#!/usr/bin/env bash
# Installs the hpcups filter and the Deskjet 2050 J510 PPD, and creates the print queue in CUPS.
#
# Usage (with the printer plugged in over USB):
#   make && sudo ./scripts/install.sh
#
# Optional variables:
#   QUEUE=name        queue name (default: Deskjet_2050)
#   PRINTER_URI=uri   printer address, if auto-detection fails (see lpinfo -v)
#   PAGE_SIZE=A4      default paper size for the queue, A4 or Letter (default: from the macOS region)
#   DESTDIR=dir       testing only: installs into another folder, without sudo and without a queue
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HPLIP_VERSION="3.26.4"
FILTER_SRC="$ROOT/build/hpcups"
PPD_GZ="$ROOT/downloads/hplip-${HPLIP_VERSION}/ppd/hpcups/hp-deskjet_2050_j510_series.ppd.gz"

# Must match INSTALL_DIR in the Makefile (the filter looks for an optional hplip.conf there).
INSTALL_DIR="/Library/Printers/DeskJet2050"
FILTER_DST="$INSTALL_DIR/Filter/hpcups"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/deskjet2050-j510-hpcups.ppd"
QUEUE="${QUEUE:-Deskjet_2050}"
DESTDIR="${DESTDIR:-}"

[ -x "$FILTER_SRC" ] || { echo "Error: $FILTER_SRC not found. Run make first." >&2; exit 1; }
[ -f "$PPD_GZ" ] || { echo "Error: PPD not found. Run ./scripts/fetch-hplip.sh first." >&2; exit 1; }
if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
    echo "Error: run with sudo (the driver goes into /Library/Printers and the queue is created in CUPS)." >&2
    exit 1
fi

# cupsd only runs filters owned by root that nobody else can modify.
own=()
[ "$(id -u)" -eq 0 ] && own=(-o root -g wheel)

echo "Installing the filter to $FILTER_DST"
install -d ${own[@]+"${own[@]}"} -m 755 "$DESTDIR$INSTALL_DIR" "$DESTDIR$INSTALL_DIR/Filter"
install ${own[@]+"${own[@]}"} -m 755 "$FILTER_SRC" "$DESTDIR$FILTER_DST"

# The HPLIP PPD, with the filter referenced by its full path (macOS does not look for third-party
# filters anywhere else) and a name that sets this driver apart in the printer list.
# HPLIP calls the black-ink-only grayscale option KGray, but Chrome and the macOS "Black & White"
# checkbox ask for ColorModel=Gray. With no option by that name the request is ignored and the page
# prints in color, with grays made by the color cartridge. hpcups picks the mode from cupsRowStep,
# not from the option name.
echo "Installing the PPD to $PPD_DST"
install -d -m 755 "$DESTDIR$(dirname "$PPD_DST")"
tmp_ppd="$(mktemp "${TMPDIR:-/tmp}/deskjet2050-ppd.XXXXXX")"
trap 'rm -f "$tmp_ppd"' EXIT
gzcat "$PPD_GZ" | sed \
    -e "s|^\*cupsFilter: .*|*cupsFilter: \"application/vnd.cups-raster 0 $FILTER_DST\"|" \
    -e "s|^\*NickName: .*|*NickName: \"HP Deskjet 2050 J510 series, hpcups $HPLIP_VERSION arm64\"|" \
    -e "s|ColorModel KGray|ColorModel Gray|g" \
    > "$tmp_ppd"
install ${own[@]+"${own[@]}"} -m 644 "$tmp_ppd" "$DESTDIR$PPD_DST"

if [ -n "$DESTDIR" ]; then
    echo "DESTDIR is set: no queue created."
    exit 0
fi

# awk reads to the end instead of exiting at the first match: exiting early could kill lpinfo with
# SIGPIPE, and with pipefail and set -e that would stop this script without a message.
uri="${PRINTER_URI:-$(lpinfo -v 2>/dev/null | awk '$2 ~ /^usb:\/\/HP\/Deskjet%202050/ && !uri { uri = $2 } END { if (uri) print uri }')}"
if [ -z "$uri" ]; then
    echo "Driver installed, but the printer was not found on USB." >&2
    echo "Turn it on and run this script again, or add it in System Settings > Printers & Scanners." >&2
    exit 1
fi

# The HP PPD defaults to Letter; outside the Americas the common paper size is A4.
# Under sudo, the region is read from the user who ran the script, not from root.
if [ -z "${PAGE_SIZE:-}" ]; then
    if [ -n "${SUDO_USER:-}" ]; then
        region="$(sudo -u "$SUDO_USER" defaults read -g AppleLocale 2>/dev/null || true)"
    else
        region="$(defaults read -g AppleLocale 2>/dev/null || true)"
    fi
    case "${region#*_}" in
        US*|CA*|MX*|PH*|CL*|CO*|VE*|PR*) PAGE_SIZE=Letter ;;
        *) PAGE_SIZE=A4 ;;
    esac
fi

# printer-is-shared=false: the queue stays on this Mac and is not shared on the network.
echo "Creating queue $QUEUE for $uri (default paper: $PAGE_SIZE)"
lpadmin -p "$QUEUE" -D "HP Deskjet 2050" -E -v "$uri" -P "$PPD_DST" \
    -o printer-is-shared=false -o PageSize="$PAGE_SIZE"

echo "Done. For a test page: lp -d $QUEUE file.pdf"
