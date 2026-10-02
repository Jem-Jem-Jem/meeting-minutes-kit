"""Voice-print profiles for speaker ID across meetings.
Reuses the diarization pipeline's own embedding model, no extra dependency.

Profiles are biometric data. They live in ~/.claude/meeting-minutes/speaker_profiles.json,
never inside the kit, and must never be committed or published.

CLI (run with the kit's venv python):
    python speaker_profiles.py list
    python speaker_profiles.py enroll "Name" audio.wav 12.5-20.0 45-52 ...
        clips = start-end seconds of clean solo speech; each call ADDS a vector
    python speaker_profiles.py enroll-cluster audio.wav transcript.txt.segments.json SPEAKER_01 "Name"
        the easy route: after a transcription, enroll an unnamed speaker from their longest
        clean turns (no timestamps to hunt for)
    python speaker_profiles.py merge other_profiles.json
        add people from another profiles file (a newer team bundle); people already on file are kept as they are
    python speaker_profiles.py remove "Name" [...]
        delete a person's voice print from this PC (someone left, or withdrew consent)
    python speaker_profiles.py relabel transcript.txt SPEAKER_01=Name [SPEAKER_02=Name2 ...]
        rename speakers in a finished transcript (and its .segments.json) without re-running it
"""
import json
import os
import shutil
import sys

import numpy as np
import torch
import whisperx
from pyannote.audio import Inference, Model
from pyannote.core import Segment

DATA_DIR = os.environ.get("MINUTES_HOME") or os.path.join(os.path.expanduser("~"), ".claude", "meeting-minutes")
PROFILES_PATH = os.path.join(DATA_DIR, "speaker_profiles.json")
MATCH_THRESHOLD = 0.7
_EMBED_CHECKPOINT = "pyannote/speaker-diarization-community-1"

# Hugging Face models pinned to exact commits: a changed or hijacked upstream repo cannot change what runs here.
# To move to a newer model, test it, then update its commit here.
MODEL_REVISIONS = {
    "Systran/faster-whisper-large-v3": "edaa852ec7e145841d8ffdb056a99866b5f0a478",
    "Systran/faster-whisper-medium.en": "a29b04bd15381511a9af671baec01072039215e3",
    "Systran/faster-whisper-small.en": "d1d751a5f8271d482d14ca55d9e2deeebbae577f",
    "pyannote/speaker-diarization-community-1": "3533c8cf8e369892e6b79ff1bf80f7b0286a54ee",
}


def pinned_model(repo):
    """Local folder of `repo` at its pinned commit (downloaded once, then read from the HF cache)."""
    from huggingface_hub import snapshot_download
    if repo not in MODEL_REVISIONS:
        sys.exit(f"{repo} is not one of the kit's pinned models: {', '.join(MODEL_REVISIONS)}")
    return snapshot_download(repo, revision=MODEL_REVISIONS[repo], token=os.environ.get("HF_TOKEN"))


def ensure_hf_token():
    """The wizard saves HF_TOKEN as a user env var. A session opened before that won't have
    it in its environment, so read it from the registry instead of demanding a restart."""
    if os.environ.get("HF_TOKEN"):
        return
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            os.environ["HF_TOKEN"] = winreg.QueryValueEx(k, "HF_TOKEN")[0]
    except Exception:
        pass


def _embedding_model(device="cpu"):
    m = Model.from_pretrained(pinned_model(_EMBED_CHECKPOINT), subfolder="embedding")
    return Inference(m, window="whole", device=torch.device(device))


def _load_waveform_file(audio_path):
    """torchcodec (pyannote's default file decoder) is unreliable on Windows, so load via
    whisperx's ffmpeg-based loader and hand pyannote the preloaded waveform dict, which it
    accepts in place of a file path."""
    audio = whisperx.load_audio(audio_path)  # float32 numpy, mono, 16kHz
    waveform = torch.from_numpy(audio).unsqueeze(0)
    return {"waveform": waveform, "sample_rate": 16000}


def _load_raw():
    """{name: [vector, ...]}, one vector per enroll() call. Upgrades the old
    one-vector-per-name format into a one-item list on read."""
    if not os.path.exists(PROFILES_PATH):
        return {}
    with open(PROFILES_PATH, encoding="utf-8-sig") as f:
        raw = json.load(f)
    return {k: (v if isinstance(v[0], list) else [v]) for k, v in raw.items()}


def _save_raw(raw):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(PROFILES_PATH, "w", encoding="utf-8") as f:
        json.dump(raw, f, indent=2)


