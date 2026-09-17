#!/usr/bin/env bash
# Stage an Apple dyld shared cache for the Stage 18 iTerm2 probes.
#
# WHY THIS EXISTS
# ---------------
# Six of the seven iTerm2 gates set ITERM2_PROBE_SHARED_CACHE=1 and fail closed
# without a cache (FINDINGS.md F69). The documented source is a retained
# UniversalMac_26.5_25F71_Restore.ipsw, which the project cannot redistribute -- so in
# practice nobody outside the original machine could run those gates.
#
# They do not need that specific image. **Any sufficiently recent Apple Silicon Mac
# already has a usable cache on disk** (F74, verified with macOS 26.6 / 25G72). This
# script stages one and handles the part that is not obvious.
#
# THE NON-OBVIOUS PART
# --------------------
# dyld derives subcache paths by appending suffixes to the MAIN cache path it is
# handed. Point it at `dyld_shared_cache_arm64` while the subcaches are still named
# `dyld_shared_cache_arm64e.01` and it fails with
#
#     dyld: dyld cache load error: shared cache file open() failed
#
# which reads like "this cache is incompatible" and is nothing of the sort. The whole
# set has to be aliased, not just the main file. That cost a debugging cycle and is
# the main reason this script exists rather than a paragraph of instructions.
#
# GETTING A CACHE OFF A MAC (run on the Mac, not here):
#
#   D=/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld
#   tar cf - -C "$D" dyld_shared_cache_arm64e\* | ssh <linux-host> \
#     "mkdir -p ~/darling/downloads/macos/<ver>/dyld-stage18 && \
#      tar xf - -C ~/darling/downloads/macos/<ver>/dyld-stage18"
#
# then run this script against that directory.
#
# LICENSING: the cache is Apple's. Use it locally, on a machine entitled to the OS it
# came from. It is never committed to this repository, exactly as corpus/bin is not.
set -uo pipefail

usage() {
	cat >&2 <<'USAGE'
usage: prepare-macos-shared-cache.sh --from <dir> [--version <ver>] [--check-only]

  --from <dir>      directory holding dyld_shared_cache_arm64e* copied from a Mac
  --version <ver>   macOS version label for the staged path (default: derived or "host")
  --check-only      validate an already-staged cache and exit

Stages into $workspace/downloads/macos/<ver>/dyld-stage18 and creates the arm64
aliases the probes require. Prints the ITERM2_SHARED_CACHE_ROOT to export.
USAGE
	exit 2
}

src=""; version=""; check_only=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--from)      src=${2:-}; shift 2 ;;
		--version)   version=${2:-}; shift 2 ;;
		--check-only) check_only=1; shift ;;
		-h|--help)   usage ;;
		*) echo "unknown argument: $1" >&2; usage ;;
	esac
done

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)

[[ $(uname -m) == aarch64 ]] || {
	echo "This stages a cache for native aarch64 Darling; host is $(uname -m)." >&2
	exit 2
}

# ---- validation helper ------------------------------------------------------
# A cache is usable when the main file exists, every subcache dyld will derive is
# present, and the arm64 aliases resolve. Report each failure specifically: a generic
# "cache invalid" is what made this hard to diagnose in the first place.
validate() {
	# NB: separate declarations. `local a=$1 b="$a/x"` evaluates the right-hand
	# sides against the OUTER scope, so $a is unbound there under `set -u`. That
	# bug survived the --check-only path only because a global `root` masked it.
	local root=$1
	local rc=0
	local main="$root/dyld_shared_cache_arm64"

	if [[ ! -e $main ]]; then
		echo "  MISSING  dyld_shared_cache_arm64 (the probes check for this exact name)" >&2
		return 1
	fi
	[[ -r $main ]] || { echo "  UNREADABLE  $main" >&2; rc=1; }

	local real subs=0 broken=0 f alias
	real=$(readlink -f "$main" 2>/dev/null || echo "$main")
	echo "  main:     $(basename "$real")  $(stat -c %s "$real" 2>/dev/null) bytes"

	# every arm64e sibling must have an arm64 alias that resolves
	for f in "$root"/dyld_shared_cache_arm64e*; do
		[[ -e $f ]] || continue
		subs=$((subs + 1))
		alias="$root/dyld_shared_cache_arm64${f##*dyld_shared_cache_arm64e}"
		if [[ ! -e $alias ]]; then
			echo "  MISSING ALIAS  $(basename "$alias")  -- dyld derives this name" >&2
			broken=$((broken + 1))
		fi
	done
	echo "  members:  $subs arm64e files, $((subs - broken)) aliased"
	(( broken == 0 )) || { echo "  $broken alias(es) missing" >&2; rc=1; }
	(( subs >= 2 )) || { echo "  only $subs file(s) -- a real cache has a main file plus subcaches" >&2; rc=1; }
	return $rc
}

