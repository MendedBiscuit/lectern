#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy>=1.24", "scipy>=1.10"]
# ///
"""lectern ramp — play a lecture at two speeds.

1.2x while the lecturer is writing, 2x otherwise.

HOW IT DECIDES
  Not by counting dark pixels. On a document camera pages get swapped, so the
  ink total resets and never accumulates. It uses persistence instead: pixels
  dark at t, not dark at t-D, still dark at t+D. Written ink stays; hands,
  sleeves and the pen move on and are rejected.

  Hysteresis and a minimum segment length are load-bearing. Without them the
  speed changes every few seconds and the result is unwatchable.

WHERE IT DOES NOT APPLY
  This detects writing. A slide lecture has no ink to persist, and a blackboard
  shot from the back of a theatre is usually too coarse. For those, ramp by
  speech (silencedetect) or not at all.

  lectern ramp run FILE -o OUT          detect, plan and render
  lectern ramp detect FILE              analysis only  -> work/newink.npy
  lectern ramp plan   FILE              segments only  -> work/segments.json
  lectern ramp render FILE -o OUT       encode only
  lectern ramp verify FILE OUT          side-by-side frames checking the map
"""

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from scipy.ndimage import uniform_filter1d

W, H = 480, 270          # analysis resolution; enough for ink, cheap to hold in RAM


# ----------------------------------------------------------------- helpers --

def probe(path: Path) -> tuple[float, float]:
    """(duration_seconds, fps)"""
    dur = float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip())
    rate = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=r_frame_rate", "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip()
    num, _, den = rate.partition("/")
    fps = float(num) / float(den or 1)
    return dur, fps


def work_dir(a) -> Path:
    d = Path(a.work) if a.work else Path(a.video).with_suffix("").parent / ".lectern-ramp"
    d.mkdir(parents=True, exist_ok=True)
    return d


def hms(s: float) -> str:
    m, sec = divmod(int(s), 60)
    return f"{m:d}:{sec:02d}"


# ------------------------------------------------------------------ detect --

def cmd_detect(a) -> int:
    wd = work_dir(a)
    raw = wd / "gray.raw"
    src = Path(a.video)
    dur, _ = probe(src)

    if not raw.exists() or a.force:
        print(f"sampling {hms(dur)} at 1 fps -> {W}x{H} gray ...", file=sys.stderr)
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-v", "error", "-stats", "-nostdin", "-i", str(src),
             "-vf", f"fps=1,scale={W}:{H},format=gray",
             "-f", "rawvideo", "-y", str(raw)], check=True)

    arr = np.fromfile(raw, dtype=np.uint8).reshape(-1, H, W)
    n = arr.shape[0]
    print(f"frames={n} ({n / 60:.1f} min)", file=sys.stderr)

    # Drop pillarbox bars. A column never brighter than 16 anywhere in the
    # lecture is not part of the picture; counted as permanent ink it would
    # swamp the signal.
    colmax = arr.max(axis=(0, 1))
    keep = np.where(colmax > 16)[0]
    if len(keep) and (keep[0] > 0 or keep[-1] < W - 1):
        print(f"cropping dead columns: keeping {keep[0]}..{keep[-1]} of {W}", file=sys.stderr)
        arr = arr[:, :, keep[0]:keep[-1] + 1]

    mask = arr < a.thresh
    del arr

    D = a.persist
    newink = np.zeros(n, np.float32)
    churn = np.zeros(n, np.float32)
    for t in range(n):
        m0 = mask[max(0, t - D)]
        m1 = mask[t]
        m2 = mask[min(n - 1, t + D)]
        appeared = m1 & ~m0
        newink[t] = (appeared & m2).sum()      # written, and it stayed
        churn[t] = (m1 ^ m0).sum()             # page swaps, camera moves

    area = mask.shape[1] * mask.shape[2]
    newink /= area
    churn /= area
    np.save(wd / "newink.npy", newink)
    np.save(wd / "churn.npy", churn)

    sm = uniform_filter1d(newink, size=7) * 100
    pct = np.percentile(sm, [25, 50, 75, 90, 95, 99])
    print("new-ink %  p25/50/75/90/95/99: " + " ".join(f"{v:.3f}" for v in pct), file=sys.stderr)
    print(f"wrote {wd}/newink.npy", file=sys.stderr)
    print("\nPick --enter / --exit for `plan` from that distribution: enter around\n"
          "p75-p90, exit around p50. The defaults (0.70 / 0.35) are not universal.",
          file=sys.stderr)
    return 0