def load_profiles():
    """{name: centroid}, the mean over every enrollment vector for that name."""
    return {k: np.mean(np.array(vs), axis=0) for k, vs in _load_raw().items()}


def enroll(name, audio_path, clips, device="cpu"):
    """clips: list of (start, end) seconds of clean solo speech. Additive: each call adds
    one more vector to this person's profile (averaged at match time)."""
    inf = _embedding_model(device)
    file = _load_waveform_file(audio_path)
    embeds = [np.asarray(inf.crop(file, Segment(s, e))).reshape(-1) for s, e in clips]
    centroid = np.mean(embeds, axis=0)
    raw = _load_raw()
    raw.setdefault(name, []).append(centroid.tolist())
    _save_raw(raw)
    print(f"enrolled {name} from {len(clips)} clip(s) ({len(raw[name])} enrollments on file total)")


def _cosine(a, b):
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


MIN_SEGMENT_DURATION = 0.3  # shorter clips give unreliable embeddings, skip them
MERGE_GAP = 1.0  # seconds. Raw diarize output is choppy; merging adjacent same-speaker rows
# this close together cuts embedding calls sharply with no accuracy loss.


def _merge_adjacent(diarize_segments, gap=MERGE_GAP):
    """Collapse consecutive same-speaker rows separated by less than `gap` seconds into one
    group. Returns (groups, row_to_group)."""
    groups = []
    row_to_group = []
    for _, row in diarize_segments.iterrows():
        if groups and groups[-1]["speaker"] == row["speaker"] and row["start"] - groups[-1]["end"] < gap:
            groups[-1]["end"] = row["end"]
        else:
            groups.append({"start": row["start"], "end": row["end"], "speaker": row["speaker"]})
        row_to_group.append(len(groups) - 1)
    return groups, row_to_group


def match_speakers(audio_path, diarize_segments, device="cpu", threshold=MATCH_THRESHOLD, candidates=None):
    """diarize_segments: the DataFrame whisperx' DiarizationPipeline returns.

    Matches per merged same-speaker stretch, not per whole cluster: diarization clustering
    can drift over a long recording and merge two people under one SPEAKER_ID. Matching
    finer than the cluster lets a saved voiceprint override a wrong cluster label.

    Returns (per_segment names/None, cluster_majority {SPEAKER_ID: name_or_None}, groups,
    row_to_group, group_rankings).
    """
    diarize_segments = diarize_segments.reset_index(drop=True)
    profiles = load_profiles()
    if candidates:
        # Restrict to known-present people: cuts false matches against an absent person.
        profiles = {k: v for k, v in profiles.items() if k in candidates}
    if not profiles:
        return [None] * len(diarize_segments), {}, [], [], []
    inf = _embedding_model(device)
    file = _load_waveform_file(audio_path)

    groups, row_to_group = _merge_adjacent(diarize_segments)
    print(f"match_speakers: {len(diarize_segments)} raw turns merged to {len(groups)} groups "
          f"({len(profiles)} enrolled profiles)", flush=True)

    group_names = []
    group_rankings = []  # full sorted [(name, score), ...] per group, kept even below threshold
    for i, g in enumerate(groups):
        if i and i % 25 == 0:
            print(f"match_speakers: embedded {i}/{len(groups)} groups", flush=True)
        if g["end"] - g["start"] < MIN_SEGMENT_DURATION:
            group_names.append(None)
            group_rankings.append([])
            continue
        try:
            emb = np.asarray(inf.crop(file, Segment(g["start"], g["end"]))).reshape(-1)
        except Exception:
            group_names.append(None)
            group_rankings.append([])
            continue
        ranking = sorted(((n, _cosine(emb, ref)) for n, ref in profiles.items()), key=lambda x: x[1], reverse=True)
        group_rankings.append(ranking)
        group_names.append(ranking[0][0] if ranking and ranking[0][1] > threshold else None)

    per_segment = [group_names[gi] for gi in row_to_group]

    # per-cluster fallback (majority vote among that cluster's confident matches)
    cluster_majority = {}
    for spk_id, group in diarize_segments.groupby("speaker"):
        names = [per_segment[i] for i in group.index if per_segment[i] is not None]
        cluster_majority[spk_id] = max(set(names), key=names.count) if names else None

    return per_segment, cluster_majority, groups, row_to_group, group_rankings


