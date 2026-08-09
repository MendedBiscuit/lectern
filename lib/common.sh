#!/usr/bin/env bash
# shared helpers. sourced, not executed.

# Every number here goes through printf and awk. Under a comma-decimal locale
# (de_DE, fr_FR, ...) ffprobe still prints "3309.15", but printf %f rejects it
# and awk truncates it to 3309.
export LC_ALL=C

# run() — echo the command when LECTERN_VERBOSE=1, then run it.
run() {
  if [ "${LECTERN_VERBOSE:-0}" = "1" ]; then
    printf '+ ' >&2; printf '%q ' "$@" >&2; printf '\n' >&2
  fi
  "$@"
}

# vol FILE FILTER -> "mean max" in dBFS ("na na" if silent)
vol() {
  ffmpeg -hide_banner -nostdin -v info -i "$1" -vn -map 0:a:0 -af "$2,volumedetect" -f null - 2>&1 \
    | awk '/mean_volume:/ {m=$(NF-1)} /max_volume:/ {p=$(NF-1)}
           END {printf "%s %s", (m==""?"na":m), (p==""?"na":p)}'
}

MID='pan=mono|c0=0.5*c0+0.5*c1'
SIDE='pan=mono|c0=0.5*c0-0.5*c1'

# pick_downmix FILE -> the pan= expression to use, on stdout.
# Mono passes through. For stereo, whichever of mid/side is louder wins. On a
# phase-inverted recording that is the difference; the sum would cancel.
pick_downmix() {
  local f="$1" ch mm sm _p
  ch=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$f")
  if [ "${ch:-1}" -lt 2 ]; then echo "anull"; return; fi
  read -r mm _p <<<"$(vol "$f" "$MID")"
  read -r sm _p <<<"$(vol "$f" "$SIDE")"
  if awk -v s="$sm" -v m="$mm" 'BEGIN{exit !(s > m + 6)}'; then echo "$SIDE"; else echo "$MID"; fi
}

# resolve_downmix FILE MODE -> pan expression
resolve_downmix() {
  case "$2" in
    auto)  pick_downmix "$1" ;;
    mid)   echo "$MID" ;;
    side)  echo "$SIDE" ;;
    left)  echo 'pan=mono|c0=c0' ;;
    right) echo 'pan=mono|c0=c1' ;;
    none)  echo 'anull' ;;
    *)     echo "$2" ;;                 # raw filter expression
  esac
}

die() { echo "lectern: $*" >&2; exit 1; }
