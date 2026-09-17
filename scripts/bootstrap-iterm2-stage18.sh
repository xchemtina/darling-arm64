#!/usr/bin/env bash
# One command from a staged Stage 0-17 runtime to a launchable iTerm2 Stage 18 prefix.
#
# Written against issue 2 ("Provide a reproducible one-command ARM64 developer
# bootstrap"). It does NOT claim that issue complete -- see HONEST SCOPE below.
#
# WHY IT EXISTS
# -------------
# `bootstrap-stable.sh` covers Stage 0-17 and ends by saying so:
#     "The separate Stage 18 iTerm2 asset/bootstrap path is not automated yet."
# Both prepare-* scripts refuse to create the roots they populate, and
# `cmake --install --component stage18` has no caller anywhere in the tree. So the
# step between "Stage 0-17 runtime" and "iTerm2 can be launched" was manual and
# undocumented. This is that step.
#
# HONEST SCOPE -- what this does and does not deliver against issue 2
# -------------------------------------------------------------------
#   [x] prerequisite check with actionable errors
#   [x] no host package installation, no kernel changes
#   [x] resumable, with a bounded disk check before the expensive phases
#   [x] pinned artifact manifest (iTerm2 archive SHA-256 verified by the existing gate)
#   [x] creates a disposable prefix and launches the official unmodified iTerm2
#   [ ] "run a short iTerm2 terminal check" -- NOT DELIVERED. iTerm2 launches and
#       reaches its run loop, but its X11 window does not persist, so no terminal is
#       reachable yet (FINDINGS.md F73). This script reports how far the launch got
#       rather than pretending otherwise.
#   [ ] "reproduced from a clean host" -- NOT DONE here. Timings below are from a
#       warm workspace; the cold number is unmeasured and is not claimed.
#
# The shared cache cannot be fetched automatically: it is Apple's, and it comes from
# the machine you are entitled to take it from. If it is missing this script says
# exactly how to get one and stops, rather than failing three phases later.
#
# DELETING A USED PREFIX NEEDS ROOT. The staging and probe phases run in docker and
# write root-owned files into the prefix through the bind mount, so a plain
# `rm -rf $DARLING_STAGE18_ROOT` fails part-way with "Permission denied" -- and a
# half-deleted prefix looks reusable to this script's resume check while being
# corrupt. Remove prefixes with sudo, and never re-run against a partially deleted
# one.
set -uo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
tools=$source_root/tools

stage18_root=${DARLING_STAGE18_ROOT:-$workspace_root/install-arm64-stage18}
stage18_build=${DARLING_STAGE18_BUILD_ROOT:-$workspace_root/build-arm64-stage18}
seed_root=${DARLING_STAGE18_SEED_ROOT:-$workspace_root/install-arm64-stage10}
seed_build=${DARLING_STAGE18_SEED_BUILD:-$workspace_root/build-arm64-gui}
builder_image=${DARLING_ARM64_BUILDER_IMAGE:-darling-arm64-dev:24.04}
gui_image=${DARLING_GUI_TEST_IMAGE:-darling-arm64-gui-test:latest}
cache_root=${ITERM2_SHARED_CACHE_ROOT:-}

