#!/bin/bash

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build"
CUDA_OUTPUT_PATH="$ROOT_DIR/comfy_aimdo/aimdo.so"
ROCM_OUTPUT_PATH="$ROOT_DIR/comfy_aimdo/aimdo_rocm.so"
FUNCHOOK_VERSION=1.1.3
FUNCHOOK_SRC="$BUILD_DIR/funchook-$FUNCHOOK_VERSION"
FUNCHOOK_TARBALL="$BUILD_DIR/funchook-$FUNCHOOK_VERSION.tar.gz"

ARCH=$(uname -m)

# Select disassembler based on architecture
# funchook uses distorm on x86_64, capstone on aarch64
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    FUNCHOOK_DISASM=capstone
    FUNCHOOK_BUILD_DIR="$BUILD_DIR/funchook-$FUNCHOOK_VERSION-capstone"
else
    FUNCHOOK_DISASM=distorm
    FUNCHOOK_BUILD_DIR="$BUILD_DIR/funchook-$FUNCHOOK_VERSION-distorm"
fi

if [ ! -f "$FUNCHOOK_SRC/CMakeLists.txt" ]; then
    URL="https://github.com/kubo/funchook/releases/download/v$FUNCHOOK_VERSION/funchook-$FUNCHOOK_VERSION.tar.gz"

    mkdir -p "$BUILD_DIR"
    curl -fL "$URL" -o "$FUNCHOOK_TARBALL"
    rm -rf "$FUNCHOOK_SRC"
    tar -xzf "$FUNCHOOK_TARBALL" -C "$BUILD_DIR"
fi

FUNCHOOK_READY=false
if [ "$FUNCHOOK_DISASM" = "capstone" ]; then
    [ -f "$FUNCHOOK_BUILD_DIR/libfunchook.a" ] && \
    [ -f "$FUNCHOOK_BUILD_DIR/capstone-build/libcapstone.a" ] && \
    FUNCHOOK_READY=true
else
    [ -f "$FUNCHOOK_BUILD_DIR/libfunchook.a" ] && \
    [ -f "$FUNCHOOK_BUILD_DIR/libdistorm.a" ] && \
    FUNCHOOK_READY=true
fi

if [ "$FUNCHOOK_READY" = "false" ]; then
    if ! command -v cmake >/dev/null 2>&1; then
        echo "cmake is required to build funchook" >&2
        exit 1
    fi

    mkdir -p "$FUNCHOOK_BUILD_DIR"

    cmake -S "$FUNCHOOK_SRC" -B "$FUNCHOOK_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DFUNCHOOK_BUILD_SHARED=OFF \
        -DFUNCHOOK_BUILD_STATIC=ON \
        -DFUNCHOOK_BUILD_TESTS=OFF \
        -DFUNCHOOK_DISASM="$FUNCHOOK_DISASM" \
        -DFUNCHOOK_INSTALL=OFF

    cmake --build "$FUNCHOOK_BUILD_DIR" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
fi

mkdir -p "$(dirname -- "$CUDA_OUTPUT_PATH")"

# Collect funchook + disassembler static libraries
FUNCHOOK_LIBS="$FUNCHOOK_BUILD_DIR/libfunchook.a"
if [ "$FUNCHOOK_DISASM" = "capstone" ]; then
    FUNCHOOK_LIBS="$FUNCHOOK_LIBS $FUNCHOOK_BUILD_DIR/capstone-build/libcapstone.a"
else
    FUNCHOOK_LIBS="$FUNCHOOK_LIBS $FUNCHOOK_BUILD_DIR/libdistorm.a"
fi

# shellcheck disable=SC2086
gcc -shared -o "$CUDA_OUTPUT_PATH" -fPIC -O2 -g -pthread \
    ${AIMDO_EXTRA_CFLAGS:-} \
    "$ROOT_DIR"/src/*.c "$ROOT_DIR"/src-cuda/dispatch.c "$ROOT_DIR"/src-posix/*.c \
    -I"$ROOT_DIR/src" -I"$FUNCHOOK_SRC/include" \
    $FUNCHOOK_LIBS \
    -ldl

# shellcheck disable=SC2086
gcc -shared -o "$ROCM_OUTPUT_PATH" -fPIC -O2 -g -pthread \
    -D__HIP_PLATFORM_AMD__ \
    ${AIMDO_EXTRA_CFLAGS:-} \
    "$ROOT_DIR"/src/*.c "$ROOT_DIR"/src-hip/dispatch.c "$ROOT_DIR"/src-posix/*.c \
    -I"$ROOT_DIR/src" -I"$FUNCHOOK_SRC/include" \
    $FUNCHOOK_LIBS \
    -ldl
