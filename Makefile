# Installation path for executables
LOCAL_DIR := $(PWD)/local
# Local programs should have higher path priority than system-installed programs
export PATH := $(LOCAL_DIR)/bin:$(PATH)

# Allow specifying the number of jobs for toolchain build for systems that need it.
# Due to different build systems used in the toolchain build, just `make -j` won't work here.
# Note: Plugin build uses `$(MAKE)` to inherit `-j` argument from command line.
ifdef JOBS
export JOBS := $(JOBS)
# Define number of jobs for crosstool-ng (uses different argument format)
export JOBS_CT_NG := .$(JOBS)
else
# If `JOBS` is not specified, default to max number of jobs.
export JOBS :=
export JOBS_CT_NG :=
endif

WGET := wget -c
UNTAR := tar -x -f
UNZIP := unzip
SHA256 := sha256check() { echo "$$2  $$1" | sha256sum -c; }; sha256check

RACK_SDK_VERSION := 2.6.6
DOCKER_IMAGE_VERSION := 19

all: toolchain-all rack-sdk-all

# Toolchain build

toolchain-all: toolchain-lin toolchain-win cppcheck

crosstool-ng := $(LOCAL_DIR)/bin/ct-ng
$(crosstool-ng):
	git clone "https://github.com/crosstool-ng/crosstool-ng.git" crosstool-ng
	cd crosstool-ng && git checkout 899e015abf8c70088e8b67e87586ae81f305711c
	cd crosstool-ng && ./bootstrap
	cd crosstool-ng && ./configure --prefix="$(LOCAL_DIR)"
	cd crosstool-ng && make -j $(JOBS)
	cd crosstool-ng && make install
	rm -rf crosstool-ng


toolchain-lin := $(LOCAL_DIR)/x86_64-ubuntu16.04-linux-gnu
toolchain-lin: $(toolchain-lin)
$(toolchain-lin): $(crosstool-ng)
	$(WGET) "https://ftp.gnu.org/gnu/texinfo/texinfo-7.2.tar.gz"
	$(SHA256) texinfo-7.2.tar.gz e86de7dfef6b352aa1bf647de3a6213d1567c70129eccbf8977706d9c91919c8
	$(UNTAR) texinfo-7.2.tar.gz
	rm texinfo-7.2.tar.gz
	cd texinfo-7.2 && ./configure --prefix="$(LOCAL_DIR)"
	cd texinfo-7.2 && make -j $(JOBS)
	cd texinfo-7.2 && make install -j $(JOBS)
	rm -rf texinfo-7.2

	ct-ng x86_64-ubuntu16.04-linux-gnu
	CT_PREFIX="$(LOCAL_DIR)" ct-ng build$(JOBS_CT_NG)
	rm -rf .build .config build.log
	# HACK Copy GL and related include dirs to toolchain sysroot
	chmod +w $(toolchain-lin)/x86_64-ubuntu16.04-linux-gnu/sysroot/usr/include
	cp -r /usr/include/GL $(toolchain-lin)/x86_64-ubuntu16.04-linux-gnu/sysroot/usr/include/
	cp -r /usr/include/KHR $(toolchain-lin)/x86_64-ubuntu16.04-linux-gnu/sysroot/usr/include/
	cp -r /usr/include/X11 $(toolchain-lin)/x86_64-ubuntu16.04-linux-gnu/sysroot/usr/include/
	chmod -w $(toolchain-lin)/x86_64-ubuntu16.04-linux-gnu/sysroot/usr/include

toolchain-win := $(LOCAL_DIR)/x86_64-w64-mingw32
toolchain-win: $(toolchain-win)
$(toolchain-win): $(crosstool-ng)
	ct-ng x86_64-w64-mingw32
	# I don't know how to set crosstool-ng variables from the command line
	sed -i 's/CT_MINGW_W64_VERSION=.*/CT_MINGW_W64_VERSION="v10.0.0"/' .config
	CT_PREFIX="$(LOCAL_DIR)" ct-ng build$(JOBS_CT_NG)
	rm -rf .build .config build.log

