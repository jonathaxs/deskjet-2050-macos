#!/usr/bin/env bash
# Tests the build/hpcups filter without a printer and without installing anything.
# Makes a text page, converts it to CUPS raster with the J510 PPD (using the macOS cupsfilter),
# runs hpcups in each quality/color mode and checks that the output looks like valid PCL3GUI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HPLIP_VERSION="3.26.4"
FILTER="$ROOT/build/hpcups"
PPD_GZ="$ROOT/downloads/hplip-${HPLIP_VERSION}/ppd/hpcups/hp-deskjet_2050_j510_series.ppd.gz"

[ -x "$FILTER" ] || { echo "Error: $FILTER not found. Run make first." >&2; exit 1; }
[ -f "$PPD_GZ" ] || { echo "Error: PPD not found. Run ./scripts/fetch-hplip.sh first." >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hpcups-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Test PPD: same as the HPLIP one, but pointing to the filter built here.
gzcat "$PPD_GZ" | sed "s|^\*cupsFilter: .*|*cupsFilter: \"application/vnd.cups-raster 0 $FILTER\"|" > "$WORK/j510.ppd"

printf 'deskjet-2050-macos test\n\nHP Deskjet 2050 J510 - hpcups arm64 filter\n' > "$WORK/test.txt"
cupsfilter -m application/pdf "$WORK/test.txt" > "$WORK/test.pdf" 2>/dev/null

failures=0
for opts in \
    "PageSize=A4 OutputMode=Normal ColorModel=RGB" \
    "PageSize=A4 OutputMode=FastDraft ColorModel=RGB" \
    "PageSize=A4 OutputMode=Best ColorModel=RGB" \
    "PageSize=A4 OutputMode=Normal ColorModel=KGray" \
    "PageSize=A4 OutputMode=Normal ColorModel=CMYGray" \
    "PageSize=A4 OutputMode=Photo ColorModel=RGB MediaType=Photo" \
    "PageSize=Letter OutputMode=Normal ColorModel=RGB"; do
    args=()
    for o in $opts; do args+=(-o "$o"); done
    cupsfilter -p "$WORK/j510.ppd" -m application/vnd.cups-raster "${args[@]}" "$WORK/test.pdf" \
        > "$WORK/test.ras" 2>/dev/null

    status=0
    PPD="$WORK/j510.ppd" TMPDIR="$WORK" "$FILTER" 1 "$USER" test 1 "$opts" "$WORK/test.ras" \
        > "$WORK/test.prn" 2> "$WORK/hpcups.log" || status=$?

    # Expected output: PCL reset + PJL at the start and at least one image row (ESC*b...W).
    rows="$(LC_ALL=C grep -a -o $'\x1b\\*b[0-9]*W' "$WORK/test.prn" | wc -l | tr -d ' ')"
    if [ "$status" -eq 0 ] && LC_ALL=C head -c 20 "$WORK/test.prn" | grep -a -q '@PJL\|%-12345X' && [ "$rows" -gt 0 ]; then
        echo "OK    $opts  ($(stat -f%z "$WORK/test.prn") bytes, $rows rows)"
    else
        echo "FAIL  $opts  (exit $status, $rows rows)"
        sed 's/^/      /' "$WORK/hpcups.log"
        failures=$((failures + 1))
    fi
done

[ "$failures" -eq 0 ] && echo "All modes passed." || { echo "$failures mode(s) failed." >&2; exit 1; }