# ---- check-only -------------------------------------------------------------
if (( check_only )); then
	root=${ITERM2_SHARED_CACHE_ROOT:-}
	[[ -n $root ]] || { echo "--check-only needs ITERM2_SHARED_CACHE_ROOT set." >&2; exit 2; }
	echo "checking $root"
	validate "$root" && { echo "cache OK"; exit 0; } || { echo "cache NOT usable" >&2; exit 1; }
fi

[[ -n $src ]] || usage
[[ -d $src ]] || { echo "source directory does not exist: $src" >&2; exit 2; }

shopt -s nullglob
members=("$src"/dyld_shared_cache_arm64e*)
shopt -u nullglob
if (( ${#members[@]} == 0 )); then
	cat >&2 <<EOF
No dyld_shared_cache_arm64e* files in: $src

On an Apple Silicon Mac they live at:
  /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/
Copy the dyld_shared_cache_arm64e* set (main file, numbered subcaches, .atlas, .map)
-- NOT the aot_shared_cache files, which are Rosetta and are not needed.
EOF
	exit 2
fi

[[ -n $version ]] || version=host
dest="$workspace_root/downloads/macos/$version/dyld-stage18"
case "$dest" in "$workspace_root"/*) ;; *) echo "destination must stay below the workspace." >&2; exit 2;; esac

# ---- bounded disk check -----------------------------------------------------
need_kb=$(du -sk "$src" 2>/dev/null | cut -f1)
free_kb=$(df -Pk "$workspace_root" | awk 'NR==2 {print $4}')
if (( free_kb < need_kb * 2 )); then
	echo "Not enough space: need ~$((need_kb / 1024)) MB (x2 headroom), have $((free_kb / 1024)) MB free." >&2
	exit 2
fi

mkdir -p "$dest" || exit 2

echo "staging $(( need_kb / 1024 )) MB from $src"
copied=0
for f in "${members[@]}"; do
	b=$(basename "$f")
	# resumable: skip members already staged at the same size
	if [[ -f "$dest/$b" && $(stat -c %s "$dest/$b") == $(stat -c %s "$f") ]]; then
		continue
	fi
	cp -f "$f" "$dest/$b" || { echo "copy failed: $b" >&2; exit 1; }
	copied=$((copied + 1))
done
echo "  copied $copied member(s), $(( ${#members[@]} - copied )) already present"

# ---- the aliases dyld actually needs ----------------------------------------
# Symlinks, not copies: dyld only needs the names to resolve, and duplicating several
# GB to satisfy a naming convention would be silly.
made=0
for f in "$dest"/dyld_shared_cache_arm64e*; do
	b=$(basename "$f")
	alias="dyld_shared_cache_arm64${b#dyld_shared_cache_arm64e}"
	[[ $alias == "$b" ]] && continue
	ln -sfn "$b" "$dest/$alias" && made=$((made + 1))
done
echo "  created $made arm64 alias(es)"

echo "validating:"
if validate "$dest"; then
	cat <<EOF

cache staged and usable. Export this before running any iTerm2 gate or probe:

  export ITERM2_SHARED_CACHE_ROOT=$dest

Note: this is Apple's cache, used locally. It is not committed to the repository.
EOF
	exit 0
fi
echo "staged but validation failed -- see messages above" >&2
exit 1
