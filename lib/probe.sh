#!/usr/bin/env bash
# lectern probe — inspect a recording before transcoding it.
#
# The check that matters is whether the stereo pair is phase-inverted. If it is,
# a mono downmix (ffmpeg -ac 1 averages L and R) cancels the audio to near
# silence, whisper's VAD discards the file, and the transcript comes back empty.
# Both channels measure normally on their own, so a level check will not catch
# it: compare mid (L+R) against side (L-R).
set -euo pipefail
. "${LIB:-$(dirname "$0")}/common.sh"

FILE=""
SAMPLES=3        # phase-correlation windows
WINDOW=60        # seconds per window

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \?//'; echo; echo "usage: lectern probe FILE [--windows N] [--window-seconds S]"; exit 0 ;;
    --windows) SAMPLES="$2"; shift 2 ;;
    --window-seconds) WINDOW="$2"; shift 2 ;;
    *) FILE="$1"; shift ;;
  esac
done
[ -n "$FILE" ] || { echo "usage: lectern probe FILE" >&2; exit 2; }
[ -f "$FILE" ] || { echo "lectern probe: no such file: $FILE" >&2; exit 1; }

# ---------------------------------------------------------------- container --
echo "== $FILE"
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$FILE")
case "$DUR" in ''|N/A) DUR=0 ;; esac
awk -v d="$DUR" 'BEGIN{printf "   duration   %d:%02d:%02d  (%.0f s)\n", d/3600, (d%3600)/60, d%60, d}'
printf '   size       %s\n' "$(du -h "$FILE" | cut -f1)"

VINFO=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,codec_name -of csv=p=0 "$FILE" 2>/dev/null || true)
[ -n "$VINFO" ] && printf '   video      %s\n' "$VINFO"

AINFO=$(ffprobe -v error -select_streams a:0 \
  -show_entries stream=codec_name,channels,sample_rate,channel_layout -of csv=p=0 "$FILE" 2>/dev/null || true)
[ -n "$AINFO" ] || { echo "   audio      (none) — nothing more to check"; exit 0; }
printf '   audio      %s\n' "$AINFO"

CH=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$FILE")

echo
echo "== levels (dBFS)"
if [ "$CH" -lt 2 ]; then
  read -r M P <<<"$(vol "$FILE" "anull")"
  printf '   mono        mean %8s   peak %8s\n' "$M" "$P"
  echo
  echo "== verdict"
  echo "   already mono. no downmix decision to make."
  echo "   downmix:   (none)"
  exit 0
fi

read -r LM LP <<<"$(vol "$FILE" "pan=mono|c0=c0")"
read -r RM RP <<<"$(vol "$FILE" "pan=mono|c0=c1")"
read -r MM MP <<<"$(vol "$FILE" "$MID")"
read -r SM SP <<<"$(vol "$FILE" "$SIDE")"
printf '   left        mean %8s   peak %8s\n' "$LM" "$LP"
printf '   right       mean %8s   peak %8s\n' "$RM" "$RP"
printf '   mid  (L+R)  mean %8s   peak %8s\n' "$MM" "$MP"
printf '   side (L-R)  mean %8s   peak %8s\n' "$SM" "$SP"

# ------------------------------------------------------- phase correlation --
# aphasemeter reports +1.0 for identical channels, -1.0 for a polarity flip.
# A few sampled windows are enough and much faster than the whole file.
echo
echo "== phase correlation (+1 identical, 0 uncorrelated, -1 inverted)"
PHASES=""
for i in $(seq 1 "$SAMPLES"); do
  SS=$(awk -v d="$DUR" -v i="$i" -v n="$SAMPLES" -v w="$WINDOW" \
        'BEGIN{t=d*i/(n+1)-w/2; if(t<0)t=0; if(t>d-w)t=(d-w>0?d-w:0); printf "%.1f", t}')
  MED=$(ffmpeg -hide_banner -v error -nostdin -ss "$SS" -t "$WINDOW" -i "$FILE" -vn -map 0:a:0 \
          -af "aphasemeter=video=0:phasing=0,ametadata=print:key=lavfi.aphasemeter.phase:file=-" \
          -f null - 2>/dev/null \
        | grep -oP 'phase=\K[-0-9.]+' | sort -n \
        | awk '{a[NR]=$1} END{if(NR)printf "%.3f", a[int(NR/2)+1]; else printf "na"}')
  printf '   at %6.0fs   median %s\n' "$SS" "$MED"
  PHASES="$PHASES $MED"
done
PHASE=$(echo "$PHASES" | tr ' ' '\n' | grep -v '^$' | grep -v na | sort -n | awk '{a[NR]=$1} END{if(NR)printf "%.3f", a[int(NR/2)+1]; else printf "na"}')

# ------------------------------------------------------------------ verdict --
echo
echo "== verdict"
DELTA=$(awk -v s="$SM" -v m="$MM" 'BEGIN{printf "%.1f", s-m}')
if awk -v d="$DELTA" 'BEGIN{exit !(d > 6)}'; then
  cat <<EOF
   *** PHASE-INVERTED STEREO ***
   side is ${DELTA} dB above mid (phase median ${PHASE}). The channels are
   polarity-flipped copies, so a mono downmix cancels them. Do not use
   'ffmpeg -ac 1' on this file. Use the difference: it is ~3 dB better than a
   single channel, since the codec noise is independent per channel.

   downmix:   pan=mono|c0=0.5*c0-0.5*c1
EOF
  exit 0
fi
if awk -v d="$DELTA" 'BEGIN{exit !(d < -6)}'; then
  cat <<EOF
   normal correlated stereo (mid is $(awk -v d="$DELTA" 'BEGIN{printf "%.1f", -d}') dB above side, phase median ${PHASE}).
   Safe to average the channels.

   downmix:   pan=mono|c0=0.5*c0+0.5*c1
EOF
  exit 0
fi
cat <<EOF
   mid and side are within ${DELTA} dB, phase median ${PHASE}. The channels carry
   different content (a real stereo pair, or two microphones). Neither downmix
   is clearly right. Take mid, but listen to a minute of the result first.

   downmix:   pan=mono|c0=0.5*c0+0.5*c1   (unverified)
EOF
