#!/usr/bin/env bash
# Testa o filtro build/hpcups sem impressora e sem instalar nada no sistema.
# Gera uma página de texto, converte para raster CUPS com o PPD da J510 (usando o cupsfilter do macOS),
# roda o hpcups em cada modo de qualidade/cor e confere se a saída parece PCL3GUI válido.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HPLIP_VERSION="3.26.4"
FILTER="$ROOT/build/hpcups"
PPD_GZ="$ROOT/downloads/hplip-${HPLIP_VERSION}/ppd/hpcups/hp-deskjet_2050_j510_series.ppd.gz"

[ -x "$FILTER" ] || { echo "Erro: $FILTER não existe. Rode make primeiro." >&2; exit 1; }
[ -f "$PPD_GZ" ] || { echo "Erro: PPD não encontrado. Rode ./scripts/fetch-hplip.sh primeiro." >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hpcups-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# PPD de teste: igual ao do HPLIP, mas apontando para o filtro compilado aqui.
gzcat "$PPD_GZ" | sed "s|^\*cupsFilter: .*|*cupsFilter: \"application/vnd.cups-raster 0 $FILTER\"|" > "$WORK/j510.ppd"

printf 'Teste deskjet-2050-macos\n\nHP Deskjet 2050 J510 - filtro hpcups arm64\n' > "$WORK/teste.txt"
cupsfilter -m application/pdf "$WORK/teste.txt" > "$WORK/teste.pdf" 2>/dev/null

falhas=0
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
    cupsfilter -p "$WORK/j510.ppd" -m application/vnd.cups-raster "${args[@]}" "$WORK/teste.pdf" \
        > "$WORK/teste.ras" 2>/dev/null

    status=0
    PPD="$WORK/j510.ppd" TMPDIR="$WORK" "$FILTER" 1 "$USER" teste 1 "$opts" "$WORK/teste.ras" \
        > "$WORK/teste.prn" 2> "$WORK/hpcups.log" || status=$?

    # Saída esperada: reset PCL + PJL no início e pelo menos uma linha de imagem (ESC*b...W).
    linhas="$(LC_ALL=C grep -a -o $'\x1b\\*b[0-9]*W' "$WORK/teste.prn" | wc -l | tr -d ' ')"
    if [ "$status" -eq 0 ] && LC_ALL=C head -c 20 "$WORK/teste.prn" | grep -a -q '@PJL\|%-12345X' && [ "$linhas" -gt 0 ]; then
        echo "OK    $opts  ($(stat -f%z "$WORK/teste.prn") bytes, $linhas linhas)"
    else
        echo "FALHA $opts  (saída $status, $linhas linhas)"
        sed 's/^/      /' "$WORK/hpcups.log"
        falhas=$((falhas + 1))
    fi
done

[ "$falhas" -eq 0 ] && echo "Todos os modos passaram." || { echo "$falhas modo(s) falharam." >&2; exit 1; }
