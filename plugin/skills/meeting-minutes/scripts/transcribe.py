"""Transcription: faster-whisper (via whisperx) + word alignment + speaker diarization,
with speaker-name matching against saved voice profiles (see speaker_profiles.py).
Runs on an NVIDIA GPU when there is one, otherwise on CPU (slower, same output).

Usage (use the kit's venv python):
    python transcribe.py <audio_path> [--out output.txt] [--attendees "Name1,Name2"]
                         [--model large-v3] [--no-diarize] [--fresh]

Needs HF_TOKEN (set by the setup wizard) for speaker diarization.
Settings come from ~/.claude/meeting-minutes/config.json ("model", "device").

A long CPU run can take over an hour, so progress is checkpointed next to the output
(<out>.ckpt): if the run is interrupted, running the same command again resumes after the
last finished stage. --fresh ignores and deletes the checkpoint. While running, the PC is
kept from going to sleep (closing the lid may still sleep it).

Writes <out> (readable transcript) and <out>.segments.json (used to name and enroll voices).
"""
import argparse
import bisect
import glob
import json
import os
import shutil
import site
import sys
import time

# Nothing about a meeting leaves this PC: pyannote reports usage (audio length, speaker counts) to its
# servers by default, and Hugging Face sends usage data with downloads. Both off, always.
os.environ["PYANNOTE_METRICS_ENABLED"] = "false"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"

DATA_DIR = os.environ.get("MINUTES_HOME") or os.path.join(os.path.expanduser("~"), ".claude", "meeting-minutes")

# CUDA DLL PATH gotcha: nvidia pip packages ship their DLLs but CTranslate2/torch only
# find them via PATH, not os.add_dll_directory(). No-op on CPU machines.
for base in site.getsitepackages():
    for bindir in glob.glob(os.path.join(base, "nvidia", "*", "bin")):
        os.environ["PATH"] = bindir + os.pathsep + os.environ["PATH"]

import pandas as pd
import torch
import whisperx
import whisperx.diarize

from speaker_profiles import ensure_hf_token, match_speakers, pinned_model, unresolved_candidates


def keep_awake():
    """Windows: don't let the PC idle-sleep while this process runs (auto-reset on exit)."""
    if os.name == "nt":
        try:
            import ctypes
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001)  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
        except Exception:
            pass


def load_config():
    p = os.path.join(DATA_DIR, "config.json")
    if os.path.exists(p):
        with open(p, encoding="utf-8-sig") as f:
            return json.load(f)
    return {}


def pick_device(cfg):
    want = cfg.get("device", "auto")
    if want == "auto":
        return "cuda" if torch.cuda.is_available() else "cpu"
    return want


