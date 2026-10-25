#!/usr/bin/env bash
# Double-click to install the HP Deskjet 2050 driver. Opens in Terminal and runs the same steps as the
# manual install: check the requirements, download HPLIP, build the filter and run install.sh with sudo.
# The scripts are called through bash so they work even if a download dropped their execute permission.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR/files" || exit 1

bold=$'\033[1m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'

finish() {
    echo
    read -r -p "Press Enter to close. "
    exit "$1"
}
fail() {
    echo
    echo "${red}${bold}Installation failed.${reset} $1"
    finish 1
}

clear
echo "${bold}HP Deskjet 2050 driver for macOS${reset}"
echo "This installs the driver and creates the printer queue. It takes about two minutes."
echo

echo "${bold}[1/4] Checking requirements${reset}"
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1
    fail "The Xcode Command Line Tools are missing. A window to install them was opened. When it finishes, double-click Install.command again."
fi
# Terminal may not have Homebrew in the PATH yet.
if ! command -v brew >/dev/null 2>&1; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
fi
command -v brew >/dev/null 2>&1 || fail "Homebrew is missing. Install it from https://brew.sh and double-click Install.command again."
if ! brew list jpeg-turbo >/dev/null 2>&1; then
    echo "Installing jpeg-turbo with Homebrew..."
    brew install jpeg-turbo || fail "Could not install jpeg-turbo."
fi
# grep without -q reads all of lpinfo's output; stopping early could kill lpinfo with SIGPIPE, and with
# pipefail that would look like "printer not found".
while ! lpinfo -v 2>/dev/null | grep 'usb://HP/Deskjet%202050' >/dev/null; do
    echo "The printer was not found. Plug it in over USB and turn it on."
    read -r -p "Press Enter to try again, or close this window to cancel. "
done
echo "${green}OK${reset}"

echo "${bold}[2/4] Downloading HPLIP${reset}"
bash scripts/fetch-hplip.sh >/dev/null || fail "Could not download HPLIP. Check your internet connection."
echo "${green}OK${reset}"

echo "${bold}[3/4] Building the driver${reset}"
mkdir -p build
if ! make >build/make.log 2>&1; then
    tail -n 15 build/make.log
    fail "The build failed. The full log is in driver/files/build/make.log."
fi
echo "${green}OK${reset}"

echo "${bold}[4/4] Installing${reset}"
echo "Type your Mac password and press Enter. Nothing shows up while you type, that is normal."
sudo bash scripts/install.sh || fail "See the messages above."

echo
echo "${green}${bold}Installed.${reset} The printer is ready in the print dialog (Cmd+P) of any app."
finish 0
