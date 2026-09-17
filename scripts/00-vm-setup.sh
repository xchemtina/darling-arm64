#!/usr/bin/env bash
# Runs INSIDE the aarch64 Fedora 44 VM.
# Installs Darling build dependencies and clones the arm64 tree.
set -euo pipefail

log() { printf '\n=== %s ===\n' "$*"; }

log "host check"
uname -m; nproc; free -g | head -2

log "installing build dependencies"
# --skip-unavailable is essential: dnf5 rejects the WHOLE transaction if any
# single package fails to resolve, which silently leaves nothing installed.
sudo dnf install -y --skip-unavailable --setopt=install_weak_deps=False \
  git git-lfs make cmake ninja-build clang clang-devel llvm llvm-devel lld bison flex \
  python3 python3-devel pkgconf-pkg-config \
  libbsd-devel libcap-devel libedit-devel libcurl-devel mesa-libGLU-devel \
  fuse-devel fuse3-devel systemd-devel elfutils-libelf-devel \
  cairo-devel freetype-devel fontconfig-devel \
  libjpeg-turbo-devel libtiff-devel giflib-devel libpng-devel \
  libglvnd-devel mesa-libGL-devel mesa-libEGL-devel \
  libxml2-devel libxslt-devel openssl-devel \
  libXcursor-devel libXext-devel libxkbfile-devel libXrandr-devel \
  libXi-devel libXrender-devel libX11-devel libxkbcommon-devel \
  pulseaudio-libs-devel alsa-lib-devel \
  libavcodec-free-devel libavformat-free-devel libavutil-free-devel \
  libudev-devel dbus-devel libtirpc-devel libuuid-devel \
  gcc gcc-c++ which file rsync xz bzip2 patch tar findutils

log "toolchain versions"
# Non-fatal: report what we have rather than aborting the run.
clang --version 2>/dev/null | head -2 || echo "WARNING: clang missing"
cmake --version 2>/dev/null | head -1 || echo "WARNING: cmake missing"
python3 --version 2>/dev/null || true
command -v clang >/dev/null || { echo "FATAL: clang unavailable, cannot continue"; exit 1; }

# ---------------------------------------------------------------------------
# Submodule routing.
#
# darling has 149 submodules declared with RELATIVE urls (../darling-foo.git),
# which resolve against the superproject's origin. We clone from darlinghq so
# all 149 resolve canonically, then redirect only the 31 repos kkHAIKE forked
# for the arm64 work. Using url.<x>.insteadOf (rather than per-submodule config)
# makes the redirect apply at every nesting level automatically.
# ---------------------------------------------------------------------------
KK_FORKS=(
  darling-xnu darlingserver darling-dyld darling-Libsystem
  darling-libxpc darling-expat darling-zlib darling-sqlite
  darling-libunwind darling-openssl darling-iokituser darling-bash
  darling-bootstrap_cmds darling-bzip2 cctools-port darling-cfnetwork
  darling-cocotron darling-corefoundation darling-dbuskit darling-foundation
  darling-Libc darling-liblzma darling-libmalloc darling-libplatform
  darling-libpthread darling-objc4 darling-perl darling-ruby
  darling-security darling-libcxx darling-libcxxabi
)

log "routing ${#KK_FORKS[@]} submodules to kkHAIKE forks"
for r in "${KK_FORKS[@]}"; do
  git config --global \
    "url.https://github.com/kkHAIKE/${r}.git.insteadOf" \
    "https://github.com/darlinghq/${r}.git"
done
git config --global advice.detachedHead false

log "cloning darlinghq/darling"
cd "$HOME"
if [ ! -d darling ]; then
  git clone https://github.com/darlinghq/darling.git
fi
cd darling

log "fetching kkHAIKE arm64-support (PR #1753)"
git remote get-url kkhaike >/dev/null 2>&1 || \
  git remote add kkhaike https://github.com/kkHAIKE/darling.git
git fetch --no-tags kkhaike arm64-support
# --no-track is CRITICAL. Git resolves relative submodule URLs (../darling-foo.git)
# against the CURRENT BRANCH'S TRACKING REMOTE, falling back to origin. If this
# branch tracks kkhaike, all 149 relative URLs resolve to github.com/kkHAIKE/*,
# and the ~118 repos they never forked fail to clone.
git checkout -B arm64-support --no-track kkHAIKE/arm64-support 2>/dev/null \
  || git checkout -B arm64-support --no-track kkhaike/arm64-support
git config --unset branch.arm64-support.remote 2>/dev/null || true
git config --unset branch.arm64-support.merge  2>/dev/null || true

log "superproject state"
git --no-pager log --oneline -12
echo "--- HEAD: $(git rev-parse HEAD)"
echo "--- relative-url base resolves to: $(git config --get remote.origin.url)"

log "re-syncing submodule URLs from .gitmodules"
# Rewrites any URLs a previous bad resolution wrote into .git/config.
git submodule sync --recursive >/dev/null 2>&1 || true

log "initialising submodules (149, recursive — this takes a while)"
git submodule update --init --recursive --jobs 8 2>&1 | grep -v -E "^Cloning into" | tail -40

log "submodule health"
total=$(git submodule status --recursive 2>/dev/null | wc -l)
missing=$(git submodule status --recursive 2>/dev/null | grep -c '^-' || true)
conflict=$(git submodule status --recursive 2>/dev/null | grep -c '^U' || true)
echo "checked out: $total | uninitialised: $missing | conflicted: $conflict"
if [ "$missing" != "0" ]; then
  echo "--- uninitialised ---"
  git submodule status --recursive | grep '^-' | head -20
fi

log "done"