CPPCHECK_VERSION := 2.16.0
cppcheck := $(LOCAL_DIR)/cppcheck/bin/cppcheck
cppcheck: $(cppcheck)
$(cppcheck):
	$(WGET) "https://github.com/danmar/cppcheck/archive/refs/tags/$(CPPCHECK_VERSION).tar.gz"
	$(UNTAR) $(CPPCHECK_VERSION).tar.gz
	cd cppcheck-$(CPPCHECK_VERSION) && mkdir build
	cd cppcheck-$(CPPCHECK_VERSION)/build \
		&& cmake .. \
		-DUSE_MATCHCOMPILER=On \
		-DUSE_THREADS=On \
		-DCMAKE_INSTALL_PREFIX=$(LOCAL_DIR)/cppcheck \
		&& cmake --build . -j \
		&& cmake --install .
	rm $(CPPCHECK_VERSION).tar.gz
	rm -rf cppcheck-$(CPPCHECK_VERSION)

toolchain-clean:
	rm -rf local .build build.log .config

# Rack SDK

rack-sdk-all: rack-sdk-win-x64 rack-sdk-lin-x64

rack-sdk-win-x64 := Rack-SDK-win-x64
rack-sdk-win-x64: $(rack-sdk-win-x64)
$(rack-sdk-win-x64):
	$(WGET) "https://vcvrack.com/downloads/Rack-SDK-$(RACK_SDK_VERSION)-win-x64.zip"
	$(UNZIP) Rack-SDK-$(RACK_SDK_VERSION)-win-x64.zip
	mv Rack-SDK Rack-SDK-win-x64
	rm Rack-SDK-$(RACK_SDK_VERSION)-win-x64.zip
RACK_DIR_WIN_X64 := $(PWD)/$(rack-sdk-win-x64)

rack-sdk-lin-x64 := Rack-SDK-lin-x64
rack-sdk-lin-x64: $(rack-sdk-lin-x64)
$(rack-sdk-lin-x64):
	$(WGET) "https://vcvrack.com/downloads/Rack-SDK-$(RACK_SDK_VERSION)-lin-x64.zip"
	$(UNZIP) Rack-SDK-$(RACK_SDK_VERSION)-lin-x64.zip
	mv Rack-SDK Rack-SDK-lin-x64
	rm Rack-SDK-$(RACK_SDK_VERSION)-lin-x64.zip
RACK_DIR_LIN_X64 := $(PWD)/$(rack-sdk-lin-x64)

rack-sdk-clean:
	rm -rf $(rack-sdk-win-x64) $(rack-sdk-lin-x64)

# Plugin build
PLUGIN_BUILD_DIR := plugin-build
PLUGIN_DIR ?=

plugin-build:
	$(MAKE) plugin-build-win-x64
	$(MAKE) plugin-build-lin-x64

plugin-build-win:
	$(MAKE) plugin-build-win-x64

plugin-build-lin:
	$(MAKE) plugin-build-lin-x64

plugin-build-win-x64: export PATH := $(LOCAL_DIR)/x86_64-w64-mingw32/bin:$(PATH)
plugin-build-win-x64: export CC := x86_64-w64-mingw32-gcc
plugin-build-win-x64: export CXX := x86_64-w64-mingw32-g++
plugin-build-win-x64: export STRIP := x86_64-w64-mingw32-strip
plugin-build-win-x64: export OBJCOPY := x86_64-w64-mingw32-objcopy

plugin-build-lin-x64: export PATH:=$(LOCAL_DIR)/x86_64-ubuntu16.04-linux-gnu/bin:$(PATH)
plugin-build-lin-x64: export CC := x86_64-ubuntu16.04-linux-gnu-gcc
plugin-build-lin-x64: export CXX := x86_64-ubuntu16.04-linux-gnu-g++
plugin-build-lin-x64: export STRIP := x86_64-ubuntu16.04-linux-gnu-strip
plugin-build-lin-x64: export OBJCOPY := x86_64-ubuntu16.04-linux-gnu-objcopy

plugin-build-win-x64: export RACK_DIR := $(RACK_DIR_WIN_X64)
plugin-build-lin-x64: export RACK_DIR := $(RACK_DIR_LIN_X64)