start_all=$(date +%s)
phase_start=0
say()   { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }
begin() { phase_start=$(date +%s); say "── $* ──"; }
done_() { say "   done in $(( $(date +%s) - phase_start ))s"; }
die()   { printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

# ── 1. prerequisites, with errors a newcomer can act on ──────────────────────
begin "prerequisites"

[[ $(uname -m) == aarch64 ]] || die "Native aarch64 Linux required; this host is $(uname -m).
Darling is a translation layer, not an emulator: arm64 Mach-O needs an arm64 host."

command -v docker >/dev/null || die "docker not found. Install Docker and ensure your
user can run it without sudo, then re-run."
docker info >/dev/null 2>&1 || die "docker is installed but not usable by this user.
Try: sudo usermod -aG docker \$USER   (then log out and back in)"

for img in "$builder_image" "$gui_image"; do
	docker image inspect "$img" >/dev/null 2>&1 || die "missing container image: $img
Build the builder from darling-getting-started:
    docker build --platform linux/arm64 -t darling-arm64-dev:24.04 -f Dockerfile .
and tag a GUI-capable image as $gui_image (it needs Xvfb, openbox, xdotool,
x11-utils, xrdb, and a CJK-capable font -- see FINDINGS.md F56)."
done

[[ -d $seed_root/root ]] || die "no Stage 0-17 runtime to seed from at: $seed_root
Run darling-getting-started/scripts/bootstrap-stable.sh first, or set
DARLING_STAGE18_SEED_ROOT to an existing staged runtime."
[[ -d $seed_build ]] || die "no seed build tree at: $seed_build
Set DARLING_STAGE18_SEED_BUILD to the build directory used for that runtime.
Seeding from it is what makes this take minutes instead of hours."

archive=$workspace_root/downloads/iterm2/3.6.11/iTerm2-3_6_11.zip
[[ -f $archive ]] || die "official iTerm2 archive not found at:
  $archive
Download iTerm2 3.6.11 and place it there. Required SHA-256:
  36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7"

command -v unzip >/dev/null || die "unzip not found; the artifact gate needs it."

# disk: Stage 18 build tree plus install root, with headroom
free_mb=$(df -Pm "$workspace_root" | awk 'NR==2 {print $4}')
(( free_mb >= 12000 )) || die "only ${free_mb} MB free below $workspace_root; allow ~12 GB."
say "   aarch64, docker, images, seed runtime, archive, ${free_mb} MB free"
done_

# ── 2. shared cache -- cannot be automated, so fail early and explain ────────
begin "shared cache"
if [[ -z $cache_root ]]; then
	for guess in "$workspace_root"/downloads/macos/*/dyld-stage18; do
		[[ -e $guess/dyld_shared_cache_arm64 ]] && { cache_root=$guess; break; }
	done
fi
if [[ -z $cache_root || ! -e $cache_root/dyld_shared_cache_arm64 ]]; then
	cat >&2 <<'EOF'

No dyld shared cache staged, and one cannot be downloaded: it is Apple's, and must
come from a machine you are entitled to take it from.

Six of the seven iTerm2 gates require it (FINDINGS.md F69). Any sufficiently recent
Apple Silicon Mac already has a usable one -- it does NOT have to be the macOS 26.5
restore image the gates pin (F74; verified working with 26.6).

On the Mac:
  D=/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld
  tar cf - -C "$D" dyld_shared_cache_arm64e\* | ssh <this-host> \
    "mkdir -p /tmp/dyld-in && tar xf - -C /tmp/dyld-in"

Then here:
  tools/prepare-macos-shared-cache.sh --from /tmp/dyld-in --version 26.6

That script also creates the arm64 aliases dyld needs; without the full set you get
"shared cache file open() failed", which looks like an incompatible cache and is not.
EOF
	die "shared cache missing (see above)"
fi
ITERM2_SHARED_CACHE_ROOT=$cache_root "$tools/prepare-macos-shared-cache.sh" --check-only \
	|| die "the staged cache at $cache_root is not usable; see messages above."
done_

# ── 3. Stage 18 roots, seeded from the known-good runtime ────────────────────
begin "Stage 18 roots"
if [[ -d $stage18_root/root && -x $stage18_root/root/usr/lib/dyld ]]; then
	say "   install root already present, reusing"
else
	say "   seeding install root from $seed_root"
	cp -a "$seed_root" "$stage18_root" 2>/dev/null
	# a few CUPS backends are root-owned mode 0700; they are irrelevant to iTerm2 but
	# their absence is noisy, so copy what we can and carry on
	[[ -d $stage18_root/root ]] || die "failed to seed install root"
fi
if [[ -d $stage18_build ]]; then
	say "   build tree already present, reusing (this is what makes it fast)"
else
	say "   seeding build tree from $seed_build"
	cp -a "$seed_build" "$stage18_build" || die "failed to seed build tree"
fi
done_

# ── 4. configure + build + stage the Stage 18 delta ──────────────────────────
begin "Stage 18 build"
# CMAKE_BUILD_TYPE is deliberately passed EMPTY: the seed tree uses an empty build
# type, and setting Release adds -DNDEBUG which trips objc4's debug-ness guard
# (`error: mismatch in debug-ness macros`). See STATE.md trap 36.
docker run --rm --platform linux/arm64 \
	-v "$source_root:/work/source:ro" -v "$stage18_build:/work/build" \
	"$builder_image" bash -lc "cd /work/build && cmake -S /work/source -B /work/build -G Ninja \
		-DDARLING_ARM64_NORTH_STAR_STAGE18=ON -DCOMPONENTS=gui,jsc -DCOMPONENT_gui=ON \
		-DTARGET_arm64=ON -DTARGET_x86_64=OFF -DTARGET_i386=OFF -DCMAKE_BUILD_TYPE=" \
	>"$workspace_root/stage18-configure.log" 2>&1 \
	|| die "configure failed; first error:
$(grep -m3 -E 'CMake Error|error:' "$workspace_root/stage18-configure.log")"

# -j8, not -j12: JavaScriptCore translation units are memory-hungry and 24 GB across
# 12 jobs is marginal. CPU is not the binding constraint.
docker run --rm --platform linux/arm64 \
	-v "$source_root:/work/source:ro" -v "$stage18_build:/work/build" \
	"$builder_image" bash -lc "cd /work/build && ninja -j${JOBS:-8}" \
	>"$workspace_root/stage18-build.log" 2>&1
rc=$?      # no pipe: this really is ninja's status (STATE.md traps 10/30)
(( rc == 0 )) || die "build failed after $(( $(date +%s) - phase_start ))s; FIRST error:
$(grep -m5 -nE 'error:|FAILED:' "$workspace_root/stage18-build.log")
full log: $workspace_root/stage18-build.log"

# `stage18` and `Unspecified` matter: the stage18 component has no caller anywhere in
# the tree, and libDarlingAppKitBootstrap's install() rule names no COMPONENT at all,
# so every named-component install misses it.
# The merge is per-entry, not a single `cp -a src/. dst/`, because the install tree
# ships Darwin-style `etc -> private/etc` and `var -> private/var` while a seeded root
# already has a real `etc` directory. cp refuses ("cannot overwrite directory with
# non-directory") and aborts the whole copy. Replacing the real directory with a
# symlink would be a regression, so the symlink is skipped and the fact is reported.
docker run --rm --platform linux/arm64 \
	-v "$source_root:/work/source:ro" -v "$stage18_build:/work/build" -v "$stage18_root:/work/stage" \
	"$builder_image" bash -lc '
		set -u; rm -rf /tmp/s18
		for c in cli_gui_common core gui stage18 jsc Unspecified; do
			DESTDIR=/tmp/s18 cmake --install /work/build --component "$c" >>/tmp/install.log 2>&1 \
				|| echo "component $c: install returned non-zero"
		done
		# /usr/bin/login lives in component `cli`, which is NOT staged above -- and
		# iTerm2 default profile runs `login -fp root`, so without it every session
		# dies at exec with errno 2, iTerm2 closes the zero-session window ~1.4s
		# after mapping, and the failure is silent on stderr (FINDINGS.md F79).
		# Stage the one binary rather than all of cli: the runtime already ships
		# its libpam.2/libbsm.0 dependencies, and the full component would drag in
		# a hundred tools this runtime has been deliberately built without.
		DESTDIR=/tmp/cli-login cmake --install /work/build --component cli >>/tmp/install.log 2>&1 || true
		cp /tmp/cli-login/usr/local/libexec/darling/usr/bin/login /tmp/s18/usr/local/libexec/darling/usr/bin/login \
			|| echo "WARNING: could not stage /usr/bin/login; iTerm2 sessions will die at exec (F79)"
		src=/tmp/s18/usr/local/libexec/darling; dst=/work/stage/root
		[ -d "$src" ] || { echo "nothing staged at $src"; exit 1; }
		rc=0
		for e in "$src"/* ; do
			b=${e##*/}
			if [ -L "$e" ] && [ -d "$dst/$b" ] && [ ! -L "$dst/$b" ]; then
				echo "skip $b: symlink in install tree, real directory in seeded root"
			elif [ -d "$e" ] && [ ! -L "$e" ]; then
				mkdir -p "$dst/$b" && cp -a "$e/." "$dst/$b/" || rc=1
			else
				cp -a "$e" "$dst/" || rc=1
			fi
		done
		exit $rc
	' >"$workspace_root/stage18-install.log" 2>&1
