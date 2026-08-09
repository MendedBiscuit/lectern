#!/usr/bin/env bash
# lectern crop — extract one region of a frame and enlarge it.
#
# A 1280x720 frame of a lecture theatre gives a line of blackboard maths about
# 25 pixels of height, which is not enough to read a subscript. Cropping the
# panel and upscaling 3-5x is.
set -euo pipefail
. "${LIB:-$(dirname "$0")}/common.sh"

FRAME=""; GEOM=""; OUT=""; ZOOM=400; SHARPEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
usage: lectern crop FRAME WxH+X+Y [-o OUT.png] [--zoom PCT] [--sharpen]

  --zoom PCT     enlarge by PCT percent (default 400)
  --sharpen      unsharp pass; helps on small chalk text, hurts on clean slides

  lectern crop frames/f110.jpg 620x180+635+15 -o board1.png
  lectern crop frames/f110.jpg 130x28+290+278 --zoom 900 --sharpen -o const.png

Geometry is ImageMagick's: width x height + xoffset + yoffset, from top-left.
Crop generously the first time, then tighten. A region that clips a subscript
is worse than one with slack around it.
EOF
      exit 0 ;;
    -o|--out) OUT="$2"; shift 2 ;;
    --zoom) ZOOM="$2"; shift 2 ;;
    --sharpen) SHARPEN=1; shift ;;
    *) if [ -z "$FRAME" ]; then FRAME="$1"; else GEOM="$1"; fi; shift ;;
  esac
done
[ -n "$FRAME" ] && [ -n "$GEOM" ] || die "usage: lectern crop FRAME WxH+X+Y [-o OUT.png]"
[ -f "$FRAME" ] || die "no such frame: $FRAME"
[ -n "$OUT" ] || OUT="crop.png"
mkdir -p "$(dirname "$OUT")"

args=(magick "$FRAME" -crop "$GEOM" +repage -resize "${ZOOM}%")
[ "$SHARPEN" = "1" ] && args+=(-sharpen 0x1)
args+=("$OUT")
run "${args[@]}"

echo "wrote $OUT  ($(magick identify -format '%wx%h' "$OUT"))"
