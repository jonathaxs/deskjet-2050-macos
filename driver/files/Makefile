# Builds only the hpcups CUPS filter from HPLIP, native for macOS arm64.
# Does not use the HPLIP configure script: it requires libusb, SANE, net-snmp and other things the
# filter does not need.
#
# Usage:
#   ./scripts/fetch-hplip.sh   # downloads and verifies the HPLIP source into downloads/
#   make                       # builds build/hpcups
#   make check                 # checks architecture, linked libraries and signature

HPLIP_VERSION ?= 3.26.4
HPLIP_DIR     ?= downloads/hplip-$(HPLIP_VERSION)
BUILD_DIR     ?= build

# libjpeg from Homebrew (jpeg-turbo), linked statically so the filter only depends on system libraries.
JPEG_PREFIX   ?= $(shell brew --prefix jpeg-turbo 2>/dev/null)
JPEG_LIB      ?= $(JPEG_PREFIX)/lib/libjpeg.a
# Internal libjpeg header (not shipped by Homebrew), downloaded by fetch-hplip.sh for the same version.
JPEGINT_H     ?= downloads/jpegint.h

SDK           := $(shell xcrun --show-sdk-path)
CC            := xcrun clang
CXX           := xcrun clang++
ARCH          ?= arm64
# The build runs on the user's own Mac; Homebrew's libjpeg is already built for the installed version.
MIN_MACOS     ?= $(shell sw_vers -productVersion | cut -d. -f1-2)

# DISABLE_IMAGEPROCESSOR: skips the closed-source libImageProcessor (x86 only, used only by ljzjstream lasers).
# No HAVE_DBUS: the DBus notification is optional and macOS has no DBus.
# CONFDIR: where the filter looks for an optional hplip.conf (without the file it uses the defaults).
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

# Same list as hpcups_SOURCES in the HPLIP Makefile.am (only the .c/.cpp files).
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

# Prepare the sources first; only then can make find the .cpp files in build/src.
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

# Copies the sources into build/src and fixes a name clash that only happens on macOS:
# HPLIP has prnt/hpcups/Utils.h and common/utils.h, two different files. On Linux (case-sensitive
# file system) each #include finds its own; on default APFS both are the same file.
# Here common/utils.{c,h} becomes hplip_utils.{c,h} and #include "utils.h" points to it
# (the same goes for the objects: utils.o and Utils.o would be the same file).
# Other Linux-to-macOS fixes: <malloc.h> does not exist (malloc is in <stdlib.h>) and genPCLm.cpp
# includes utils.h by a path relative to the HPLIP tree.
$(SRC_DIR)/.prepared:
	@test -d $(HPLIP_DIR) || { echo "HPLIP source not found in $(HPLIP_DIR). Run ./scripts/fetch-hplip.sh"; exit 1; }
	@test -f $(JPEGINT_H) || { echo "jpegint.h not found in $(JPEGINT_H). Run ./scripts/fetch-hplip.sh"; exit 1; }
	@test -f $(JPEG_LIB) || { echo "libjpeg.a not found. Install it with: brew install jpeg-turbo"; exit 1; }
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
		echo "ERROR: the filter depends on a library outside the system"; exit 1; \
	else echo "OK: system libraries only"; fi
	codesign -dv $< 2>&1 | grep -E 'Signature|Identifier|flags'

clean:
	rm -rf $(BUILD_DIR)
