#!/usr/bin/env bash
# Double-click to remove the HP Deskjet 2050 driver and its print queue (runs uninstall.sh with sudo).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/files" || exit 1

bold=$'\033[1m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'

clear
echo "${bold}HP Deskjet 2050 driver for macOS${reset}"
echo "This removes the driver and the Deskjet_2050 printer queue."
read -r -p "Press Enter to continue, or close this window to cancel. "
echo

echo "Type your Mac password and press Enter. Nothing shows up while you type, that is normal."
if sudo bash scripts/uninstall.sh; then
    echo
    echo "${green}${bold}Uninstalled.${reset}"
    status=0
else
    echo
    echo "${red}${bold}Uninstall failed.${reset} See the messages above."
    status=1
fi

echo
read -r -p "Press Enter to close. "
exit "$status"
