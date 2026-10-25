#!/usr/bin/env bash
# Instala o filtro hpcups e o PPD da Deskjet 2050 J510 e cria a fila de impressão no CUPS.
#
# Uso (com a impressora ligada na USB):
#   make && sudo ./scripts/install.sh
#
# Variáveis opcionais:
#   QUEUE=nome        nome da fila (padrão: Deskjet_2050)
#   PRINTER_URI=uri   endereço da impressora, se a detecção automática falhar (veja lpinfo -v)
#   PAGE_SIZE=A4      papel padrão da fila, A4 ou Letter (padrão: pela região do macOS)
#   DESTDIR=pasta     só para teste: instala dentro de outra pasta, sem sudo e sem criar a fila
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HPLIP_VERSION="3.26.4"
FILTER_SRC="$ROOT/build/hpcups"
PPD_GZ="$ROOT/downloads/hplip-${HPLIP_VERSION}/ppd/hpcups/hp-deskjet_2050_j510_series.ppd.gz"

# Precisa bater com o INSTALL_DIR do Makefile (o filtro procura o hplip.conf opcional lá).
INSTALL_DIR="/Library/Printers/DeskJet2050"
FILTER_DST="$INSTALL_DIR/Filter/hpcups"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/deskjet2050-j510-hpcups.ppd"
QUEUE="${QUEUE:-Deskjet_2050}"
DESTDIR="${DESTDIR:-}"

[ -x "$FILTER_SRC" ] || { echo "Erro: $FILTER_SRC não existe. Rode make primeiro." >&2; exit 1; }
[ -f "$PPD_GZ" ] || { echo "Erro: PPD não encontrado. Rode ./scripts/fetch-hplip.sh primeiro." >&2; exit 1; }
if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
    echo "Erro: rode com sudo (o driver vai para /Library/Printers e a fila é criada no CUPS)." >&2
    exit 1
fi

# O cupsd só executa filtros de root que ninguém mais pode alterar.
own=()
[ "$(id -u)" -eq 0 ] && own=(-o root -g wheel)

echo "Instalando o filtro em $FILTER_DST"
install -d ${own[@]+"${own[@]}"} -m 755 "$DESTDIR$INSTALL_DIR" "$DESTDIR$INSTALL_DIR/Filter"
install ${own[@]+"${own[@]}"} -m 755 "$FILTER_SRC" "$DESTDIR$FILTER_DST"

# PPD do HPLIP com o filtro apontado pelo caminho completo (o macOS não procura filtros de terceiros
# em outro lugar) e um nome que diferencia este driver na lista de impressoras.
# A opção de cinza só com tinta preta se chama KGray no HPLIP, mas o Chrome e a caixa "Preto e branco"
# do macOS pedem ColorModel=Gray. Sem uma opção com esse nome, o pedido é ignorado e a página sai em
# cor, com os cinzas feitos pelo cartucho colorido. O hpcups escolhe o modo pelo cupsRowStep, não pelo nome.
echo "Instalando o PPD em $PPD_DST"
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
    echo "DESTDIR definido: fila não criada."
    exit 0
fi

uri="${PRINTER_URI:-$(lpinfo -v 2>/dev/null | awk '$2 ~ /^usb:\/\/HP\/Deskjet%202050/ { print $2; exit }')}"
if [ -z "$uri" ]; then
    echo "Driver instalado, mas a impressora não foi encontrada na USB." >&2
    echo "Ligue-a e rode o script de novo, ou adicione pelos Ajustes do Sistema > Impressoras e Scanners." >&2
    exit 1
fi

# O PPD da HP vem com Carta como padrão; fora das Américas o papel comum é A4.
# Com sudo, a região é lida do usuário que chamou o script, não do root.
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

# printer-is-shared=false: a fila fica só neste Mac, sem compartilhar na rede.
echo "Criando a fila $QUEUE para $uri (papel padrão: $PAGE_SIZE)"
lpadmin -p "$QUEUE" -D "HP Deskjet 2050" -E -v "$uri" -P "$PPD_DST" \
    -o printer-is-shared=false -o PageSize="$PAGE_SIZE"

echo "Pronto. Para uma página de teste: lp -d $QUEUE arquivo.pdf"