rc=$?
# Trust the outcome, not the exit status: a partial copy can still return 0, and the
# only thing that matters is whether the Stage 18 payload actually landed.
missing=""
for f in JavaScriptCore ScreenCaptureKit; do
	[[ -f $stage18_root/root/System/Library/Frameworks/$f.framework/Versions/A/$f ]] || missing+=" $f"
done
[[ -f $stage18_root/root/usr/bin/login ]] || missing+=" usr/bin/login"
if [[ -n $missing ]]; then
	die "staging did not deliver:$missing
$(tail -20 "$workspace_root/stage18-install.log")"
fi
(( rc == 0 )) || say "   staging reported errors but the payload landed; see stage18-install.log"
build_secs=$(( $(date +%s) - phase_start ))
done_

# ── 5. verify the runtime before trusting anything built on it ───────────────
begin "runtime check"
DARLING_ARM64_INSTALL_ROOT=$stage18_root "$tools/verify-north-star-arm64.sh" quick \
	>"$workspace_root/stage18-ladder.log" 2>&1
rc=$?
(( rc == 0 )) || die "the Stage 18 runtime does not pass the capability ladder.
Nothing built on it can be trusted. See $workspace_root/stage18-ladder.log"
say "   capability ladder passed"
for f in JavaScriptCore ScreenCaptureKit; do
	p=$stage18_root/root/System/Library/Frameworks/$f.framework/Versions/A/$f
	[[ -f $p ]] && say "   $f $(stat -c %s "$p") bytes" || say "   $f ABSENT (unexpected)"