# -------------------------------------------------------------------- plan --

def runs(labels: np.ndarray) -> list[list]:
    out, s = [], 0
    for i in range(1, len(labels)):
        if labels[i] != labels[s]:
            out.append([s, i, bool(labels[s])])
            s = i
    out.append([s, len(labels), bool(labels[s])])
    return out


def cmd_plan(a) -> int:
    wd = work_dir(a)
    src = Path(a.video)
    dur, _ = probe(src)
    newink = np.load(wd / "newink.npy") * 100
    sm = uniform_filter1d(newink, size=9)
    n = len(sm)

    state = False
    lab = np.zeros(n, bool)
    for i, v in enumerate(sm):
        if state:
            if v < a.exit_:
                state = False
        elif v > a.enter:
            state = True
        lab[i] = state

    # top and tail are bumpers and title cards, never writing
    lab[:15] = False
    lab[-15:] = False

    r = runs(lab)
    # Absorb anything shorter than --min-seg into whichever neighbour is longer,
    # then merge like with like. This is what stops the speed changing constantly.
    changed = True
    while changed:
        changed = False
        for i, (s, e, _v) in enumerate(r):
            if e - s < a.min_seg and len(r) > 1:
                if i == 0:
                    r[1][0] = s
                elif i == len(r) - 1:
                    r[-2][1] = e
                elif (r[i - 1][1] - r[i - 1][0]) >= (r[i + 1][1] - r[i + 1][0]):
                    r[i - 1][1] = e
                else:
                    r[i + 1][0] = s
                r.pop(i)
                changed = True
                break
    merged = [r[0]]
    for s, e, v in r[1:]:
        if v == merged[-1][2]:
            merged[-1][1] = e
        else:
            merged.append([s, e, v])

    segs = []
    for s, e, v in merged:
        segs.append({"start": round(s * dur / n, 3),
                     "end": round(e * dur / n, 3),
                     "speed": a.write_speed if v else a.idle_speed,
                     "writing": v})
    segs[-1]["end"] = dur

    wr = sum(s["end"] - s["start"] for s in segs if s["writing"])
    idle = sum(s["end"] - s["start"] for s in segs if not s["writing"])
    out = sum((s["end"] - s["start"]) / s["speed"] for s in segs)
    lens = np.array([s["end"] - s["start"] for s in segs])
    e = sys.stderr
    print(f"segments: {len(segs)}", file=e)
    print(f"  writing {wr / 60:6.1f} min ({wr / dur * 100:3.0f}%) @ {a.write_speed}x", file=e)
    print(f"  idle    {idle / 60:6.1f} min ({idle / dur * 100:3.0f}%) @ {a.idle_speed}x", file=e)
    print(f"  source  {dur / 60:6.1f} min  ->  output {out / 60:.1f} min  "
          f"(saves {(dur - out) / 60:.1f} min)", file=e)
    print(f"  segment length: min {lens.min():.0f}s median {np.median(lens):.0f}s "
          f"max {lens.max():.0f}s", file=e)
    json.dump(segs, (wd / "segments.json").open("w"), indent=1)
    print(f"wrote {wd}/segments.json", file=e)
    return 0


# ------------------------------------------------------------------ render --

