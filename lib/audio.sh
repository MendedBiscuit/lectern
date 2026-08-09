#!/usr/bin/env bash
# lectern audio — extract ASR-ready audio from a recording.
#
# 16 kHz mono PCM, which is what whisper resamples to anyway. The downmix is
# measured by default rather than assumed.
set -euo pipefail
. "${LIB:-$(dirname "$0")}/common.sh"

FILE=""; OUT=""; MODE="auto"; RATE=16000; HP=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
usage: lectern audio FILE [-o OUT.wav] [options]

  -o, --out PATH      output wav (default: FILE with .wav, alongside the input)
      --downmix MODE  auto (default) | mid | side | left | right | none
                      or a raw ffmpeg filter expression.
                      auto measures mid vs side and takes the louder, which is
                      what catches phase-inverted stereo.
      --rate HZ       sample rate (default 16000; whisper wants 16k)
      --highpass HZ   roll off rumble below HZ (try 80 for a hall recording)
EOF
      exit 0 ;;
    -o|--out) OUT="$2"; shift 2 ;;
    --downmix) MODE="$2"; shift 2 ;;
    --rate) RATE="$2"; shift 2 ;;
    --highpass) HP="$2"; shift 2 ;;
    *) FILE="$1"; shift ;;
  esac
done
[ -n "$FILE" ] || die "usage: lectern audio FILE [-o OUT.wav]"
[ -f "$FILE" ] || die "no such file: $FILE"
[ -n "$OUT" ] || OUT="${FILE%.*}.wav"

PAN="$(resolve_downmix "$FILE" "$MODE")"
CHAIN="$PAN"
[ -n "$HP" ] && CHAIN="$CHAIN,highpass=f=$HP"

echo "downmix: $PAN"
run ffmpeg -hide_banner -v error -stats -nostdin -i "$FILE" \
  -vn -map 0:a:0 -af "$CHAIN" -ar "$RATE" -ac 1 -c:a pcm_s16le -y "$OUT"

read -r M P <<<"$(vol "$OUT" "anull")"
printf 'wrote %s  (mean %s dBFS, peak %s dBFS)\n' "$OUT" "$M" "$P"

# -50 dBFS or below is a cancelled downmix, not a quiet lecture. Report it now
# rather than after five minutes of transcribing silence.
if [ "$M" != "na" ] && awk -v m="$M" 'BEGIN{exit !(m < -50)}'; then
  echo "WARNING: mean level is ${M} dBFS, which is not speech. Run 'lectern probe' on the source." >&2
fi