plugin-build-win-x64 plugin-build-lin-x64:
	cd $(PLUGIN_DIR) && $(MAKE) clean
	cd $(PLUGIN_DIR) && $(MAKE) cleandep
	cd $(PLUGIN_DIR) && $(MAKE) dep
	cd $(PLUGIN_DIR) && $(MAKE) dist
	mkdir -p $(PLUGIN_BUILD_DIR)
	cp $(PLUGIN_DIR)/dist/*.vcvplugin $(PLUGIN_BUILD_DIR)/
	cd $(PLUGIN_DIR) && $(MAKE) clean

plugin-build-clean:
	rm -rf $(PLUGIN_BUILD_DIR)

# Static Analysis

static-analysis-cppcheck: export PATH := $(LOCAL_DIR)/cppcheck/bin:$(PATH)
static-analysis-cppcheck: cppcheck
	cd $(PLUGIN_DIR) && cppcheck src/ -isrc/dep --std=c++11 -j $(shell nproc) --error-exitcode=1

plugin-analyze: static-analysis-cppcheck

# Docker helpers
dep-ubuntu:
	sudo apt-get install --no-install-recommends \
		ca-certificates \
		git \
		build-essential \
		autoconf \
		automake \
		bison \
		flex \
		gawk \
		libtool-bin \
		libncurses5-dev \
		unzip \
		zip \
		jq \
		libgl-dev \
		libglu-dev \
		git \
		wget \
		curl \
		cmake \
		nasm \
		xz-utils \
		file \
		python3 \
		libxml2-dev \
		libssl-dev \
		texinfo \
		help2man \
		libz-dev \
		rsync \
		xxd \
		perl \
		coreutils \
		zstd \
		markdown \
		libarchive-tools \
		gettext \
		libgmp-dev \
		libmpfr-dev

dep-arch-linux:
	sudo pacman -S --needed \
		gcc \
		git \
		cmake \
		patch \
		python3 \
		automake \
		help2man \
		texinfo \
		libtool \
		jq \
		rsync \
		autoconf \
		flex \
		bison \
		which \
		unzip \
		wget \
		glu \
		libx11 \
		mesa

docker-build: rack-sdk-all
	docker build --build-arg JOBS=$(JOBS) --no-cache --tag rack-plugin-toolchain:$(DOCKER_IMAGE_VERSION) . --progress=plain 2>&1 | tee docker-build.log

DOCKER_RUN := docker run --rm --interactive --tty \
	--volume=$(PLUGIN_DIR):/home/build/plugin-src \
	--volume=$(PWD)/$(PLUGIN_BUILD_DIR):/home/build/rack-plugin-toolchain/$(PLUGIN_BUILD_DIR) \
	--volume=$(PWD)/Rack-SDK-win-x64:/home/build/rack-plugin-toolchain/Rack-SDK-win-x64 \
	--volume=$(PWD)/Rack-SDK-lin-x64:/home/build/rack-plugin-toolchain/Rack-SDK-lin-x64 \
	--env PLUGIN_DIR=/home/build/plugin-src \
	rack-plugin-toolchain:$(DOCKER_IMAGE_VERSION) \
	/bin/bash

docker-run:
	$(DOCKER_RUN)

docker-plugin-build:
	mkdir -p $(PLUGIN_BUILD_DIR)
	$(DOCKER_RUN) -c "$(MAKE) plugin-build $(MFLAGS)"

docker-plugin-build-win-x64:
	mkdir -p $(PLUGIN_BUILD_DIR)
	$(DOCKER_RUN) -c "$(MAKE) plugin-build-win-x64 $(MFLAGS)"

docker-plugin-build-lin-x64:
	mkdir -p $(PLUGIN_BUILD_DIR)
	$(DOCKER_RUN) -c "$(MAKE) plugin-build-lin-x64 $(MFLAGS)"

docker-plugin-analyze:
	$(DOCKER_RUN) -c "$(MAKE) plugin-analyze $(MFLAGS)"

.NOTPARALLEL:
.PHONY: all plugin-build plugin-analyze