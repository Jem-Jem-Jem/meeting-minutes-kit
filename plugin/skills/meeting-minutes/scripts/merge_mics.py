# -*- coding: utf-8 -*-
"""Merge two table microphones (recorded as separate files, possibly in 30-minute chunks)
into ONE mono file for transcribe.py.

    python merge_mics.py --mic-a "<folder A>" --mic-b "<folder B>" --out "<meeting folder>\\audio.wav" [--samples]
    python merge_mics.py --mic-a "<folder A>" --mic-b "<folder B>" --out audio.wav --single b   # fallback

What it does (this exact procedure was worked out and verified on real DJI Mic 3 recordings):
  1. Concatenates each mic's chunks in filename order (ffmpeg concat demuxer, no re-encode).
  2. Measures the start-time offset between the two mics by cross-correlating speech windows taken
     from several places in the recording. It does NOT trust file timecodes or filenames: on the
     DJI Mic 3 the embedded timecode fields are empty and filenames are only whole seconds.
  3. Delays the earlier-timeline mic with ffmpeg's `adelay` filter. NOT `-itsoffset`: inside an
     `amix` filtergraph `-itsoffset` is silently ignored, which produces an audible echo.
  4. Re-measures the offset on the delayed file. It must be ~0 before mixing.
  5. Mixes with `amix` to mono 16-bit.
  6. With --samples, also writes 25 s clips (merged, mic A, mic B) for the human to LISTEN to.
     A hollow or phasey mix means comb filtering: rerun with --single a or --single b.

Needs ffmpeg on PATH (the setup wizard installs it) and numpy (in the kit's venv).
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

SR = 16000           # analysis sample rate (Hz)
WIN_S = 40           # analysis window length (s)
MAX_LAG_S = 6.0      # search +/- this far for the offset
TOL_S = 0.05         # windows must agree within this, or we stop and say so


def run(cmd):
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        sys.exit("command failed: " + " ".join(cmd[:4]) + " ...\n" + r.stderr.decode("utf-8", "replace")[-600:])
    return r


def chunks(folder):
    files = sorted(glob.glob(os.path.join(folder, "*.wav")))
    if not files:
        sys.exit(f"no .wav files in {folder}")
    return files


def concat(files, out):
    lst = out + ".txt"
    with open(lst, "w", encoding="utf-8") as f:
        for p in files:
            f.write("file '" + os.path.abspath(p).replace("\\", "/").replace("'", "'\\''") + "'\n")
    run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out])
    os.remove(lst)


def duration(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path])
    return float(r.stdout.decode().strip())


def window(path, start, length=WIN_S):
    r = run(["ffmpeg", "-loglevel", "error", "-ss", f"{start:.3f}", "-t", str(length), "-i", path,
             "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"])
    x = np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64)
    return (x - x.mean()) / (x.std() + 1e-9)


def lag_seconds(a, b):
    """k such that a[n+k] ~ b[n]. k < 0: a's content appears EARLIER on its own timeline."""
    n = 1 << int(np.ceil(np.log2(len(a) + len(b))))
    c = np.fft.irfft(np.fft.rfft(a, n) * np.conj(np.fft.rfft(b, n)), n)
    m = int(MAX_LAG_S * SR)
    c = np.concatenate([c[-m:], c[:m + 1]])
    i = int(np.argmax(c))
    return (i - m) / SR, float(c[i] / min(len(a), len(b)))


def measure(pa, pb, total):
    """Offset from several windows; returns (median_lag_s, [(lag, strength), ...])."""
    got = []
    for frac in (0.08, 0.25, 0.45, 0.65, 0.85):
        t = max(0.0, min(total - WIN_S - 1, total * frac))
        a, b = window(pa, t), window(pb, t)
        n = min(len(a), len(b))
        if n < SR * 10:
            continue
        got.append(lag_seconds(a[:n], b[:n]))
    if len(got) < 2:
        sys.exit("recording too short to measure the mic offset")
    best = sorted(got, key=lambda g: g[1], reverse=True)[:3]
    lags = [g[0] for g in best]
    if max(lags) - min(lags) > TOL_S:
        sys.exit(f"the mics disagree about the offset ({', '.join(f'{l:.3f}s' for l in lags)}). "
                 "Do not force a mix. Rerun with --single a or --single b.")
    return float(np.median(lags)), got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mic-a", required=True, help="folder with mic A's wav chunks")
    ap.add_argument("--mic-b", required=True, help="folder with mic B's wav chunks")
    ap.add_argument("--out", required=True, help="output wav path (mono)")
    ap.add_argument("--single", choices=["a", "b"], help="skip the mix; use only this mic (fallback)")
    ap.add_argument("--samples", action="store_true", help="also write 25 s listening samples beside --out")
    a = ap.parse_args()
    for exe in ("ffmpeg", "ffprobe"):
        if not shutil.which(exe):
            sys.exit(f"{exe} not found on PATH. Run the setup wizard.")

    tmp = tempfile.mkdtemp(prefix="mics-")
    try:
        pa, pb = os.path.join(tmp, "a.wav"), os.path.join(tmp, "b.wav")
        print("joining chunks ...", flush=True)
        concat(chunks(a.mic_a), pa)
        concat(chunks(a.mic_b), pb)
        da, db = duration(pa), duration(pb)
        print(f"mic A {da:.1f}s   mic B {db:.1f}s")

        if a.single:
            src = pa if a.single == "a" else pb
            run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-ac", "1", "-c:a", "pcm_s16le", a.out])
            print(f"single mic {a.single.upper()} written: {a.out}")
            return

        lag, got = measure(pa, pb, min(da, db))
        print("offset windows (s, strength): " + ", ".join(f"{g[0]:.3f}/{g[1]:.2f}" for g in got))
        print(f"offset = {lag:+.3f} s  " + ("(mic A content is earlier: delaying A)" if lag < 0 else "(mic B content is earlier: delaying B)"))

        delayed_src, other, name = (pa, pb, "A") if lag < 0 else (pb, pa, "B")
        ms = abs(lag) * 1000.0
        pd = os.path.join(tmp, "delayed.wav")
        run(["ffmpeg", "-y", "-loglevel", "error", "-i", delayed_src, "-af", f"adelay={ms:.2f}:all=1", pd])

        # verify BEFORE mixing: the residual offset must be ~0
        total = min(da, db) - abs(lag) - 2
        t = total * 0.5
        x, y = (window(pd, t), window(other, t))
        n = min(len(x), len(y))
        resid, strength = lag_seconds(x[:n], y[:n]) if name == "A" else lag_seconds(y[:n], x[:n])
        print(f"residual offset after delay = {resid*1000:+.1f} ms (strength {strength:.2f})")
        if abs(resid) > 0.02:
            sys.exit("alignment did not land. Do not mix. Rerun with --single a or --single b.")

        ia, ib = (pd, other) if name == "A" else (other, pd)
        run(["ffmpeg", "-y", "-loglevel", "error", "-i", ia, "-i", ib, "-filter_complex",
             "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=3", "-ac", "1", "-c:a", "pcm_s16le", a.out])
        print(f"merged file written: {a.out}  ({duration(a.out):.1f}s)")

        if a.samples:
            base = os.path.splitext(a.out)[0]
            t0 = min(300.0, max(0.0, duration(a.out) / 3))
            for label, src in (("merged", a.out), ("micA", pa), ("micB", pb)):
                dst = f"{base}.sample-{label}.wav"
                run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t0:.1f}", "-t", "25", "-i", src, "-ac", "1", dst])
                print("listen:", dst)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