class Checkpoint:
    """Stage results saved beside the output, valid only for the same audio + model."""

    def __init__(self, out_path, audio_path, model_name, fresh):
        self.dir = out_path + ".ckpt"
        self.key = f"{os.path.getsize(audio_path)}:{int(os.path.getmtime(audio_path))}:{model_name}"
        keyfile = os.path.join(self.dir, "key.txt")
        if fresh or not (os.path.exists(keyfile) and open(keyfile).read() == self.key):
            shutil.rmtree(self.dir, ignore_errors=True)
        os.makedirs(self.dir, exist_ok=True)
        with open(keyfile, "w") as f:
            f.write(self.key)

    def path(self, name):
        return os.path.join(self.dir, name)

    def has(self, name):
        return os.path.exists(self.path(name))

    def clear(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def transcribe(audio_path, model_name, device, ckpt, attendees=None, diarize=True):
    t0 = time.time()
    cuda = device == "cuda"
    compute_type = "int8_float16" if cuda else "int8"
    batch_size = 8 if cuda else 4
    print(f"device={device} model={model_name} compute={compute_type}", flush=True)
    audio = whisperx.load_audio(audio_path)

    # ---- stage 1: speech-to-text + word alignment (the long part on a CPU)
    if ckpt.has("asr.json"):
        with open(ckpt.path("asr.json"), encoding="utf-8") as f:
            result = json.load(f)
        print(f"[resume] reusing finished speech-to-text ({len(result['segments'])} segments)", flush=True)
    else:
        model = whisperx.load_model(pinned_model(f"Systran/faster-whisper-{model_name}"), device=device,
                                   compute_type=compute_type, language="en")
        result = model.transcribe(audio, batch_size=batch_size)
        print(f"[{time.time()-t0:.0f}s] transcribe done, {len(result['segments'])} segments", flush=True)
        align_model, align_meta = whisperx.load_align_model(language_code="en", device=device)
        result = whisperx.align(result["segments"], align_model, align_meta, audio, device=device)
        print(f"[{time.time()-t0:.0f}s] align done", flush=True)
        # Free the ASR + align models before diarization loads. On a 6 GB GPU, leaving them
        # resident throttled diarization to a crawl (confirmed); on CPU it just saves RAM.
        del model, align_model
        if cuda:
            torch.cuda.empty_cache()
        with open(ckpt.path("asr.json"), "w", encoding="utf-8") as f:
            json.dump(result, f, default=float)

    if not diarize:
        for seg in result["segments"]:
            seg["speaker_label"] = "?"
        return result

    # ---- stage 2: who spoke when
    if ckpt.has("diar.csv"):
        diarize_segments = pd.read_csv(ckpt.path("diar.csv"))
        print(f"[resume] reusing finished diarization ({len(diarize_segments)} turns)", flush=True)
    else:
        diarize_model = whisperx.diarize.DiarizationPipeline(
            model_name=pinned_model("pyannote/speaker-diarization-community-1"), device=device)

        def _progress(pct):
            print(f"[{time.time()-t0:.0f}s] diarizing: {pct:.0f}%", flush=True)

        kwargs = {}
        if attendees:
            # We know who is in the room: pin the speaker count instead of letting pyannote guess.
            kwargs = {"min_speakers": len(attendees), "max_speakers": len(attendees)}
        diarize_segments = diarize_model(audio, progress_callback=_progress, **kwargs)
        print(f"[{time.time()-t0:.0f}s] raw diarization done, {len(diarize_segments)} turns", flush=True)
        diarize_segments[["start", "end", "speaker"]].to_csv(ckpt.path("diar.csv"), index=False)

    result = whisperx.assign_word_speakers(diarize_segments, result)

    # ---- stage 3: match voices to enrolled names
    per_segment_names, cluster_majority, groups, row_to_group, group_rankings = match_speakers(
        audio_path, diarize_segments, device=device, candidates=attendees
    )
    print(f"[{time.time()-t0:.0f}s] speaker-profile matching done", flush=True)

    candidates = unresolved_candidates(diarize_segments, cluster_majority, groups, row_to_group, group_rankings)
    if candidates:
        print("unresolved speakers (closest voiceprint candidates, below match threshold):")
        for spk_id, ranking in candidates.items():
            print(f"  {spk_id}: " + ", ".join(f"{n} ({s:.2f})" for n, s in ranking))

    diarize_segments = diarize_segments.reset_index(drop=True)

    # Per-speaker sorted (start, end, row) lists so each whisper segment finds its
    # diarize row by binary search, not a full-dataframe scan.
    by_speaker = {}
    for i, row in diarize_segments.iterrows():
        by_speaker.setdefault(row["speaker"], []).append((row["start"], row["end"], i))
    for rows in by_speaker.values():
        rows.sort()

    def find_row(spk, t):
        rows = by_speaker.get(spk)
        if not rows:
            return None
        pos = bisect.bisect_right([s for s, _, _ in rows], t) - 1
        if pos >= 0:
            s, e, idx = rows[pos]
            if s <= t <= e:
                return idx
        return None

    for seg in result["segments"]:
        spk = seg.get("speaker")
        row_idx = find_row(spk, seg["start"])
        name = per_segment_names[row_idx] if row_idx is not None else None
        seg["speaker_label"] = name or cluster_majority.get(spk) or spk or "?"

    return result


def write_outputs(result, out_path):
    with open(out_path, "w", encoding="utf-8") as f:
        for seg in result["segments"]:
            f.write(f"[{seg['start']:.1f}-{seg['end']:.1f}] {seg['speaker_label']}: {seg['text'].strip()}\n")
    segs = [{"start": round(s["start"], 2), "end": round(s["end"], 2), "cluster": s.get("speaker"),
             "label": s["speaker_label"], "text": s["text"].strip()} for s in result["segments"]]
    with open(out_path + ".segments.json", "w", encoding="utf-8") as f:
        json.dump(segs, f, ensure_ascii=False, indent=1)
    return segs


def summarize_speakers(segs):
    """Who is in the transcript, so the user can name the unknown ones."""
    by = {}
    for s in segs:
        by.setdefault(s["label"], []).append(s)
    print("\nspeakers found:")
    for label, ss in sorted(by.items(), key=lambda kv: -sum(x["end"] - x["start"] for x in kv[1])):
        mins = sum(x["end"] - x["start"] for x in ss) / 60
        known = not label.startswith("SPEAKER_") and label != "?"
        print(f"  {label}: {mins:.1f} min" + ("" if known else "   <- NOT NAMED"))
        if not known:
            for x in sorted(ss, key=lambda x: x["end"] - x["start"], reverse=True)[:2]:
                print(f"      [{x['start']:.0f}s] {x['text'][:140]}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("audio_path")
    ap.add_argument("--out", default=None)
    ap.add_argument("--attendees", default=None,
                    help="comma-separated enrolled names present this session, e.g. 'Alex,Sam,Riley'. "
                         "Pins the diarization speaker count and limits voice-match candidates to these people.")
    ap.add_argument("--model", default=None, help="override config model (large-v3, medium.en, small.en)")
    ap.add_argument("--no-diarize", action="store_true", help="skip speaker labels (words only)")
    ap.add_argument("--fresh", action="store_true", help="ignore and delete any checkpoint from an interrupted run")
    args = ap.parse_args()

    cfg = load_config()
    ensure_hf_token()
    if not args.no_diarize and "HF_TOKEN" not in os.environ:
        sys.exit("HF_TOKEN not set. Run the setup wizard (skill: minutes-setup).")

    keep_awake()
    attendees = [a.strip() for a in args.attendees.split(",")] if args.attendees else None
    device = pick_device(cfg)
    model_name = args.model or cfg.get("model", "large-v3")
    out_path = args.out or os.path.splitext(args.audio_path)[0] + ".whisper.txt"
    ckpt = Checkpoint(out_path, args.audio_path, model_name + ("" if args.no_diarize else "+d"), args.fresh)
    result = transcribe(args.audio_path, model_name, device, ckpt, attendees=attendees, diarize=not args.no_diarize)
    segs = write_outputs(result, out_path)
    ckpt.clear()
    print(f"written to {out_path}")
    summarize_speakers(segs)