done
done_

# ── 6. official artifact: verify + extract ───────────────────────────────────
begin "iTerm2 artifact"
"$tools/verify-iterm2-artifact-arm64.sh" >"$workspace_root/stage18-artifact.log" 2>&1 \
	|| die "artifact gate failed; see $workspace_root/stage18-artifact.log"
bundle=$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app
if [[ ! -d $bundle ]]; then
	extracted=$workspace_root/artifacts/stage18-iterm2-artifact/fresh-extraction/iTerm.app
	[[ -d $extracted ]] || die "artifact gate passed but no extracted bundle found"
	mkdir -p "$(dirname "$bundle")" && cp -a "$extracted" "$bundle"
fi
say "   unmodified bundle at $bundle"
done_

# ── 7. launch the official binary and report how far it gets ─────────────────
begin "iTerm2 launch probe"
export DARLING_STAGE18_ROOT=$stage18_root DARLING_STAGE18_BUILD_ROOT=$stage18_build
export DARLING_GUI_TEST_IMAGE=$gui_image DARLING_ARM64_BUILDER_IMAGE=$builder_image
export ITERM2_SHARED_CACHE_ROOT=$cache_root
export ITERM2_PROBE_SHARED_CACHE=1 ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1
export ITERM2_PROBE_FULL_LAUNCHD=1 ITERM2_PROBE_APPKIT_BOOTSTRAP=1 ITERM2_PROBE_APPKIT_REOPEN=1
export ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 ITERM2_PROBE_DIRECT_PTY=1
export ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 ITERM2_PROBE_OPAQUE_TEXT=1
export ITERM2_PROBE_DISABLE_METAL=1 ITERM2_PROBE_APPLE_LSD=0 ITERM2_PROBE_APPLE_MDS=0
export ITERM2_PROBE_ARTIFACTS=$workspace_root/artifacts/stage18-bootstrap-probe
# The probe's own default is 10s, which is too short for anything useful to happen:
# the run ends before iTerm2 has written a line of its own log, and the empty log then
# reads as "zero events" when it actually means "no evidence captured". 45s is what the
# run behind FINDINGS.md F73 used.
export ITERM2_PROBE_WAIT_SECONDS=${ITERM2_PROBE_WAIT_SECONDS:-45}
"$tools/probe-iterm2-launch-arm64.sh" >"$workspace_root/stage18-probe.log" 2>&1
A=$ITERM2_PROBE_ARTIFACTS
status=$(cat "$A/status.txt" 2>/dev/null || echo unknown)

# Absence of a log is not a measurement. Say which of the two it is, every time.
applog=$A/iterm2-job.err
if [[ -s $applog ]]; then
	maps="X11 MapNotify events=$(grep -ac MapNotify "$applog")"
	exc=$(grep -am1 "Terminating app due to uncaught" "$applog")
else
	maps="NO APPLICATION LOG CAPTURED (iterm2-job.err is empty) -- this is absence of
                  evidence, not evidence of zero window-mapping events"
	exc=""
fi
done_

total=$(( $(date +%s) - start_all ))
cat <<EOF

────────────────────────────────────────────────────────────────────────
 Stage 18 bootstrap complete in $(( total / 60 ))m $(( total % 60 ))s
────────────────────────────────────────────────────────────────────────
 runtime          $stage18_root  (capability ladder: passed)
 shared cache     $cache_root
 iTerm2 launch    status=$status
                  $maps
 ${exc:+uncaught exception: $exc}
 artifacts        $A

 timing           total ${total}s, of which the build phase was ${build_secs}s
$( (( build_secs < 120 )) \
	&& echo " A build phase this short means an existing build tree was REUSED. Do not
 quote this total against issue 2's 30-minute target -- it is a resume, not a build." \
	|| echo " Issue 2's 30-minute target: $( (( total <= 1800 )) && echo "met at $(( total / 60 ))m from a seeded Stage 0-17 runtime" || echo "NOT met ($(( total / 60 ))m)" )" )
 Timing from a clean host -- no images, no seed runtime -- is NOT measured here and
 is NOT claimed. That is the number issue 2 actually asks for.

 NOT DELIVERED: the short terminal check. iTerm2 launches and reaches its run
 loop, but its X11 window does not persist, so no terminal is reachable yet.
 See FINDINGS.md F73. Do not read a successful run of this script as Bronze.
────────────────────────────────────────────────────────────────────────
EOF