def unresolved_candidates(diarize_segments, cluster_majority, groups, row_to_group, group_rankings, top_n=3):
    """For each SPEAKER_ID that came back unresolved, rank it against every enrolled profile
    anyway (uses the cluster's longest group, the most reliable single embedding)."""
    diarize_segments = diarize_segments.reset_index(drop=True)
    out = {}
    for spk_id, name in cluster_majority.items():
        if name is not None:
            continue
        group_idxs = {row_to_group[i] for i in diarize_segments.index[diarize_segments["speaker"] == spk_id]}
        if not group_idxs:
            continue
        longest_gi = max(group_idxs, key=lambda gi: groups[gi]["end"] - groups[gi]["start"])
        ranking = group_rankings[longest_gi]
        if ranking:
            out[spk_id] = ranking[:top_n]
    return out


def enroll_cluster(audio_path, segments_json, cluster, name, device="cpu", max_clips=6):
    """Enroll `name` from the cleanest long turns the diarizer attributed to `cluster`."""
    with open(segments_json, encoding="utf-8") as f:
        segs = json.load(f)
    mine = [s for s in segs if s["label"] == cluster or s.get("cluster") == cluster]
    good = sorted((s for s in mine if 2.0 <= s["end"] - s["start"] <= 25.0),
                  key=lambda s: s["end"] - s["start"], reverse=True)[:max_clips]
    total = sum(s["end"] - s["start"] for s in good)
    if len(good) < 2 or total < 6.0:
        sys.exit(f"not enough clean speech found for {cluster} ({len(good)} usable turns, {total:.0f}s). "
                 "Pick a speaker who talked for longer, or use 'enroll' with hand-picked clips.")
    print(f"enrolling {name} from {len(good)} turns of {cluster} ({total:.0f}s of speech)")
    enroll(name, audio_path, [(s["start"], s["end"]) for s in good], device=device)


def merge_profiles(other_path):
    with open(other_path, encoding="utf-8-sig") as f:
        other = json.load(f)
    other = {k: (v if isinstance(v[0], list) else [v]) for k, v in other.items()}
    raw = _load_raw()
    added = [k for k in other if k not in raw]
    for k in added:
        raw[k] = other[k]
    _save_raw(raw)
    print(f"merged voice profiles: {len(added)} added ({', '.join(added) or 'none'}), {len(other) - len(added)} already on file kept as is")


def remove_profiles(names):
    raw = _load_raw()
    gone = [n for n in names if raw.pop(n, None) is not None]
    if gone:
        _save_raw(raw)
    print(f"removed voice profiles: {', '.join(gone) or 'none on file'}")


def relabel(transcript_path, mapping):
    import re
    line_re = re.compile(r"^(\[[0-9.]+-[0-9.]+\] )(.+?)(: .*)$")
    with open(transcript_path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    shutil.copyfile(transcript_path, transcript_path + ".bak")
    out, n = [], 0
    for ln in lines:
        m = line_re.match(ln)
        if m and m.group(2) in mapping:
            ln = m.group(1) + mapping[m.group(2)] + m.group(3); n += 1
        out.append(ln)
    with open(transcript_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    sj = transcript_path + ".segments.json"
    if os.path.exists(sj):
        with open(sj, encoding="utf-8") as f:
            segs = json.load(f)
        for sg in segs:
            sg["label"] = mapping.get(sg["label"], sg["label"])
        with open(sj, "w", encoding="utf-8") as f:
            json.dump(segs, f, ensure_ascii=False, indent=1)
    print(f"relabelled {n} lines (backup: {transcript_path}.bak)")


if __name__ == "__main__":
    if len(sys.argv) >= 6 and sys.argv[1] == "enroll-cluster":
        ensure_hf_token()
        enroll_cluster(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5],
                       device="cuda" if torch.cuda.is_available() else "cpu")
    elif len(sys.argv) >= 3 and sys.argv[1] == "merge":
        merge_profiles(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == "remove":
        remove_profiles(sys.argv[2:])
    elif len(sys.argv) >= 4 and sys.argv[1] == "relabel":
        relabel(sys.argv[2], dict(a.split("=", 1) for a in sys.argv[3:]))
    elif len(sys.argv) >= 2 and sys.argv[1] == "list":
        for n, vs in _load_raw().items():
            print(f"{n}: {len(vs)} enrollment(s)")
    elif len(sys.argv) >= 5 and sys.argv[1] == "enroll":
        ensure_hf_token()
        clips = [tuple(float(x) for x in c.split("-")) for c in sys.argv[4:]]
        enroll(sys.argv[2], sys.argv[3], clips, device="cuda" if torch.cuda.is_available() else "cpu")
    else:
        print(__doc__)
