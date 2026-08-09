#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["faster-whisper>=1.0"]
# ///
"""lectern transcribe — audio in, timestamped transcript out.

Runs on CPU by default. distil-large-v3 does a 55 minute lecture in about five
minutes on 16 threads.

Two limits on the output:

  * VAD is a threshold, not a gradient. vad_filter drops anything scored as
    non-speech, so very quiet audio produces an empty transcript rather than a
    poor one. A few lines out of a one hour lecture means the problem is
    upstream: run `lectern probe` on the source.

  * ASR is unreliable on technical vocabulary and fails fluently: misheard
    terms come back as plausible English words, and list items can be
    interpolated. Proper nouns and notation are worst. Use the transcript for
    narrative, asides, admin and emphasis; take the content from the frames.
"""

import argparse
import sys
import time
from pathlib import Path


def ts(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def srt_ts(seconds: float) -> str:
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def main() -> int:
    p = argparse.ArgumentParser(prog="lectern transcribe", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("audio", type=Path, help="wav/mp3/mp4 — anything ffmpeg reads")
    p.add_argument("-o", "--out", type=Path, help="output file (default: AUDIO with .txt)")
    p.add_argument("--model", default="distil-large-v3",
                   help="faster-whisper model (default distil-large-v3; "
                        "large-v3 is slower and slightly better on names)")
    p.add_argument("--language", default="en")
    p.add_argument("--device", default="cpu", choices=["cpu", "cuda", "auto"])
    p.add_argument("--compute-type", default="int8",
                   help="int8 on cpu, float16 on cuda")
    p.add_argument("--threads", type=int, default=0,
                   help="cpu threads (default: all cores)")
    p.add_argument("--beam-size", type=int, default=5)
    p.add_argument("--no-vad", action="store_true",
                   help="disable voice-activity filtering. Slower and noisier, "
                        "but it will not silently discard quiet audio.")
    p.add_argument("--min-silence", type=int, default=700,
                   help="ms of silence before VAD splits a segment (default 700)")
    p.add_argument("--srt", action="store_true", help="write .srt subtitles instead of plain text")
    p.add_argument("--quiet", action="store_true", help="do not echo lines as they arrive")
    a = p.parse_args()

    if not a.audio.exists():
        print(f"lectern: no such file: {a.audio}", file=sys.stderr)
        return 1

    out = a.out or a.audio.with_suffix(".srt" if a.srt else ".txt")
    threads = a.threads or __import__("os").cpu_count() or 4

    from faster_whisper import WhisperModel

    print(f"model {a.model} on {a.device} ({a.compute_type}, {threads} threads)", file=sys.stderr)
    model = WhisperModel(a.model, device=a.device, compute_type=a.compute_type,
                         cpu_threads=threads)

    segments, info = model.transcribe(
        str(a.audio),
        language=a.language,
        beam_size=a.beam_size,
        vad_filter=not a.no_vad,
        vad_parameters=dict(min_silence_duration_ms=a.min_silence),
        # Whisper loops on repetitive input; repeated filler is enough to make it
        # emit the same sentence for minutes. Do not feed it its own tail.
        condition_on_previous_text=False,
    )
    print(f"audio {ts(info.duration)}  (after VAD: {ts(info.duration_after_vad)})", file=sys.stderr)

    t0 = time.time()
    n = 0
    last_end = 0.0
    gaps = []
    with out.open("w") as f:
        for i, s in enumerate(segments, 1):
            if s.start - last_end > 45 and last_end > 0:
                gaps.append((last_end, s.start))
            last_end = s.end
            n += 1
            text = s.text.strip()
            if a.srt:
                f.write(f"{i}\n{srt_ts(s.start)} --> {srt_ts(s.end)}\n{text}\n\n")
            else:
                f.write(f"[{ts(s.start)}] {text}\n")
            f.flush()
            if not a.quiet:
                print(f"{time.time() - t0:6.0f}s [{ts(s.start)}] {text}", flush=True)

    print(f"\nwrote {out}  ({n} segments, {ts(last_end)} of {ts(info.duration)}, "
          f"{time.time() - t0:.0f}s wall)", file=sys.stderr)

    # Coverage report. A transcript that stops at 12:00 of a 55 minute lecture
    # is indistinguishable from a complete one unless the last cue is checked.
    if info.duration and last_end < info.duration * 0.9:
        print(f"WARNING: last cue is at {ts(last_end)} but the audio runs to "
              f"{ts(info.duration)}. Something ate the tail.", file=sys.stderr)
    if n < 20 and info.duration > 300:
        print(f"WARNING: only {n} segments from {ts(info.duration)} of audio. "
              f"Usually a level problem: run 'lectern probe' on the source.",
              file=sys.stderr)
    for g0, g1 in gaps:
        print(f"   gap {ts(g0)} -> {ts(g1)} ({g1 - g0:.0f}s with no speech)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
