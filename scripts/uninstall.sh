#!/usr/bin/env bash
# Remove a fila, o filtro e o PPD instalados pelo install.sh.
#
# Uso:
#   sudo ./scripts/uninstall.sh
#   QUEUE=nome sudo ./scripts/uninstall.sh   # se a fila foi criada com outro nome
set -euo pipefail

INSTALL_DIR="/Library/Printers/DeskJet2050"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/deskjet2050-j510-hpcups.ppd"
QUEUE="${QUEUE:-Deskjet_2050}"

[ "$(id -u)" -eq 0 ] || { echo "Erro: rode com sudo." >&2; exit 1; }

if lpstat -p "$QUEUE" >/dev/null 2>&1; then
    echo "Removendo a fila $QUEUE"
    lpadmin -x "$QUEUE"
fi

echo "Removendo $INSTALL_DIR e $PPD_DST"
rm -rf "$INSTALL_DIR"
rm -f "$PPD_DST"
echo "Pronto."
