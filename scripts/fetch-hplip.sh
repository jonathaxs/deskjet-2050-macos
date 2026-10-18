#!/usr/bin/env bash
set -euo pipefail

HPLIP_VERSION="3.26.4"
HPLIP_SHA256="b9c61252754f35b4a237396ca8961e7b3e0c56db76d66a6712b7bf3e30e69463"
URL="https://downloads.sourceforge.net/project/hplip/hplip/${HPLIP_VERSION}/hplip-${HPLIP_VERSION}.tar.gz"

# Diretórios principais
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS="$ROOT/downloads"
TARBALL="$DOWNLOADS/hplip-${HPLIP_VERSION}.tar.gz"
PART_FILE="${TARBALL}.part"
EXTRACT_DIR="$DOWNLOADS/hplip-${HPLIP_VERSION}"

mkdir -p "$DOWNLOADS"

# Baixa o tarball se não existir ou se o hash estiver incorreto
if [ -f "$TARBALL" ] && echo "$HPLIP_SHA256  $TARBALL" | shasum -a 256 -c >/dev/null 2>&1; then
    echo "Arquivo já baixado e verificado: $TARBALL"
else
    echo "Baixando HPLIP ${HPLIP_VERSION}..."
    curl -fL --retry 3 -o "$PART_FILE" "$URL"
    mv "$PART_FILE" "$TARBALL"

    # Confere a integridade do arquivo baixado
    if ! echo "$HPLIP_SHA256  $TARBALL" | shasum -a 256 -c >/dev/null 2>&1; then
        rm -f "$TARBALL"
        echo "Erro: SHA256 não confere para $TARBALL" >&2
        exit 1
    fi
fi

# Extrai o tarball apenas se a pasta ainda não existir
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "Extraindo $TARBALL..."
    tar -xzf "$TARBALL" -C "$DOWNLOADS"
fi

# O hpcups usa um cabeçalho interno da libjpeg (jpegint.h) que o Homebrew não instala.
# Ele precisa ser da mesma versão da jpeg-turbo instalada, porque descreve estruturas internas da biblioteca.
if ! JPEG_VERSION="$(brew list --versions jpeg-turbo 2>/dev/null | awk '{print $2}')" || [ -z "$JPEG_VERSION" ]; then
    echo "Erro: jpeg-turbo não encontrada. Instale com: brew install jpeg-turbo" >&2
    exit 1
fi
JPEG_VERSION="${JPEG_VERSION%%_*}"   # remove revisão do Homebrew (ex: 3.2.0_1)
JPEGINT_H="$DOWNLOADS/jpegint.h"
JPEGINT_STAMP="$DOWNLOADS/jpegint.h.version"
if [ ! -f "$JPEGINT_H" ] || [ "$(cat "$JPEGINT_STAMP" 2>/dev/null)" != "$JPEG_VERSION" ]; then
    echo "Baixando jpegint.h da jpeg-turbo ${JPEG_VERSION}..."
    curl -fL --retry 3 -o "${JPEGINT_H}.part" \
        "https://raw.githubusercontent.com/libjpeg-turbo/libjpeg-turbo/${JPEG_VERSION}/src/jpegint.h"
    mv "${JPEGINT_H}.part" "$JPEGINT_H"
    echo "$JPEG_VERSION" > "$JPEGINT_STAMP"
fi

# Imprime o caminho final
echo "$EXTRACT_DIR"
