#!/usr/bin/env bash
# Downloads and verifies the HPLIP source and the libjpeg header that the build needs, into downloads/.
set -euo pipefail

HPLIP_VERSION="3.26.4"
HPLIP_SHA256="b9c61252754f35b4a237396ca8961e7b3e0c56db76d66a6712b7bf3e30e69463"
URL="https://downloads.sourceforge.net/project/hplip/hplip/${HPLIP_VERSION}/hplip-${HPLIP_VERSION}.tar.gz"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS="$ROOT/downloads"
TARBALL="$DOWNLOADS/hplip-${HPLIP_VERSION}.tar.gz"
PART_FILE="${TARBALL}.part"
EXTRACT_DIR="$DOWNLOADS/hplip-${HPLIP_VERSION}"

mkdir -p "$DOWNLOADS"

# Download the tarball if it is missing or its hash does not match.
if [ -f "$TARBALL" ] && echo "$HPLIP_SHA256  $TARBALL" | shasum -a 256 -c >/dev/null 2>&1; then
    echo "Already downloaded and verified: $TARBALL"
else
    echo "Downloading HPLIP ${HPLIP_VERSION}..."
    curl -fL --retry 3 -o "$PART_FILE" "$URL"
    mv "$PART_FILE" "$TARBALL"

    if ! echo "$HPLIP_SHA256  $TARBALL" | shasum -a 256 -c >/dev/null 2>&1; then
        rm -f "$TARBALL"
        echo "Error: SHA-256 mismatch for $TARBALL" >&2
        exit 1
    fi
fi

# Extract only if the folder does not exist yet.
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "Extracting $TARBALL..."
    tar -xzf "$TARBALL" -C "$DOWNLOADS"
fi

# hpcups uses an internal libjpeg header (jpegint.h) that Homebrew does not install.
# It must match the installed jpeg-turbo version, because it describes the library's internal structures.
if ! JPEG_VERSION="$(brew list --versions jpeg-turbo 2>/dev/null | awk '{print $2}')" || [ -z "$JPEG_VERSION" ]; then
    echo "Error: jpeg-turbo not found. Install it with: brew install jpeg-turbo" >&2
    exit 1
fi
JPEG_VERSION="${JPEG_VERSION%%_*}"   # drop the Homebrew revision (e.g. 3.2.0_1)
JPEGINT_H="$DOWNLOADS/jpegint.h"
JPEGINT_STAMP="$DOWNLOADS/jpegint.h.version"
if [ ! -f "$JPEGINT_H" ] || [ "$(cat "$JPEGINT_STAMP" 2>/dev/null)" != "$JPEG_VERSION" ]; then
    echo "Downloading jpegint.h from jpeg-turbo ${JPEG_VERSION}..."
    curl -fL --retry 3 -o "${JPEGINT_H}.part" \
        "https://raw.githubusercontent.com/libjpeg-turbo/libjpeg-turbo/${JPEG_VERSION}/src/jpegint.h"
    mv "${JPEGINT_H}.part" "$JPEGINT_H"
    echo "$JPEG_VERSION" > "$JPEGINT_STAMP"
fi

echo "$EXTRACT_DIR"
