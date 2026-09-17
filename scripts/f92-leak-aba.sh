#!/usr/bin/env bash
# F92: full ABA validation of the two-hunk resize-leak patch (LEAK-LOCALIZATION.md).
#
#   A  baseline   f85 cycle on the reviewed tree            -> leak present
#   B  patched    apply 2 release hunks, rebuild, restage,
#                 f85 cycle                                  -> flat?
#      gates      ladder + text-view + tabs/tab-close/splits -> no regression?
#   A' reverted   revert, rebuild, restage, f85 cycle        -> leak returns?
#
# Only the full ABA earns "candidate fix" wording (plan item 9 / trap 9: control
# before crediting a patch). Everything serial; statuses direct; per-arm samples
# archived. The reviewed runtime ends restored (revert + rebuild + control gates).
set -u

W=$HOME/darling
S=$W/source
OUT=$W/f92-leak-aba
mkdir -p "$OUT"
R=$OUT/ABA-REPORT.md
: > "$R"
note() { printf '%s\n' "$*" >> "$R"; }
say()  { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

rebuild_and_restage() {
	docker run --rm --platform linux/arm64 \
		-v "$S:/work/source:ro" -v "$W/build-arm64-stage18:/work/build" \
		darling-arm64-dev:24.04 bash -lc "cd /work/build && ninja -j8" \
		> "$OUT/$1-build.log" 2>&1
	brc=$?
	[ $brc -eq 0 ] || return 1
	docker run --rm --platform linux/arm64 \
		-v "$S:/work/source:ro" -v "$W/build-arm64-stage18:/work/build" -v "$W/install-arm64-stage18:/work/stage" \
		darling-arm64-dev:24.04 bash -lc '
			set -u; rm -rf /tmp/g
			for c in cli_gui_common gui Unspecified; do
				DESTDIR=/tmp/g cmake --install /work/build --component "$c" >>/tmp/i.log 2>&1 || true
			done
			cp -a /tmp/g/usr/local/libexec/darling/System/Library/Frameworks/. \
			      /work/stage/root/System/Library/Frameworks/' \
		> "$OUT/$1-stage.log" 2>&1
}

run_cycle() {   # $1 = arm name
	rm -rf "$W/artifacts/f85-resize-leak"
	"$HOME/f85.sh" > "$OUT/$1-f85.log" 2>&1
	cp "$W/artifacts/f85-resize-leak/f85-samples.txt" "$OUT/$1-samples.txt" 2>/dev/null
	n=$(grep -c "^[0-9]" "$OUT/$1-samples.txt" 2>/dev/null || echo 0)
	note "- arm $1: $n samples captured"
}

note "# F92 ABA report — $(date)"

# ---- restore reviewed tree exactly -------------------------------------------
say "phase 0: restore + assert reviewed tree"
cd "$S"
git checkout -q north-star/arm64-verified-fixes
git submodule sync --recursive -q
git submodule update --init --recursive --force -q 2>/dev/null
# bash and liblzma carry COMMITTED arm64 build fixes (branch arm64-build-fixes)
# that the pins predate; --force resets them to broken pins, so restore the fix
# branches and exempt exactly these two from the pin assertion (trap 41).
git -C src/external/liblzma checkout -q arm64-build-fixes
git -C src/external/bash checkout -q arm64-build-fixes
mismatch=0
while read -r _ sha _ path; do
	case "$path" in src/external/bash|src/external/liblzma) continue;; esac
	actual=$(git -C "$path" rev-parse HEAD 2>/dev/null)
	[ "$sha" = "$actual" ] || { echo "MISMATCH $path"; mismatch=1; }
done < <(git ls-tree HEAD -r | awk '$2=="commit" {print $1, $3, 0, $4}')
note "- reviewed-tree assertion: $( [ $mismatch -eq 0 ] && echo PASS || echo FAIL )"
[ $mismatch -eq 0 ] || { note "ABORT: tree not reviewed-clean"; exit 1; }

