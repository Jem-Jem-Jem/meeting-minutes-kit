# -*- coding: utf-8 -*-
"""End-to-end check of the transcription path, run by the setup wizard.

Makes a ~40 s two-voice speech file with Windows' built-in text-to-speech, runs the real
transcribe.py on it (model download, speech-to-text, alignment, diarization, voice
matching) and reports the speed, so the wizard can estimate a real meeting's run time.

    python smoke_test.py [--model large-v3] [--no-diarize]

Prints a final line:  SMOKE_RESULT {"ok": true, "audio_s": ..., "elapsed_s": ..., "rtf": ...}
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import wave

LINES = [
    "Good morning everyone. This is a short test of the meeting minutes tool.",
    "Thank you. I will send the programme fact sheet to the partner by Friday.",
    "The budget of two thousand dollars is confirmed for the spring campaign.",
    "Understood. I will review the creative before the fifth of February.",
    "Please note that twelve applications were submitted and nine were approved.",
    "That is all for today. Thank you all for joining.",
]

PS_TTS = r"""
param([string]$Out, [string]$Text, [int]$VoiceIndex)
Add-Type -AssemblyName System.Speech
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$v = @($s.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like 'en*' })
if ($v.Count -eq 0) { $v = @($s.GetInstalledVoices() | Where-Object { $_.Enabled }) }
$s.SelectVoice($v[$VoiceIndex % $v.Count].VoiceInfo.Name)
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$s.SetOutputToWaveFile($Out, $fmt)
$s.Speak($Text)
$s.Dispose()
"""


def make_audio(path, repeat=1):
    tmp = tempfile.mkdtemp(prefix="minutes-smoke-")
    ps1 = os.path.join(tmp, "tts.ps1")
    with open(ps1, "w", encoding="utf-8") as f:
        f.write(PS_TTS)
    parts = []
    one = []
    for i, line in enumerate(LINES):
        p = os.path.join(tmp, f"{i}.wav")
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1,
                            "-Out", p, "-Text", line, "-VoiceIndex", str(i % 2)],
                           capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(p):
            raise SystemExit("text-to-speech failed: " + (r.stderr or r.stdout)[:400])
        one.append(p)
    parts = one * repeat
    with wave.open(path, "wb") as out:
        for i, p in enumerate(parts):
            with wave.open(p, "rb") as w:
                if i == 0:
                    out.setparams(w.getparams())
                out.writeframes(w.readframes(w.getnframes()))
                out.writeframes(b"\x00\x00" * 8000)  # 0.5 s gap
    with wave.open(path, "rb") as w:
        return w.getnframes() / w.getframerate()


def merge_check():
    """Proves ffmpeg/ffprobe/numpy and merge_mics.py work: fake two recorders from the test
    speech (mic B = mic A started 1.5 s later), each saved as two chunks, then merge and check
    the measured offset."""
    import re
    here = os.path.dirname(os.path.abspath(__file__))
    merge = os.path.normpath(os.path.join(here, "..", "..", "meeting-minutes", "scripts", "merge_mics.py"))
    tmp = tempfile.mkdtemp(prefix="minutes-merge-")
    src = os.path.join(tmp, "src.wav")
    audio_s = make_audio(src, 3)
    a_dir, b_dir = os.path.join(tmp, "A"), os.path.join(tmp, "B")
    os.makedirs(a_dir); os.makedirs(b_dir)
    delayed = os.path.join(tmp, "delayed.wav")
    for cmd in (["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-af", "adelay=1500:all=1", delayed],
                ["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-f", "segment", "-segment_time", "70", "-c", "copy", os.path.join(a_dir, "%03d.wav")],
                ["ffmpeg", "-y", "-loglevel", "error", "-i", delayed, "-f", "segment", "-segment_time", "70", "-c", "copy", os.path.join(b_dir, "%03d.wav")]):
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print("ffmpeg failed:", r.stderr[-400:]); sys.exit(1)
    out = os.path.join(tmp, "merged.wav")
    r = subprocess.run([sys.executable, merge, "--mic-a", a_dir, "--mic-b", b_dir, "--out", out], capture_output=True, text=True)
    print(r.stdout + r.stderr)
    m = re.search(r"offset = ([+-][0-9.]+) s", r.stdout)
    ok = r.returncode == 0 and m and abs(float(m.group(1)) + 1.5) < 0.06 and os.path.exists(out)
    print("MERGE_CHECK", "ok" if ok else "FAILED", f"(expected offset -1.5 s, source {audio_s:.0f} s)")
    sys.exit(0 if ok else 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--merge-check", action="store_true", help="test the two-microphone merge instead of transcription")
    ap.add_argument("--model", default=None)
    ap.add_argument("--no-diarize", action="store_true")
    ap.add_argument("--repeat", type=int, default=1, help="repeat the test speech N times (longer clip for timing)")
    a = ap.parse_args()
    if a.merge_check:
        merge_check()

    here = os.path.dirname(os.path.abspath(__file__))
    transcribe = os.path.join(here, "..", "..", "meeting-minutes", "scripts", "transcribe.py")
    transcribe = os.path.normpath(transcribe)
    if not os.path.exists(transcribe):  # flat layout fallback
        transcribe = os.path.join(here, "transcribe.py")

    wav = os.path.join(tempfile.gettempdir(), "minutes-smoke.wav")
    out = os.path.join(tempfile.gettempdir(), "minutes-smoke.whisper.txt")
    audio_s = make_audio(wav, a.repeat)
    print(f"test audio: {audio_s:.0f} s", flush=True)

    cmd = [sys.executable, transcribe, wav, "--out", out]
    if a.model:
        cmd += ["--model", a.model]
    if a.no_diarize:
        cmd += ["--no-diarize"]
    t0 = time.time()
    r = subprocess.run(cmd)
    elapsed = time.time() - t0
    ok = r.returncode == 0 and os.path.exists(out)
    text = ""
    if ok:
        with open(out, encoding="utf-8") as f:
            text = f.read()
        print("\n--- transcript ---\n" + text)
        ok = "budget" in text.lower() or "meeting" in text.lower()
    # elapsed includes one-off model downloads on a first run; the wizard runs this twice
    # only if it needs a clean speed number.
    print("SMOKE_RESULT " + json.dumps({"ok": ok, "audio_s": round(audio_s, 1), "elapsed_s": round(elapsed, 1),
                                         "rtf": round(elapsed / audio_s, 2),
                                         "speakers": sorted({l.split("] ")[1].split(":")[0] for l in text.splitlines() if "] " in l})}))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
