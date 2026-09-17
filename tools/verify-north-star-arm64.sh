#!/usr/bin/env bash
set -euo pipefail

tools_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd "$tools_dir/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
mode=${1:-quick}

require_file() {
	[[ -x $1 ]] || {
		echo "Required executable is missing: $1" >&2
		exit 2
	}
}

run() {
	printf '\n==> %s\n' "$1"
	shift
	"$@"
}

case "$mode" in
	quick)
		install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage18}
		require_file "$install_root/bin/darlingserver"
		run "installed command-line and Foundation ladder" \
			env DARLING_ARM64_INSTALL_ROOT="$install_root" \
			"$tools_dir/verify-staged-darling-arm64.sh"
		;;
	x11)
		install_root=${DARLING_ARM64_INSTALL_ROOT:-$workspace_root/install-arm64-stage18}
		require_file "$install_root/bin/darlingserver"
		for verifier in \
			verify-x11-backend-darling-arm64.sh \
			verify-hello-window-darling-arm64.sh \
			verify-controls-darling-arm64.sh \
			verify-text-view-darling-arm64.sh \
			verify-text-edit-darling-arm64.sh \
			verify-pty-harness-darling-arm64.sh \
			verify-mini-term-darling-arm64.sh
		do
			run "$verifier" env DARLING_ARM64_INSTALL_ROOT="$install_root" \
				"$tools_dir/$verifier"
		done
		;;
	iterm2)
		run "official iTerm2 artifact" "$tools_dir/verify-iterm2-artifact-arm64.sh"
		run "independent iTerm2 tabs" "$tools_dir/verify-iterm2-silver-tabs-arm64.sh"
		run "iTerm2 tab close lifecycle" "$tools_dir/verify-iterm2-silver-tab-close-arm64.sh"
		run "independent iTerm2 splits" "$tools_dir/verify-iterm2-silver-splits-arm64.sh"
		;;
	*)
		echo "Usage: $0 {quick|x11|iterm2}" >&2
		exit 2
		;;
esac