# the merge session may have left build-arm64-stage18 configured but unbuilt for
# HEAD changes; one ninja pass re-syncs it to reviewed sources (it was never built
# against merged sources -- Phase F aborted pre-build; gap used its own dir)
say "phase 0b: sync build tree to reviewed sources"
rebuild_and_restage sync || { note "ABORT: sync build failed"; exit 1; }

# ---- A: baseline ---------------------------------------------------------------
say "arm A: baseline cycle"
note ""
note "## A — baseline (reviewed, unpatched)"
run_cycle A

# ---- B: patch ------------------------------------------------------------------
say "arm B: apply hunks, rebuild, cycle"
cd "$S/src/external/cocotron"
git checkout -qb f89-leak-fix 2>/dev/null || git checkout -q f89-leak-fix
python3 - <<'PYEOF'
import pathlib
p1 = pathlib.Path("AppKit/X11.backend/X11Window.m"); s1 = p1.read_text()
anchor1 = """        _context = [[O2Context_builtin_FT alloc] initWithSurface: surface
                                                         flipped: NO];"""
add1 = anchor1 + """
        // F89 candidate fix: -[O2BitmapContext initWithSurface:flipped:] retains
        // the surface (O2BitmapContext.m:39); without this release one full
        // window backing store is stranded on every context rebuild -- which is
        // every resize, because -resizeWithNewSize: returns NO (O2Context.m:203).
        [surface release];"""
assert s1.count(anchor1) == 1, "hunk1 anchor"
assert "[surface release];" not in s1, "hunk1 already applied"
p1.write_text(s1.replace(anchor1, add1, 1))

p2 = pathlib.Path("Onyx2D/O2Context_builtin.m"); s2 = p2.read_text()
anchor2 = """                shadow);
    }"""
add2 = """                shadow);
        [shadow release]; // F89: shadow surface was created above and never freed
    }"""
assert s2.count(anchor2) == 1, "hunk2 anchor"
p2.write_text(s2.replace(anchor2, add2, 1))
print("both hunks applied")
PYEOF
[ $? -eq 0 ] || { note "ABORT: hunks failed to apply"; exit 1; }
git commit -aqm "F89 candidate: release stranded backing-store + shadow surfaces"
cd "$S"
note ""
note "## B — patched (two release hunks)"
rebuild_and_restage B || { note "ABORT: patched build failed"; tail -3 "$OUT/B-build.log" >> "$R"; exit 1; }
run_cycle B

say "arm B gates"
export ITERM2_SHARED_CACHE_ROOT=$W/downloads/macos/26.6/dyld-stage18
DARLING_ARM64_INSTALL_ROOT=$W/install-arm64-stage18 tools/verify-north-star-arm64.sh quick > "$OUT/B-ladder.log" 2>&1
note "- patched ladder: rc=$?"
tools/verify-text-view-darling-arm64.sh > "$OUT/B-textview.log" 2>&1
note "- patched text-view: rc=$?"
for g in tabs tab-close splits; do
	tools/verify-iterm2-silver-$g-arm64.sh > "$OUT/B-$g.log" 2>&1
	note "- patched silver-$g: rc=$?"
done

# ---- A': revert ----------------------------------------------------------------
say "arm A-prime: revert, rebuild, cycle"
cd "$S/src/external/cocotron"
git checkout -q north-star/arm64-verified-fixes 2>/dev/null || git checkout -q 2fa0bef93
cd "$S"
note ""
note "## A' — reverted"
rebuild_and_restage Aprime || { note "ABORT: revert build failed"; exit 1; }
run_cycle Aprime
DARLING_ARM64_INSTALL_ROOT=$W/install-arm64-stage18 tools/verify-north-star-arm64.sh quick > "$OUT/Aprime-ladder.log" 2>&1
note "- restored ladder: rc=$?"
tools/verify-iterm2-silver-tabs-arm64.sh > "$OUT/Aprime-tabs.log" 2>&1
note "- restored silver-tabs control: rc=$?"

note ""
note "*(driver finished $(date))*"
echo "F92 ABA COMPLETE"