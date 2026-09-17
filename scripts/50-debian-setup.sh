#!/usr/bin/env bash
# Runs INSIDE the Debian 13 aarch64 VM.
#
# WHY DEBIAN 13: it ships clang 19 -- an exact match for the toolchain kkHAIKE
# developed PR #1753 against -- paired with a libstdc++ that clang 19 can actually
# parse. Fedora 44 was the wrong choice: clang 22 (its default) is too strict for
# Darling's C, and clang 18 (its compat package) cannot parse Fedora's libstdc++ 16
# headers. See FINDINGS.md "METHODOLOGICAL CORRECTION".
set -uo pipefail

log() { printf '\n=== %s ===\n' "$*"; }

log "host"
uname -m; cat /etc/debian_version; nproc

log "apt update"
sudo apt-get update -qq

# Darling's documented Debian 13 list, minus libc6-dev-i386 (x86-only, absent on
# arm64). apt has no --skip-unavailable, so try the batch then fall back to
# one-by-one so a single missing package can't abort everything.
PKGS="cmake clang lld bison flex xz-utils libfuse-dev libudev-dev pkg-config
libcap2-bin git git-lfs libglu1-mesa-dev libcairo2-dev libgl1-mesa-dev
libtiff-dev libfreetype6-dev libxml2-dev libegl1-mesa-dev libfontconfig1-dev
libbsd-dev libxrandr-dev libxcursor-dev libgif-dev libpulse-dev libavformat-dev
libavcodec-dev libswresample-dev libdbus-1-dev libxkbfile-dev libssl-dev
libvulkan-dev libcurl4-openssl-dev libedit-dev libxml2-utils python3 make
build-essential libxi-dev libxrender-dev libx11-dev libxkbcommon-dev
libelf-dev libsystemd-dev libtirpc-dev libjpeg-dev libpng-dev ninja-build"

log "installing dependencies"
if ! sudo apt-get install -y --no-install-recommends $PKGS 2>/dev/null; then
    echo "batch install failed; falling back to per-package"
    for p in $PKGS; do
        sudo apt-get install -y --no-install-recommends "$p" >/dev/null 2>&1 \
            || echo "  UNAVAILABLE: $p"
    done
fi

# Debian uses multiarch include paths (/usr/include/aarch64-linux-gnu/asm) while
# Fedora puts kernel headers at /usr/include/asm. Darling's build assumes the Fedora
# layout, so <linux/types.h> -> <asm/types.h> fails to resolve (hits fseventsd.m in
# CoreServices at ~89%). Bridge it.
log "bridging multiarch kernel headers"
if [ ! -e /usr/include/asm ] && [ -d /usr/include/aarch64-linux-gnu/asm ]; then
    sudo ln -sfn /usr/include/aarch64-linux-gnu/asm /usr/include/asm
    echo "  linked /usr/include/asm -> /usr/include/aarch64-linux-gnu/asm"
else
    echo "  /usr/include/asm already present"
fi

log "toolchain"
clang --version | head -2
cmake --version | head -1
echo "libstdc++ headers: $(ls -d /usr/include/c++/* 2>/dev/null | tr '\n' ' ')"

log "unpacking source tree"
cd "$HOME"
if [ ! -d darling ]; then
    [ -f /tmp/darling-src.tgz ] || { echo "FATAL: /tmp/darling-src.tgz missing"; exit 1; }
    tar xzf /tmp/darling-src.tgz
fi
cd darling
echo "HEAD: $(git rev-parse --short HEAD)"
echo "submodules present: $(git submodule status --recursive 2>/dev/null | grep -vc '^-')"
echo "submodules missing: $(git submodule status --recursive 2>/dev/null | grep -c '^-')"
echo "mismatched:         $(git submodule status --recursive 2>/dev/null | grep -c '^+')"

log "local patch state (expect F1+F2 applied, F6 REVERTED)"
for f in src/external/xnu/darling/src/libsystem_kernel/emulation/include/linux_premigration/ext/sys/epoll.h \
         src/external/libkqueue/src/linux/timer.c \
         src/external/libffi/darwin/include/fficonfig_arm64.h; do
    printf '  %-58s %s\n' "$(basename "$f")" \
      "$(grep -c 'DARLING-ARM64 LOCAL PATCH' "$f" 2>/dev/null || echo 0) patch marker(s)"
done

log "done — next: scripts/51-debian-build.sh"
