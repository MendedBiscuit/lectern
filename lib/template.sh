#!/usr/bin/env bash
# lectern template — copy the LaTeX preamble out so a summary can be written into it.
set -euo pipefail
. "${LIB:-$(dirname "$0")}/common.sh"

SRC="${LECTERN_ROOT:-$(dirname "$0")/..}/skills/lecture-summary/assets/lecture.tex"
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
usage: lectern template [-o OUT.tex]

Writes the lecture-summary preamble to OUT.tex (default: ./lecture.tex).
Build it with:  latexmk -pdf -outdir=build OUT.tex

  lectern template -o lec05/lec05.tex
EOF
      exit 0 ;;
    -o|--out) OUT="$2"; shift 2 ;;
    *) OUT="$1"; shift ;;
  esac
done
[ -n "$OUT" ] || OUT="lecture.tex"
[ -f "$SRC" ] || die "template not found at $SRC"
[ -e "$OUT" ] && die "$OUT already exists"

mkdir -p "$(dirname "$OUT")"
cp "$SRC" "$OUT"
echo "wrote $OUT"
echo "build with: latexmk -pdf -outdir=build $OUT"
