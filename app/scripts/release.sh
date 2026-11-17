#!/bin/bash
# Builds the two zips for a GitHub release in dist/ at the repository root:
#   DeskJet-2050-app-vX.Y.Z.zip     the app (shows the ink levels and installs the driver)
#   deskjet-2050-driver-vX.Y.Z.zip  only the driver folder, for people who prefer Install.command
# Usage, from anywhere: app/scripts/release.sh 1.1.0
# The driver zip comes from the last commit (git archive), so commit first.
set -euo pipefail

VERSION="${1:?Usage: release.sh X.Y.Z}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$REPO/dist"

if [ -n "$(git -C "$REPO" status --porcelain -- app driver)" ]; then
    echo "app/ or driver/ has uncommitted changes. Commit them first." >&2
    exit 1
fi

VERSION="$VERSION" "$REPO/app/scripts/build-app.sh"

mkdir -p "$DIST"
APP_ZIP="$DIST/DeskJet-2050-app-v$VERSION.zip"
DRIVER_ZIP="$DIST/deskjet-2050-driver-v$VERSION.zip"
rm -f "$APP_ZIP" "$DRIVER_ZIP"

# ditto keeps the signature, the execute bits and the bundle layout the way Finder's Compress does.
ditto -c -k --sequesterRsrc --keepParent "$REPO/app/build/DeskJet 2050.app" "$APP_ZIP"
git -C "$REPO" archive --format=zip --prefix=deskjet-2050-driver/ -o "$DRIVER_ZIP" HEAD:driver

echo
echo "Release files:"
cd "$DIST"
shasum -a 256 "$(basename "$APP_ZIP")" "$(basename "$DRIVER_ZIP")"
