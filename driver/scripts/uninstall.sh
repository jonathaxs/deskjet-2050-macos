#!/usr/bin/env bash
# Removes the queue, the filter and the PPD installed by install.sh.
#
# Usage:
#   sudo ./scripts/uninstall.sh
#   QUEUE=name sudo ./scripts/uninstall.sh   # if the queue was created with another name
set -euo pipefail

INSTALL_DIR="/Library/Printers/DeskJet2050"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/deskjet2050-j510-hpcups.ppd"
QUEUE="${QUEUE:-Deskjet_2050}"

[ "$(id -u)" -eq 0 ] || { echo "Error: run with sudo." >&2; exit 1; }

if lpstat -p "$QUEUE" >/dev/null 2>&1; then
    echo "Removing queue $QUEUE"
    lpadmin -x "$QUEUE"
fi

echo "Removing $INSTALL_DIR and $PPD_DST"
rm -rf "$INSTALL_DIR"
rm -f "$PPD_DST"
echo "Done."
