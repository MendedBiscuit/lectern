#!/usr/bin/env bash
# lectern frames — sample frames so the board or the slides can be read.
#
# One frame every 30 s suits a blackboard lecture: boards accumulate before they
# are wiped, so consecutive samples differ by a few lines and the last frame of
# each board holds everything on it.
set -euo pipefail
. "${LIB:-$(dirname "$0")}/common.sh"

FILE=""; OUT=""; EVERY=30; SCALE=""; Q=3
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
usage: lectern frames FILE [-o DIR] [options]

  -o, --out DIR       output directory (default: ./frames)
      --every SEC     one frame every SEC seconds (default 30)
      --scale W       scale to width W, keeping aspect (default: native)
      --quality N     jpeg quality, 2 best .. 31 worst (default 3)

Frames are named fNNN.jpg and NNN maps to time: frame N is at (N-1)*EVERY
seconds, give or take half an interval.
EOF
      exit 0 ;;
    -o|--out) OUT="$2"; shift 2 ;;
    --every) EVERY="$2"; shift 2 ;;
    --scale) SCALE="$2"; shift 2 ;;
    --quality) Q="$2"; shift 2 ;;
    *) FILE="$1"; shift ;;
  esac
done
[ -n "$FILE" ] || die "usage: lectern frames FILE [-o DIR]"
[ -f "$FILE" ] || die "no such file: $FILE"
[ -n "$OUT" ] || OUT="frames"
mkdir -p "$OUT"

VF="fps=1/$EVERY"
[ -n "$SCALE" ] && VF="$VF,scale=$SCALE:-2"

run ffmpeg -hide_banner -v error -stats -nostdin -i "$FILE" -vf "$VF" -q:v "$Q" -y "$OUT/f%03d.jpg"

N=$(find "$OUT" -maxdepth 1 -name 'f*.jpg' | wc -l)
echo "wrote $N frames to $OUT/  (one every ${EVERY}s)"
echo "frame N is at $(( EVERY ))*(N-1) seconds; f001 = 0:00"
