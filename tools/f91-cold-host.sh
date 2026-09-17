#!/usr/bin/env bash
# F91: the cold-host number — issue 2's actual question.
#
# Runs INSIDE a fresh Lima VM (darling-cold) that has ONLY: Ubuntu 24.04 aarch64,
# docker, git. Measures, timed per phase, the true from-nothing path a new
# contributor faces: clone → build images from Dockerfiles → bootstrap-stable
# (Kevin's, Stage 0–17) → our stage18 bootstrap → launch probe. The dyld shared
# cache is pre-staged from the host Mac (documented, unavoidable — it is Apple's),
# and that asterisk ships with the number.
#
# Caveat that ships with the result: this "cold host" is a second VM on a machine
# whose primary VM exists (idle during the run, but resident). Stated, not hidden.
set -u
T0=$(date +%s)
mark() { printf '%s  %6ss  %s\n' "$(date +%H:%M:%S)" "$(( $(date +%s) - T0 ))" "$*"; }

W=$HOME/darling
mkdir -p "$W"; cd "$W"

# COLD-HOST FINDING, measured before any workaround: the recursive clone fails for
# 100% of submodules as shipped. .gitmodules uses relative URLs (../darling-X.git)
# resolving to deepai-org/darling-X, but the org's forks are named
# darling-aarch64-X and only six exist; the rest live at darlinghq. No vanilla
# contributor can pass step zero. The rewrites below are the workaround, and the
# measured time from here on is "cold host + this documented workaround".
mark "phase 0a: submodule URL rewrites (workaround for broken relative URLs)"
git config --global url."https://github.com/deepai-org/darling-aarch64-north-star".insteadOf "https://github.com/deepai-org/darling-aarch64-north-star"
git config --global url."https://github.com/deepai-org/darling-getting-started".insteadOf "https://github.com/deepai-org/darling-getting-started"
# complete fork table (35 rules), generated mechanically from the working tree's
# actual submodule remotes -- names are case-folded and underscore-normalized in
# ways .gitmodules cannot predict (IOKitUser -> darling-aarch64-iokituser):
git config --global url."https://github.com/deepai-org/darling-aarch64-iokituser".insteadOf "https://github.com/deepai-org/darling-iokituser"
git config --global url."https://github.com/deepai-org/darling-aarch64-javascriptcore".insteadOf "https://github.com/deepai-org/darling-JavaScriptCore"
git config --global url."https://github.com/deepai-org/darling-aarch64-libinfo".insteadOf "https://github.com/deepai-org/darling-Libinfo"
git config --global url."https://github.com/deepai-org/darling-aarch64-textedit".insteadOf "https://github.com/deepai-org/darling-TextEdit"
git config --global url."https://github.com/deepai-org/darling-aarch64-bootstrap-cmds".insteadOf "https://github.com/deepai-org/darling-bootstrap_cmds"
git config --global url."https://github.com/deepai-org/darling-aarch64-bzip2".insteadOf "https://github.com/deepai-org/darling-bzip2"
git config --global url."https://github.com/deepai-org/darling-aarch64-cctools-port".insteadOf "https://github.com/deepai-org/cctools-port"
git config --global url."https://github.com/deepai-org/darling-aarch64-cfnetwork".insteadOf "https://github.com/deepai-org/darling-cfnetwork"
git config --global url."https://github.com/deepai-org/darling-aarch64-cocotron".insteadOf "https://github.com/deepai-org/darling-cocotron"
git config --global url."https://github.com/deepai-org/darling-aarch64-compiler-rt".insteadOf "https://github.com/deepai-org/darling-compiler-rt"
git config --global url."https://github.com/deepai-org/darling-aarch64-configd".insteadOf "https://github.com/deepai-org/darling-configd"
git config --global url."https://github.com/deepai-org/darling-aarch64-corefoundation".insteadOf "https://github.com/deepai-org/darling-corefoundation"
git config --global url."https://github.com/deepai-org/darling-aarch64-darlingserver".insteadOf "https://github.com/deepai-org/darlingserver"
git config --global url."https://github.com/deepai-org/darling-aarch64-dyld".insteadOf "https://github.com/deepai-org/darling-dyld"
git config --global url."https://github.com/deepai-org/darling-aarch64-expat".insteadOf "https://github.com/deepai-org/darling-expat"
git config --global url."https://github.com/deepai-org/darling-aarch64-foundation".insteadOf "https://github.com/deepai-org/darling-foundation"
git config --global url."https://github.com/deepai-org/darling-aarch64-icu".insteadOf "https://github.com/deepai-org/darling-icu"
git config --global url."https://github.com/deepai-org/darling-aarch64-libc".insteadOf "https://github.com/deepai-org/darling-Libc"
git config --global url."https://github.com/deepai-org/darling-aarch64-libdispatch".insteadOf "https://github.com/deepai-org/darling-libdispatch"
git config --global url."https://github.com/deepai-org/darling-aarch64-libmalloc".insteadOf "https://github.com/deepai-org/darling-libmalloc"
git config --global url."https://github.com/deepai-org/darling-aarch64-libnotify".insteadOf "https://github.com/deepai-org/darling-Libnotify"
git config --global url."https://github.com/deepai-org/darling-aarch64-libplatform".insteadOf "https://github.com/deepai-org/darling-libplatform"
git config --global url."https://github.com/deepai-org/darling-aarch64-libpthread".insteadOf "https://github.com/deepai-org/darling-libpthread"
git config --global url."https://github.com/deepai-org/darling-aarch64-libsystem".insteadOf "https://github.com/deepai-org/darling-Libsystem"
git config --global url."https://github.com/deepai-org/darling-aarch64-libtrace".insteadOf "https://github.com/deepai-org/darling-libtrace"
git config --global url."https://github.com/deepai-org/darling-aarch64-libunwind".insteadOf "https://github.com/deepai-org/darling-libunwind"
git config --global url."https://github.com/deepai-org/darling-aarch64-libxpc".insteadOf "https://github.com/deepai-org/darling-libxpc"
git config --global url."https://github.com/deepai-org/darling-aarch64-metal".insteadOf "https://github.com/deepai-org/darling-metal"
git config --global url."https://github.com/deepai-org/darling-aarch64-objc4".insteadOf "https://github.com/deepai-org/darling-objc4"
git config --global url."https://github.com/deepai-org/darling-aarch64-security".insteadOf "https://github.com/deepai-org/darling-security"
git config --global url."https://github.com/deepai-org/darling-aarch64-shell-cmds".insteadOf "https://github.com/deepai-org/darling-shell_cmds"
git config --global url."https://github.com/deepai-org/darling-aarch64-sqlite".insteadOf "https://github.com/deepai-org/darling-sqlite"
git config --global url."https://github.com/deepai-org/darling-aarch64-vim".insteadOf "https://github.com/deepai-org/darling-vim"
git config --global url."https://github.com/deepai-org/darling-aarch64-xnu".insteadOf "https://github.com/deepai-org/darling-xnu"
git config --global url."https://github.com/deepai-org/darling-aarch64-zlib".insteadOf "https://github.com/deepai-org/darling-zlib"
git config --global url."https://github.com/darlinghq/".insteadOf "https://github.com/deepai-org/darling-"
# NB: the broad rule strips the "darling-" prefix wrongly; use exact form instead:
git config --global --unset url."https://github.com/darlinghq/".insteadOf
git config --global url."https://github.com/darlinghq/darling-".insteadOf "https://github.com/deepai-org/darling-"
# and the submodules whose names carry no darling- prefix (cctools-port, ...):
git config --global url."https://github.com/darlinghq/".insteadOf "https://github.com/deepai-org/"