def cmd_render(a) -> int:
    wd = work_dir(a)
    src = Path(a.video)
    segs = json.load((wd / "segments.json").open())
    if not a.out:
        print("lectern ramp render: -o OUT is required", file=sys.stderr)
        return 2
    out = Path(a.out)
    _dur, fps = probe(src)
    parts = wd / "parts"
    parts.mkdir(exist_ok=True)

    if a.test:
        segs = segs[a.test_from:a.test_from + 6]
        out = wd / "test.mp4"
        print(f"test mode: segments {a.test_from}..{a.test_from + len(segs)} -> {out}", file=sys.stderr)

    def one(i_seg):
        i, s = i_seg
        dur = s["end"] - s["start"]
        outdur = dur / s["speed"]
        dst = parts / f"{i:04d}.ts"
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
            "-ss", f"{s['start']:.3f}", "-t", f"{dur:.3f}", "-i", str(src),
            "-filter:v", f"setpts=PTS/{s['speed']}",
            # Limiter before the pad: atempo plus an AAC re-encode otherwise
            # pushes peaks to 0 dBFS. apad plus an exact -t pins audio and video
            # to the same length; without it each segment's audio lands ~10 ms
            # short, the concat demuxer offsets each stream by its own duration,
            # and a hundred segments accumulate about a second of A/V drift.
            "-filter:a", f"atempo={s['speed']},alimiter=limit=0.891:level=false:latency=true,apad",
            "-t", f"{outdur:.3f}",
            "-r", f"{fps:.4f}",
            "-c:v", "libx264", "-preset", a.preset, "-crf", str(a.crf), "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "1",
            "-avoid_negative_ts", "make_zero", "-muxdelay", "0",
            "-f", "mpegts", "-y", str(dst),
        ]
        r = subprocess.run(cmd, capture_output=True, text=True)
        return (i, r.returncode == 0, r.stderr[-400:] if r.returncode else str(dst))

    # One ffmpeg per segment, in parallel. A single filtergraph with one trim
    # branch per segment makes ffmpeg push every frame down every branch and
    # takes hours. This way a hundred segments is about 90 seconds on 16 cores.
    print(f"rendering {len(segs)} segments on {a.jobs} workers ...", file=sys.stderr)
    results = list(ThreadPoolExecutor(max_workers=a.jobs).map(one, enumerate(segs)))
    bad = [r for r in results if not r[1]]
    if bad:
        print(f"FAILED {len(bad)} segments; first error:\n{bad[0][2]}", file=sys.stderr)
        return 1

    lst = wd / "parts.txt"
    with lst.open("w") as f:
        for i, _ in enumerate(segs):
            f.write(f"file '{parts / f'{i:04d}.ts'}'\n")
    print("concatenating ...", file=sys.stderr)
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
         "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c", "copy", "-movflags", "+faststart", "-y", str(out)],
        capture_output=True, text=True)
    if r.returncode:
        print(r.stderr[-600:], file=sys.stderr)
        return 1
    newdur, _ = probe(out)
    print(f"wrote {out}  ({hms(newdur)})")
    return 0


# ------------------------------------------------------------------ verify --

def cmd_verify(a) -> int:
    wd = work_dir(a)
    src, dst = Path(a.video), Path(a.out)
    segs = json.load((wd / "segments.json").open())

    def src_to_out(T):
        acc = 0.0
        for s in segs:
            if T < s["end"]:
                return acc + (T - s["start"]) / s["speed"], s
            acc += (s["end"] - s["start"]) / s["speed"]
        return acc, segs[-1]

    mapdir = wd / "map"
    mapdir.mkdir(exist_ok=True)
    times = [float(t) for t in a.at.split(",")] if a.at else None
    if times is None:
        d, _ = probe(src)
        times = [d * f for f in (0.15, 0.4, 0.65, 0.9)]

    for T in times:
        ot, seg = src_to_out(T)
        for tag, f, t in (("src", src, T), ("out", dst, ot)):
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error",
                            "-ss", f"{t:.3f}", "-i", str(f), "-frames:v", "1",
                            "-y", str(mapdir / f"{tag}_{int(T)}.png")], check=True)
        if a.montage:
            subprocess.run(["magick", str(mapdir / f"src_{int(T)}.png"),
                            str(mapdir / f"out_{int(T)}.png"), "+append",
                            "-resize", "1200x", str(mapdir / f"pair_{int(T)}.png")], check=True)
        kind = f"WRITE {seg['speed']}x" if seg["writing"] else f"idle  {seg['speed']}x"
        print(f"  src {hms(T)} ({kind}) -> out {hms(ot)}", file=sys.stderr)
    print(f"frames in {mapdir}/ — each pair should show the same board. If not, "
          f"the segment map and the render disagree.")
    return 0


