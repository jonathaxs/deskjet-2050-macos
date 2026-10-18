# Compila só o filtro CUPS hpcups do HPLIP, nativo para macOS arm64.
# Não usa o configure do HPLIP: ele exige libusb, SANE, net-snmp e outras coisas que o filtro não precisa.
#
# Uso:
#   ./scripts/fetch-hplip.sh   # baixa e confere o código do HPLIP em downloads/
#   make                       # gera build/hpcups
#   make check                 # confere arquitetura, bibliotecas e assinatura

HPLIP_VERSION ?= 3.26.4
HPLIP_DIR     ?= downloads/hplip-$(HPLIP_VERSION)
BUILD_DIR     ?= build

# libjpeg do Homebrew (jpeg-turbo), linkada estática para o filtro depender só de bibliotecas do sistema.
JPEG_PREFIX   ?= $(shell brew --prefix jpeg-turbo 2>/dev/null)
JPEG_LIB      ?= $(JPEG_PREFIX)/lib/libjpeg.a
# Cabeçalho interno da libjpeg (não vem no Homebrew), baixado pelo fetch-hplip.sh na mesma versão.
JPEGINT_H     ?= downloads/jpegint.h

SDK           := $(shell xcrun --show-sdk-path)
CC            := xcrun clang
CXX           := xcrun clang++
ARCH          ?= arm64
# O build é feito no próprio Mac do usuário; a libjpeg do Homebrew já sai para a versão instalada.
MIN_MACOS     ?= $(shell sw_vers -productVersion | cut -d. -f1-2)

# DISABLE_IMAGEPROCESSOR: não usa a libImageProcessor fechada (só existe para x86 e só serve a lasers ljzjstream).
# Sem HAVE_DBUS: o aviso por DBus é opcional e não existe DBus no macOS.
# CONFDIR: onde o filtro procura um hplip.conf opcional (sem o arquivo, usa os padrões).
INSTALL_DIR ?= /Library/Printers/DeskJet2050
DEFINES   := -DAPDK_LITTLE_ENDIAN -DDISABLE_IMAGEPROCESSOR -DCONFDIR=\"$(INSTALL_DIR)\"
SRC_DIR   := $(BUILD_DIR)/src
INCLUDES  := -I$(SRC_DIR) -I$(JPEG_PREFIX)/include
WARNINGS  := -Wno-deprecated-declarations -Wno-write-strings -Wno-format-security
COMMON    := -arch $(ARCH) -isysroot $(SDK) -mmacosx-version-min=$(MIN_MACOS) -O2 $(DEFINES) $(INCLUDES) $(WARNINGS)
CFLAGS    += $(COMMON)
CXXFLAGS  += $(COMMON) -std=gnu++11
LDFLAGS   += -arch $(ARCH) -isysroot $(SDK) -mmacosx-version-min=$(MIN_MACOS)
LIBS      := $(JPEG_LIB) -lcups -lcupsimage -lz

# Mesma lista de hpcups_SOURCES do Makefile.am do HPLIP (só os .c/.cpp).
CPP_SOURCES := \
	BreakTables ColorMatcher Compressor Encapsulator EncapsulatorFactory ErnieFilter HPCupsFilter \
	Halftoner Hbpl1 Hbpl1_Wrapper Job LJColor LJFastRaster LJJetReady LJMono LJZjStream LJZxStream \
	Lidil LidilCompress Mode10 Mode2 Mode3 Mode9 ModeDeltaPlus ModeJbig ModeJpeg Pcl3 Pcl3Gui \
	Pcl3Gui2 Pipeline Processor QuickConnect RasterSender RunLenEncoding Scaler SystemServices Utils \
	dbuscomm dj3320ColorMaps dj3600ColorMaps dj400ColorMaps dj4100ColorMaps dj600ColorMaps \
	dj8xxColorMaps dj970ColorMaps genJPEGStrips genPCLm