mark "phase 0: clone north-star (recursive)"
# no --shallow-submodules: the superproject pins are not branch tips, so shallow
# fetches miss them (v4 failure) -- and full histories are the true cold cost anyway
# --branch: the DEFAULT branch (community-integration) pins a dyld commit that
# exists on no public ref of the dyld fork -- the author's own current tree is
# un-fetchable for anyone. The reviewed branch's pins are all live-reachable, so
# clone it directly.
git clone --recurse-submodules --branch north-star/arm64-verified-fixes \
  https://github.com/deepai-org/darling-aarch64-north-star.git source \
  > clone.log 2>&1
rc=$?; mark "clone rc=$rc"
(( rc == 0 )) || { echo "FATAL: clone failed"; tail -5 clone.log; exit 1; }
cd source
mark "reviewed branch cloned recursively"

mark "phase 1: build builder image from Dockerfile"
git clone https://github.com/deepai-org/darling-getting-started.git ../getting-started > /dev/null 2>&1
docker build --platform linux/arm64 -t darling-arm64-dev:24.04 -f ../getting-started/Dockerfile ../getting-started > ../image-build.log 2>&1
rc=$?; mark "builder image rc=$rc"
docker tag darling-arm64-dev:24.04 darling-arm64-dev:latest

mark "phase 2: build GUI test image (north-star Dockerfile.gui-deps)"
docker build --platform linux/arm64 -t darling-arm64-gui-test:latest -f north-star/scripts/Dockerfile.gui-deps north-star/scripts > ../gui-image.log 2>&1
rc=$?; mark "gui image rc=$rc"

mark "phase 3: bootstrap-stable (Kevin's, Stage 0-17)"
../getting-started/scripts/bootstrap-stable.sh > ../bootstrap-stable.log 2>&1
rc=$?; mark "bootstrap-stable rc=$rc"
(( rc == 0 )) || { echo "STOPPED at bootstrap-stable; first error:"; grep -m3 -iE "error|failed" ../bootstrap-stable.log; exit 1; }

mark "phase 4: our stage18 bootstrap (assumes cache pre-staged in ~/darling/downloads)"
tools/bootstrap-iterm2-stage18.sh > ../stage18-bootstrap.log 2>&1
rc=$?; mark "stage18 bootstrap rc=$rc"

mark "TOTAL cold-host wall clock: $(( ($(date +%s) - T0) / 60 ))m"