# -------------------------------------------------------------------- main --

def main() -> int:
    p = argparse.ArgumentParser(prog="lectern ramp", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(q, video=True):
        if video:
            q.add_argument("video", help="source recording")
        q.add_argument("--work", help="scratch dir (default: .lectern-ramp beside the video)")

    d = sub.add_parser("detect", help="measure where writing happens")
    common(d)
    d.add_argument("--thresh", type=int, default=120, help="ink is darker than this (0-255)")
    d.add_argument("--persist", type=int, default=4, help="seconds of look-back/look-ahead")
    d.add_argument("--force", action="store_true", help="re-extract frames even if cached")
    d.set_defaults(fn=cmd_detect)

    pl = sub.add_parser("plan", help="turn the measurement into speed segments")
    common(pl)
    pl.add_argument("--write-speed", type=float, default=1.2)
    pl.add_argument("--idle-speed", type=float, default=2.0)
    pl.add_argument("--enter", type=float, default=0.70, help="%% of frame, start of writing")
    pl.add_argument("--exit", dest="exit_", type=float, default=0.35, help="%% of frame, end of writing")
    pl.add_argument("--min-seg", type=int, default=5, help="seconds; below this the speed flaps")
    pl.set_defaults(fn=cmd_plan)

    r = sub.add_parser("render", help="encode the ramped file")
    common(r)
    r.add_argument("-o", "--out")
    r.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 4))
    r.add_argument("--crf", type=int, default=21)
    r.add_argument("--preset", default="veryfast")
    r.add_argument("--test", action="store_true", help="render six segments only")
    r.add_argument("--test-from", type=int, default=20)
    r.set_defaults(fn=cmd_render)

    v = sub.add_parser("verify", help="prove the output still shows the right thing")
    common(v)
    v.add_argument("out", help="the ramped file")
    v.add_argument("--at", help="comma-separated source timestamps in seconds")
    v.add_argument("--montage", action="store_true", help="also build side-by-side pairs (needs magick)")
    v.set_defaults(fn=cmd_verify)

    a = sub.add_parser("run", help="detect + plan + render")
    common(a)
    a.add_argument("-o", "--out", required=True)
    a.add_argument("--thresh", type=int, default=120)
    a.add_argument("--persist", type=int, default=4)
    a.add_argument("--force", action="store_true")
    a.add_argument("--write-speed", type=float, default=1.2)
    a.add_argument("--idle-speed", type=float, default=2.0)
    a.add_argument("--enter", type=float, default=0.70)
    a.add_argument("--exit", dest="exit_", type=float, default=0.35)
    a.add_argument("--min-seg", type=int, default=5)
    a.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 4))
    a.add_argument("--crf", type=int, default=21)
    a.add_argument("--preset", default="veryfast")
    a.add_argument("--test", action="store_true")
    a.add_argument("--test-from", type=int, default=20)
    a.set_defaults(fn=lambda ns: cmd_detect(ns) or cmd_plan(ns) or cmd_render(ns))

    ns = p.parse_args()
    return ns.fn(ns)


if __name__ == "__main__":
    sys.exit(main())
