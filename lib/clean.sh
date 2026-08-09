#!/usr/bin/env bash
# lectern clean — audio repair for listening.
#
# Downmix -> high-pass -> two-pass EBU R128 loudness normalisation -> true-peak
# limiter. Video is stream-copied, so a 55 minute lecture takes about a minute
# and the picture is untouched.
#
# Three settings matter:
#
#  1. loudnorm's second pass needs measurements from the exact chain that
#     precedes it. Measure after the pan and high-pass, not on the raw file, or
#     the second pass overshoots.
#  2. alimiter's `level` option defaults to true, which auto-levels the output
#     back to full scale and undoes the headroom. The symptom is peaks at
#     exactly 0.0 dB. Pass level=false.
#  3. lossy encoding adds 1-2 dB of inter-sample overshoot after the limiter.
#     Limit to about -2.5 dBFS to land under -1.5 dBTP.
set -euo pipefail
. "${LIB:-$(dirname "$0")}/common.sh"

FILE=""; OUT=""; MODE="auto"; I=-16; TP=-1.5; LRA=11; HP=80; LIMIT_DB=-2.5
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
usage: lectern clean FILE [-o OUT] [options]

  -o, --out PATH      output (default: FILE with -clean before the extension).
                      Extension picks the container: .mp4 keeps the video,
                      .mp3 / .m4a / .wav give audio only.
      --downmix MODE  auto (default) | mid | side | left | right | none
      --lufs N        integrated loudness target (default -16, good for speech
                      on laptop speakers; -23 is the broadcast figure)
      --tp N          true-peak target for loudnorm (default -1.5)
      --lra N         loudness range (default 11)
      --highpass HZ   default 80. Set 0 to disable.
      --limit DB      final limiter ceiling in dBFS (default -2.5)
EOF
      exit 0 ;;
    -o|--out) OUT="$2"; shift 2 ;;
    --downmix) MODE="$2"; shift 2 ;;
    --lufs) I="$2"; shift 2 ;;
    --tp) TP="$2"; shift 2 ;;
    --lra) LRA="$2"; shift 2 ;;
    --highpass) HP="$2"; shift 2 ;;
    --limit) LIMIT_DB="$2"; shift 2 ;;
    *) FILE="$1"; shift ;;
  esac
done
[ -n "$FILE" ] || die "usage: lectern clean FILE [-o OUT]"
[ -f "$FILE" ] || die "no such file: $FILE"
if [ -z "$OUT" ]; then
  ext="${FILE##*.}"; OUT="${FILE%.*}-clean.$ext"
fi

HAS_VIDEO=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$FILE" || true)
PAN="$(resolve_downmix "$FILE" "$MODE")"

PRE="$PAN"
[ "$HP" != "0" ] && PRE="$PRE,highpass=f=$HP"

echo "downmix: $PAN"
echo "pass 1: measuring loudness through the real chain ..."
MEAS=$(ffmpeg -hide_banner -nostdin -v info -i "$FILE" -vn -map 0:a:0 \
        -af "$PRE,loudnorm=I=$I:TP=$TP:LRA=$LRA:print_format=json" -f null - 2>&1 \
      | sed -n '/^{/,/^}/p')
[ -n "$MEAS" ] || die "loudnorm measurement produced nothing — is there an audio stream?"

getj() { echo "$MEAS" | grep -oP "\"$1\"\s*:\s*\"\K[^\"]+"; }
MI=$(getj input_i); MTP=$(getj input_tp); MLRA=$(getj input_lra)
MTH=$(getj input_thresh); MOFF=$(getj target_offset)
printf '   measured  I %s LUFS  TP %s dBTP  LRA %s  thresh %s\n' "$MI" "$MTP" "$MLRA" "$MTH"

# loudnorm refuses to run with non-finite measurements (a silent input gives -inf)
case "$MI" in *inf*) die "input measures $MI LUFS — the audio is silent. Run 'lectern probe' first." ;; esac

LIMIT=$(awk -v d="$LIMIT_DB" 'BEGIN{printf "%.4f", 10^(d/20)}')
CHAIN="$PRE,loudnorm=I=$I:TP=$TP:LRA=$LRA:measured_I=$MI:measured_TP=$MTP:measured_LRA=$MLRA:measured_thresh=$MTH:offset=$MOFF:linear=false"
CHAIN="$CHAIN,aresample=44100,alimiter=limit=$LIMIT:attack=5:release=50:level=false:latency=true"

echo "pass 2: rendering (limiter ceiling ${LIMIT_DB} dBFS = ${LIMIT}) ..."
if [ -n "$HAS_VIDEO" ] && [[ "$OUT" =~ \.(mp4|mkv|mov|webm)$ ]]; then
  run ffmpeg -hide_banner -v error -stats -nostdin -i "$FILE" \
    -map 0:v:0 -map 0:a:0 -c:v copy -af "$CHAIN" -ar 44100 -c:a aac -b:a 128k \
    -movflags +faststart -y "$OUT"
elif [[ "$OUT" =~ \.wav$ ]]; then
  run ffmpeg -hide_banner -v error -stats -nostdin -i "$FILE" \
    -vn -map 0:a:0 -af "$CHAIN" -ar 44100 -c:a pcm_s16le -y "$OUT"
else
  run ffmpeg -hide_banner -v error -stats -nostdin -i "$FILE" \
    -vn -map 0:a:0 -af "$CHAIN" -ar 44100 -c:a libmp3lame -q:a 2 -y "$OUT"
fi

echo "verifying the render ..."
read -r M P <<<"$(vol "$OUT" "anull")"
OUTM=$(ffmpeg -hide_banner -nostdin -v info -i "$OUT" -vn -map 0:a:0 \
        -af "loudnorm=I=$I:TP=$TP:LRA=$LRA:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
OI=$(echo "$OUTM" | grep -oP '"input_i"\s*:\s*"\K[^"]+'); OTP=$(echo "$OUTM" | grep -oP '"input_tp"\s*:\s*"\K[^"]+')
printf 'wrote %s\n   mean %s dBFS   peak %s dBFS   I %s LUFS   TP %s dBTP\n' "$OUT" "$M" "$P" "$OI" "$OTP"
if [ -n "$OTP" ] && awk -v t="$OTP" 'BEGIN{exit !(t > -1.0)}'; then
  echo "NOTE: true peak is ${OTP} dBTP. Re-run with a lower --limit if that matters." >&2
fi
