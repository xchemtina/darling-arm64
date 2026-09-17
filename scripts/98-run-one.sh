#!/usr/bin/env bash
# Run ONE corpus binary under Darling with completely unfiltered output.
#
# WHY: 91-corpus.sh strips objc/dyld/libEGL noise and collapses newlines so it can
# diff against ground truth. That is right for scoring and wrong for debugging -- a
# SIGSEGV frame chain looks exactly like noise to that filter. This runs a single
# binary and shows everything.
#
#   ~/98-run-one.sh t33_thread.arm64e
set -uo pipefail

BIN="${1:?usage: 98-run-one.sh <corpus-binary-name>}"
STAGE="${DARLING_ARM64_INSTALL_ROOT:-$HOME/darling/install-arm64-stage10}"
CORPUS="$HOME/corpus"
IMAGE="${DARLING_ARM64_IMAGE:-darling-arm64-dev:latest}"

[ -f "$CORPUS/bin/$BIN" ] || { echo "no such corpus binary: $BIN"; exit 1; }

docker rm -f darling-runone >/dev/null 2>&1 || true
docker run --name darling-runone --rm \
    -e DARLING_ARM64_THREAD_BRIDGE=1 \
    -e "TARGET=$BIN" \
    --cap-add SYS_ADMIN --cap-add SYS_PTRACE \
    --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
    -v "$STAGE/root:/usr/local/libexec/darling:ro" \
    -v "$STAGE/bin:/opt/darling/bin:ro" \
    -v "$CORPUS/bin:/corpus-in:ro" \
    "$IMAGE" bash -lc '
        set -u
        prefix=/tmp/darling-prefix
        mkdir -p "$prefix/dev/pts" "$prefix/corpus"
        cp -a /dev/null /dev/urandom "$prefix/dev/" 2>/dev/null || true
        mount --bind /dev/pts "$prefix/dev/pts" 2>/dev/null || true
        ln -sf pts/ptmx "$prefix/dev/ptmx" 2>/dev/null || true
        cp /corpus-in/* "$prefix/corpus/" 2>/dev/null || true
        chmod -R a+rx "$prefix/corpus"

        export PATH=/opt/darling/bin:$PATH
        export DARLING_NOOVERLAYFS=1
        # Pass through any DYLD_/OBJC_ diagnostics the caller set.
        DSERVER_INIT="/corpus/$TARGET" timeout -s KILL 120 \
            darlingserver "$prefix" 0 0 3 0 2>&1
        echo "=== EXIT: $?"
    '