C_SOURCES := jccolor jdatadbf

OBJS := $(addprefix $(BUILD_DIR)/obj/,$(addsuffix .o,$(CPP_SOURCES) $(C_SOURCES) hplip_utils))

.PHONY: all check clean

# Prepara os fontes antes; só depois o make consegue achar os .cpp em build/src.
all: $(SRC_DIR)/.prepared
	@$(MAKE) --no-print-directory $(BUILD_DIR)/hpcups

$(BUILD_DIR)/hpcups: $(OBJS)
	$(CXX) $(LDFLAGS) -o $@ $^ $(LIBS)
	strip -x $@
	codesign --force --sign - $@

$(BUILD_DIR)/obj/%.o: $(SRC_DIR)/%.cpp $(SRC_DIR)/.prepared | $(BUILD_DIR)/obj
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/obj/%.o: $(SRC_DIR)/%.c $(SRC_DIR)/.prepared | $(BUILD_DIR)/obj
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/obj:
	mkdir -p $@

# Copia os fontes para build/src e resolve um conflito de nomes que só existe no macOS:
# o HPLIP tem prnt/hpcups/Utils.h e common/utils.h, arquivos diferentes. No Linux (sistema de arquivos
# que diferencia maiúsculas) cada #include acha o seu; no APFS padrão os dois viram o mesmo arquivo.
# Aqui o common/utils.{c,h} vira hplip_utils.{c,h} e os #include "utils.h" passam a apontar para ele
# (o mesmo vale para os objetos: utils.o e Utils.o seriam o mesmo arquivo).
# Outros ajustes de Linux para macOS: <malloc.h> não existe (malloc está em <stdlib.h>) e o genPCLm.cpp
# inclui o utils.h por caminho relativo à árvore do HPLIP.
$(SRC_DIR)/.prepared:
	@test -d $(HPLIP_DIR) || { echo "Código do HPLIP não encontrado em $(HPLIP_DIR). Rode ./scripts/fetch-hplip.sh"; exit 1; }
	@test -f $(JPEGINT_H) || { echo "jpegint.h não encontrado em $(JPEGINT_H). Rode ./scripts/fetch-hplip.sh"; exit 1; }
	@test -f $(JPEG_LIB) || { echo "libjpeg.a não encontrada. Instale com: brew install jpeg-turbo"; exit 1; }
	rm -rf $(SRC_DIR) && mkdir -p $(SRC_DIR)
	cp $(HPLIP_DIR)/prnt/hpcups/*.c $(HPLIP_DIR)/prnt/hpcups/*.cpp $(HPLIP_DIR)/prnt/hpcups/*.h $(SRC_DIR)/
	cp $(HPLIP_DIR)/common/utils.c $(SRC_DIR)/hplip_utils.c
	cp $(HPLIP_DIR)/common/utils.h $(SRC_DIR)/hplip_utils.h
	cp $(HPLIP_DIR)/io/hpmud/hpmud.h $(SRC_DIR)/
	cp $(JPEGINT_H) $(SRC_DIR)/
	cd $(SRC_DIR) && LC_ALL=C sed -i '' \
		-e 's|#include "utils.h"|#include "hplip_utils.h"|' \
		-e 's|#include "./../../common/utils.h"|#include "hplip_utils.h"|' \
		-e 's|#include <malloc.h>|#include <stdlib.h>|' \
		*.c *.cpp *.h
	touch $@

check: $(BUILD_DIR)/hpcups
	file $<
	otool -L $<
	@if otool -L $< | tail -n +2 | grep -v -E '^\s+/usr/lib/|^\s+/System/Library/'; then \
		echo "ERRO: o filtro depende de biblioteca fora do sistema"; exit 1; \
	else echo "OK: só bibliotecas do sistema"; fi
	codesign -dv $< 2>&1 | grep -E 'Signature|Identifier|flags'

clean:
	rm -rf $(BUILD_DIR)
