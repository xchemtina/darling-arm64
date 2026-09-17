#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
install_root=${DARLING_STAGE18_ROOT:-$workspace_root/install-arm64-stage18}
bundle_root=${APP_PROBE_BUNDLE:-${ITERM2_BUNDLE:-$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app}}
bundle_name=${APP_PROBE_BUNDLE_NAME:-iTerm.app}
executable_name=${APP_PROBE_EXECUTABLE_NAME:-iTerm2}
force_flat_namespace=${APP_PROBE_FORCE_FLAT_NAMESPACE:-1}
flat_fallback_two_level=${APP_PROBE_FLAT_FALLBACK_TWO_LEVEL:-0}
artifact_root=${ITERM2_PROBE_ARTIFACTS:-$workspace_root/artifacts/stage18-iterm2-launch-probe}
image=${DARLING_GUI_TEST_IMAGE:-darling-arm64-gui-test:latest}
wait_seconds=${ITERM2_PROBE_WAIT_SECONDS:-10}
shared_cache=${ITERM2_PROBE_SHARED_CACHE:-0}
prefer_disk_frameworks=${ITERM2_PROBE_PREFER_DISK_FRAMEWORKS:-0}
trace=${ITERM2_PROBE_TRACE:-0}
dserver_gdb=${ITERM2_PROBE_DSERVER_GDB:-0}
lifecycle_debug=${ITERM2_PROBE_LIFECYCLE_DEBUG:-0}
debug=${ITERM2_PROBE_DEBUG:-0}
debug_sample=${ITERM2_PROBE_DEBUG_SAMPLE:-0}
debug_delay=${ITERM2_PROBE_DEBUG_DELAY:-0}
debug_break_address=${ITERM2_PROBE_DEBUG_BREAK_ADDRESS:-}
debug_break_symbol=${ITERM2_PROBE_DEBUG_BREAK_SYMBOL:-}
debug_syscall=${ITERM2_PROBE_DEBUG_SYSCALL:-}
debug_signal=${ITERM2_PROBE_DEBUG_SIGNAL:-}
debug_break_condition=${ITERM2_PROBE_DEBUG_BREAK_CONDITION:-1}
debug_call_address=${ITERM2_PROBE_DEBUG_CALL_ADDRESS:-}
debug_follow_break_address=${ITERM2_PROBE_DEBUG_FOLLOW_BREAK_ADDRESS:-}
debug_watch_address=${ITERM2_PROBE_DEBUG_WATCH_ADDRESS:-}
debug_process=${ITERM2_PROBE_DEBUG_PROCESS:-}
debug_process_match_index=${ITERM2_PROBE_DEBUG_PROCESS_MATCH_INDEX:-1}
disable_objc_preopt=${ITERM2_PROBE_DISABLE_OBJC_PREOPT:-0}
disable_preattached_categories=${ITERM2_PROBE_DISABLE_PREATTACHED_CATEGORIES:-0}
dyld_print_bindings=${ITERM2_PROBE_DYLD_PRINT_BINDINGS:-0}
dyld_print_initializers=${ITERM2_PROBE_DYLD_PRINT_INITIALIZERS:-0}
dyld_print_segments=${ITERM2_PROBE_DYLD_PRINT_SEGMENTS:-0}
mldr_debug=${ITERM2_PROBE_MLDR_DEBUG:-0}
launch_services=${ITERM2_PROBE_LAUNCH_SERVICES:-0}
launch_services_debug=${ITERM2_PROBE_LAUNCH_SERVICES_DEBUG:-1}
full_launchd=${ITERM2_PROBE_FULL_LAUNCHD:-0}
activate_delay=${ITERM2_PROBE_ACTIVATE_DELAY:-0}
register_delay=${ITERM2_PROBE_REGISTER_DELAY:-}
register_dump_delay=${ITERM2_PROBE_REGISTER_DUMP_DELAY:-}
register_keepalive=${ITERM2_PROBE_REGISTER_KEEPALIVE:-0}
register_path=${ITERM2_PROBE_REGISTER_PATH:-/Applications}
activate_shared_cache=${ITERM2_PROBE_ACTIVATE_SHARED_CACHE:-0}
activate_app_path=${ITERM2_PROBE_ACTIVATE_APP_PATH:-0}
ae_debug=${ITERM2_PROBE_AE_DEBUG:-0}
appkit_bootstrap=${ITERM2_PROBE_APPKIT_BOOTSTRAP:-0}
appkit_reopen=${ITERM2_PROBE_APPKIT_REOPEN:-0}
apple_lsd=${ITERM2_PROBE_APPLE_LSD:-0}
apple_mds=${ITERM2_PROBE_APPLE_MDS:-0}
cfprefsd=${ITERM2_PROBE_CFPREFSD:-0}
cfprefsd_debug=${ITERM2_PROBE_CFPREFSD_DEBUG:-0}
apple_cfprefsd=${ITERM2_PROBE_APPLE_CFPREFSD:-0}
language_data=${ITERM2_PROBE_LANGUAGE_DATA:-0}
shallow_tokenizer=${ITERM2_PROBE_SHALLOW_TOKENIZER:-0}
mdutil_delay=${ITERM2_PROBE_MDUTIL_DELAY:-0}
start_app=${ITERM2_PROBE_START_APP:-1}
disable_locale_discovery=${ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY:-0}
direct_pty=${ITERM2_PROBE_DIRECT_PTY:-0}
tab_workflow=${ITERM2_PROBE_TAB_WORKFLOW:-0}
tab_close_workflow=${ITERM2_PROBE_TAB_CLOSE_WORKFLOW:-0}
tab_close_debug_sample=${ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE:-0}
split_workflow=${ITERM2_PROBE_SPLIT_WORKFLOW:-0}
basic_key_input=${ITERM2_PROBE_BASIC_KEY_INPUT:-0}
stable_keyboard_source=${ITERM2_PROBE_STABLE_KEYBOARD_SOURCE:-0}
opaque_text=${ITERM2_PROBE_OPAQUE_TEXT:-0}
disable_metal=${ITERM2_PROBE_DISABLE_METAL:-0}
memory_limit=${ITERM2_PROBE_MEMORY_LIMIT:-32g}
nofile_limit=${ITERM2_PROBE_NOFILE_LIMIT:-1024}
type_text=${ITERM2_PROBE_TYPE_TEXT:-}
type_return=${ITERM2_PROBE_TYPE_RETURN:-1}
resize_width=${ITERM2_PROBE_RESIZE_WIDTH:-0}
resize_height=${ITERM2_PROBE_RESIZE_HEIGHT:-0}
resize_delay=${ITERM2_PROBE_RESIZE_DELAY:-1}
scroll_up_ticks=${ITERM2_PROBE_SCROLL_UP_TICKS:-0}
scroll_up_delay=${ITERM2_PROBE_SCROLL_UP_DELAY:-2}
scroll_up_tick_delay=${ITERM2_PROBE_SCROLL_UP_TICK_DELAY:-0.1}
selection_start_x=${ITERM2_PROBE_SELECTION_START_X:-0}
selection_start_y=${ITERM2_PROBE_SELECTION_START_Y:-0}
selection_end_x=${ITERM2_PROBE_SELECTION_END_X:-0}
selection_end_y=${ITERM2_PROBE_SELECTION_END_Y:-0}
selection_delay=${ITERM2_PROBE_SELECTION_DELAY:-2}
selection_paste_back=${ITERM2_PROBE_SELECTION_PASTE_BACK:-0}
quit_dialog=${ITERM2_PROBE_QUIT_DIALOG:-0}
quit_confirm=${ITERM2_PROBE_QUIT_CONFIRM:-0}
shutdown_prefix=${ITERM2_PROBE_SHUTDOWN_PREFIX:-0}
settings_persistence=${ITERM2_PROBE_SETTINGS_PERSISTENCE:-0}
soak_seconds=${ITERM2_PROBE_SOAK_SECONDS:-0}
soak_interval=${ITERM2_PROBE_SOAK_INTERVAL:-10}
cache_root=${ITERM2_SHARED_CACHE_ROOT:-$workspace_root/downloads/macos/26.5/dyld-stage18}
apple_lsd_root=${ITERM2_APPLE_LSD_ROOT:-$workspace_root/downloads/macos/26.5/apple-lsd/25F71__MacOS/root}
apple_cfprefsd_root=${ITERM2_APPLE_CFPREFSD_ROOT:-$workspace_root/downloads/macos/26.5/apple-cfprefsd/25F71__MacOS/root}
apple_dirhelper_root=${ITERM2_APPLE_DIRHELPER_ROOT:-$workspace_root/downloads/macos/26.5/apple-dirhelper/25F71__MacOS/root}
apple_lsregister_root=${ITERM2_APPLE_LSREGISTER_ROOT:-$workspace_root/downloads/macos/26.5/apple-lsregister/25F71__MacOS/root}
apple_metadata_root=${ITERM2_APPLE_METADATA_ROOT:-$workspace_root/downloads/macos/26.5/apple-metadata/25F71__MacOS/root}
apple_metadata_tools_root=${ITERM2_APPLE_METADATA_TOOLS_ROOT:-$workspace_root/downloads/macos/26.5/apple-metadata-tools/25F71__MacOS/root}
language_data_root=${ITERM2_LANGUAGE_DATA_ROOT:-$workspace_root/downloads/macos/26.5/langid-extract/25F71__MacOS/root}
icu_data_root=${ITERM2_ICU_DATA_ROOT:-$workspace_root/downloads/macos/26.5/icu-extract/25F71__MacOS/root}
container=darling-arm64-iterm2-launch-probe

[[ $(uname -m) == aarch64 ]] || { echo "This probe requires native aarch64 Linux." >&2; exit 2; }
[[ $bundle_name =~ ^[A-Za-z0-9._+-]+[.]app$ && $executable_name =~ ^[A-Za-z0-9._+-]+$ ]] || {
	echo "APP_PROBE_BUNDLE_NAME and APP_PROBE_EXECUTABLE_NAME must be simple names." >&2
	exit 2
}
[[ $force_flat_namespace == 0 || $force_flat_namespace == 1 ]] || {
	echo "APP_PROBE_FORCE_FLAT_NAMESPACE must be 0 or 1." >&2
	exit 2
}
[[ $flat_fallback_two_level == 0 || $flat_fallback_two_level == 1 ]] || {
	echo "APP_PROBE_FLAT_FALLBACK_TWO_LEVEL must be 0 or 1." >&2
	exit 2
}
[[ $nofile_limit =~ ^[0-9]+$ ]] || { echo "ITERM2_PROBE_NOFILE_LIMIT must be a non-negative integer." >&2; exit 2; }
[[ $soak_seconds =~ ^[0-9]+$ && $soak_interval =~ ^[1-9][0-9]*$ ]] || {
	echo "ITERM2_PROBE_SOAK_SECONDS must be non-negative and SOAK_INTERVAL must be positive." >&2
	exit 2
}
[[ $type_return == 0 || $type_return == 1 ]] || { echo "ITERM2_PROBE_TYPE_RETURN must be 0 or 1." >&2; exit 2; }
[[ $resize_width =~ ^[0-9]+$ && $resize_height =~ ^[0-9]+$ ]] || {
	echo "ITERM2_PROBE_RESIZE_WIDTH and HEIGHT must be non-negative integers." >&2
	exit 2
}
[[ $resize_delay =~ ^[0-9]+([.][0-9]+)?$ ]] || {
	echo "ITERM2_PROBE_RESIZE_DELAY must be a non-negative number." >&2
	exit 2
}
[[ $scroll_up_ticks =~ ^[0-9]+$ ]] || {
	echo "ITERM2_PROBE_SCROLL_UP_TICKS must be a non-negative integer." >&2
	exit 2
}
[[ $scroll_up_delay =~ ^[0-9]+([.][0-9]+)?$ ]] || {
	echo "ITERM2_PROBE_SCROLL_UP_DELAY must be a non-negative number." >&2
	exit 2
}
[[ $scroll_up_tick_delay =~ ^[0-9]+([.][0-9]+)?$ ]] || {
	echo "ITERM2_PROBE_SCROLL_UP_TICK_DELAY must be a non-negative number." >&2
	exit 2
}
for coordinate in "$selection_start_x" "$selection_start_y" \
	"$selection_end_x" "$selection_end_y"; do
	[[ $coordinate =~ ^[0-9]+$ ]] || {
		echo "ITERM2_PROBE_SELECTION coordinates must be non-negative integers." >&2
		exit 2
	}
done
[[ $selection_delay =~ ^[0-9]+([.][0-9]+)?$ ]] || {
	echo "ITERM2_PROBE_SELECTION_DELAY must be a non-negative number." >&2
	exit 2
}
[[ $selection_paste_back == 0 || $selection_paste_back == 1 ]] || {
	echo "ITERM2_PROBE_SELECTION_PASTE_BACK must be 0 or 1." >&2
	exit 2
}
[[ $quit_dialog == 0 || $quit_dialog == 1 ]] || {
	echo "ITERM2_PROBE_QUIT_DIALOG must be 0 or 1." >&2
	exit 2
}
[[ $quit_confirm == 0 || $quit_confirm == 1 ]] || {
	echo "ITERM2_PROBE_QUIT_CONFIRM must be 0 or 1." >&2
	exit 2
}
if (( quit_confirm == 1 && quit_dialog == 0 )); then
	echo "ITERM2_PROBE_QUIT_CONFIRM requires ITERM2_PROBE_QUIT_DIALOG=1." >&2
	exit 2
fi
[[ $shutdown_prefix == 0 || $shutdown_prefix == 1 ]] || {
	echo "ITERM2_PROBE_SHUTDOWN_PREFIX must be 0 or 1." >&2
	exit 2
}
if (( shutdown_prefix == 1 && quit_confirm == 0 )); then
	echo "ITERM2_PROBE_SHUTDOWN_PREFIX requires ITERM2_PROBE_QUIT_CONFIRM=1." >&2
	exit 2
fi
[[ $settings_persistence == 0 || $settings_persistence == 1 ]] || {
	echo "ITERM2_PROBE_SETTINGS_PERSISTENCE must be 0 or 1." >&2
	exit 2
}
if (( settings_persistence == 1 )) &&
	(( full_launchd != 1 || appkit_bootstrap != 1 )); then
	echo "Settings persistence requires full launchd and the AppKit bootstrap." >&2
	exit 2
fi
selection_enabled=0
if (( selection_start_x > 0 || selection_start_y > 0 ||
	selection_end_x > 0 || selection_end_y > 0 )); then
	if (( selection_start_x == 0 || selection_start_y == 0 ||
		selection_end_x == 0 || selection_end_y == 0 )); then
		echo "All ITERM2_PROBE_SELECTION coordinates must be positive when enabled." >&2
		exit 2
	fi
	selection_enabled=1
fi
if (( selection_paste_back == 1 && selection_enabled == 0 )); then
	echo "ITERM2_PROBE_SELECTION_PASTE_BACK requires selection coordinates." >&2
	exit 2
fi
if (( (resize_width == 0) != (resize_height == 0) )); then
	echo "ITERM2_PROBE_RESIZE_WIDTH and HEIGHT must both be zero or positive." >&2
	exit 2
fi
[[ $basic_key_input == 0 || $basic_key_input == 1 ]] || { echo "ITERM2_PROBE_BASIC_KEY_INPUT must be 0 or 1." >&2; exit 2; }
[[ $stable_keyboard_source == 0 || $stable_keyboard_source == 1 ]] || { echo "ITERM2_PROBE_STABLE_KEYBOARD_SOURCE must be 0 or 1." >&2; exit 2; }
[[ $tab_workflow == 0 || $tab_workflow == 1 ]] || { echo "ITERM2_PROBE_TAB_WORKFLOW must be 0 or 1." >&2; exit 2; }
[[ $tab_close_workflow == 0 || $tab_close_workflow == 1 ]] || { echo "ITERM2_PROBE_TAB_CLOSE_WORKFLOW must be 0 or 1." >&2; exit 2; }
(( tab_close_workflow == 0 || tab_workflow == 1 )) || { echo "ITERM2_PROBE_TAB_CLOSE_WORKFLOW requires ITERM2_PROBE_TAB_WORKFLOW=1." >&2; exit 2; }
[[ $tab_close_debug_sample == 0 || $tab_close_debug_sample == 1 ]] || { echo "ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE must be 0 or 1." >&2; exit 2; }
(( tab_close_debug_sample == 0 || tab_close_workflow == 1 )) || { echo "ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE requires ITERM2_PROBE_TAB_CLOSE_WORKFLOW=1." >&2; exit 2; }
[[ $split_workflow == 0 || $split_workflow == 1 ]] || { echo "ITERM2_PROBE_SPLIT_WORKFLOW must be 0 or 1." >&2; exit 2; }
(( split_workflow == 0 || tab_workflow == 0 )) || { echo "ITERM2_PROBE_SPLIT_WORKFLOW and ITERM2_PROBE_TAB_WORKFLOW are mutually exclusive." >&2; exit 2; }
[[ $opaque_text == 0 || $opaque_text == 1 ]] || { echo "ITERM2_PROBE_OPAQUE_TEXT must be 0 or 1." >&2; exit 2; }
[[ $disable_metal == 0 || $disable_metal == 1 ]] || { echo "ITERM2_PROBE_DISABLE_METAL must be 0 or 1." >&2; exit 2; }
[[ $language_data == 0 || $language_data == 1 ]] || { echo "ITERM2_PROBE_LANGUAGE_DATA must be 0 or 1." >&2; exit 2; }
[[ $shallow_tokenizer == 0 || $shallow_tokenizer == 1 ]] || { echo "ITERM2_PROBE_SHALLOW_TOKENIZER must be 0 or 1." >&2; exit 2; }
[[ $cfprefsd == 0 || $cfprefsd == 1 ]] || { echo "ITERM2_PROBE_CFPREFSD must be 0 or 1." >&2; exit 2; }
[[ $cfprefsd_debug == 0 || $cfprefsd_debug == 1 ]] || { echo "ITERM2_PROBE_CFPREFSD_DEBUG must be 0 or 1." >&2; exit 2; }
[[ $apple_cfprefsd == 0 || $apple_cfprefsd == 1 ]] || { echo "ITERM2_PROBE_APPLE_CFPREFSD must be 0 or 1." >&2; exit 2; }
(( cfprefsd == 0 || apple_cfprefsd == 0 )) || {
	echo "Darling and Apple cfprefsd probes are mutually exclusive." >&2
	exit 2
}
if (( ${#type_text} > 512 )) || [[ $type_text == *$'\n'* || $type_text == *$'\r'* ]]; then
	echo "ITERM2_PROBE_TYPE_TEXT must be one line of at most 512 bytes." >&2
	exit 2
fi
[[ -x $install_root/root/usr/lib/dyld ]] || { echo "Missing Stage 18 runtime." >&2; exit 2; }
[[ -x $bundle_root/Contents/MacOS/$executable_name ]] || { echo "Missing precompiled application bundle." >&2; exit 2; }
case "$install_root" in "$workspace_root"/*) ;; *) echo "Runtime must be below the workspace." >&2; exit 2;; esac
case "$bundle_root" in "$workspace_root"/*) ;; *) echo "Bundle must be below the workspace." >&2; exit 2;; esac
case "$artifact_root" in "$workspace_root"/*) ;; *) echo "Artifacts must be below the workspace." >&2; exit 2;; esac
if [[ $shared_cache == 1 ]]; then
	[[ -f $cache_root/dyld_shared_cache_arm64 ]] || { echo "Missing staged shared cache." >&2; exit 2; }
	case "$cache_root" in "$workspace_root"/*) ;; *) echo "Shared cache must be below the workspace." >&2; exit 2;; esac
fi
if [[ $language_data == 1 ]]; then
	[[ $shared_cache == 1 ]] || { echo "Apple language data requires the shared cache." >&2; exit 2; }
	[[ -f $language_data_root/usr/share/langid/langid.inv ]] || {
		echo "Missing extracted Apple language-identification data." >&2
		exit 2
	}
	[[ -f $icu_data_root/usr/share/icu/icudt78l.dat ]] || {
		echo "Missing extracted Apple ICU data." >&2
		exit 2
	}
	case "$language_data_root" in "$workspace_root"/*) ;; *) echo "Language data must stay below the workspace." >&2; exit 2;; esac
	case "$icu_data_root" in "$workspace_root"/*) ;; *) echo "ICU data must stay below the workspace." >&2; exit 2;; esac
fi
if [[ ( $disable_locale_discovery == 1 || $direct_pty == 1 || $opaque_text == 1 ) && $appkit_bootstrap != 1 ]]; then
	echo "iTerm2 preference overrides require the opt-in AppKit bootstrap." >&2
	exit 2
fi
if [[ $apple_lsd == 1 ]]; then
	[[ $shared_cache == 1 && $full_launchd == 1 ]] || { echo "Apple lsd requires the shared cache and full launchd." >&2; exit 2; }
	[[ -x $apple_lsd_root/usr/libexec/lsd && -f $apple_lsd_root/System/Library/LaunchDaemons/com.apple.lsd.plist ]] || {
		echo "Missing extracted Apple lsd runtime." >&2
		exit 2
	}
	[[ -x $apple_dirhelper_root/usr/libexec/dirhelper && -f $apple_dirhelper_root/System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist ]] || {
		echo "Missing extracted Apple dirhelper runtime." >&2
		exit 2
	}
	[[ -x $apple_lsregister_root/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister ]] || {
		echo "Missing extracted Apple lsregister runtime." >&2
		exit 2
	}
	if [[ $apple_mds == 1 ]]; then
		metadata_support=$apple_metadata_root/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support
		[[ -x $metadata_support/mds && -x $metadata_support/mds_stores && -x $metadata_support/mdsync &&
			-x $metadata_support/mdworker && -x $metadata_support/mdworker_shared &&
			-f ${metadata_support%/Support}/Resources/schema.plist &&
			-f $apple_metadata_root/System/Library/LaunchDaemons/com.apple.metadata.mds.plist &&
			-f $apple_metadata_root/System/Library/LaunchDaemons/com.apple.metadata.mds.index.plist &&
			-f $apple_metadata_root/System/Library/LaunchDaemons/com.apple.metadata.mds.scan.plist ]] || {
			echo "Missing extracted Apple metadata runtime." >&2
			exit 2
		}
		[[ -x $apple_metadata_tools_root/usr/bin/mdutil ]] || {
			echo "Missing extracted Apple metadata tools." >&2
			exit 2
		}
	fi
	case "$apple_lsd_root" in "$workspace_root"/*) ;; *) echo "Apple lsd runtime must stay below the workspace." >&2; exit 2;; esac
	case "$apple_dirhelper_root" in "$workspace_root"/*) ;; *) echo "Apple dirhelper runtime must stay below the workspace." >&2; exit 2;; esac
	case "$apple_lsregister_root" in "$workspace_root"/*) ;; *) echo "Apple lsregister runtime must stay below the workspace." >&2; exit 2;; esac
	case "$apple_metadata_root" in "$workspace_root"/*) ;; *) echo "Apple metadata runtime must stay below the workspace." >&2; exit 2;; esac
	case "$apple_metadata_tools_root" in "$workspace_root"/*) ;; *) echo "Apple metadata tools must stay below the workspace." >&2; exit 2;; esac
fi
if [[ $apple_cfprefsd == 1 ]]; then
	[[ $shared_cache == 1 && $full_launchd == 1 ]] || {
		echo "Apple cfprefsd requires the shared cache and full launchd." >&2
		exit 2
	}
	[[ -x $apple_cfprefsd_root/usr/sbin/cfprefsd &&
		-f $apple_cfprefsd_root/System/Library/LaunchDaemons/com.apple.cfprefsd.xpc.daemon.plist ]] || {
		echo "Missing extracted Apple cfprefsd runtime." >&2
		exit 2
	}
	case "$apple_cfprefsd_root" in "$workspace_root"/*) ;; *)
		echo "Apple cfprefsd runtime must stay below the workspace." >&2
		exit 2
	esac
fi
if [[ $cfprefsd == 1 ]]; then
	[[ $full_launchd == 1 ]] || { echo "Darling cfprefsd requires full launchd." >&2; exit 2; }
	[[ -x $install_root/root/usr/sbin/cfprefsd &&
		-f $install_root/root/System/Library/LaunchDaemons/com.apple.cfprefsd.xpc.daemon.plist ]] || {
		echo "Missing staged Darling cfprefsd runtime." >&2
		exit 2
	}
fi

mkdir -p "$artifact_root"
rm -f "$artifact_root"/{darlingserver,launchservicesd}.{out,err} "$artifact_root"/{status,windows,processes,gdb,input}.txt "$artifact_root"/screen.png "$artifact_root"/strace.*
rm -f "$artifact_root"/launchctl-bootstrap.{out,err}
rm -f "$artifact_root"/{launchservicesd-job,iterm2-job}.{out,err}
rm -f "$artifact_root"/iterm2-activate.{out,err}
rm -f "$artifact_root"/iterm2-{register,register-dump}.{out,err}
rm -f "$artifact_root"/apple-mdutil.{out,err}
rm -f "$artifact_root"/{cfprefsd,apple-cfprefsd}.{out,err}
rm -f "$artifact_root"/launchctl-shutdown.{out,err} "$artifact_root"/prefix-shutdown-request
rm -f "$artifact_root"/settings-persistence-*
rm -f "$artifact_root"/com.googlecode.iterm2.plist
rm -f "$artifact_root"/soak-*.{txt,png}
rm -f "$artifact_root"/silver-tab*.txt "$artifact_root"/silver-tabs.txt
rm -f "$artifact_root"/silver-{tab,tabs,pane,split,splits}*.png
rm -f "$artifact_root"/silver-{pane,split,splits}*.txt
rm -f "$artifact_root"/{server-start-ns,shell-ready}.txt
rm -f "$artifact_root"/mldr-[0-9]*.txt
rm -f "$artifact_root"/iterm2-{before-input,final}-{status,smaps-rollup}.txt
rm -f "$artifact_root"/{resize-input,scroll-up-input,scroll-pointer,selection-input}.txt
rm -f "$artifact_root"/selection-{clipboard,primary}.{txt,err}
rm -f "$artifact_root"/{selection-screen.png,selection-paste.txt}
if (( shutdown_prefix == 1 )); then
	mkfifo "$artifact_root/prefix-shutdown-request"
fi
if (( settings_persistence == 1 )); then
	mkfifo "$artifact_root/settings-persistence-relaunch-request"
fi
docker rm -f "$container" >/dev/null 2>&1 || true
docker_args=(
	--name "$container" --rm
	--cap-add SYS_ADMIN --cap-add SYS_PTRACE \
	--security-opt apparmor=unconfined --security-opt seccomp=unconfined \
	--pids-limit 512 --memory "$memory_limit" \
	-v "$install_root/root:/usr/local/libexec/darling:ro" \
	-v "$install_root/bin:/opt/darling/bin:ro" \
	-v "$bundle_root:/app-reference:ro" \
	-v "$artifact_root:/artifacts" \
	-e "APP_PROBE_BUNDLE_NAME=$bundle_name" \
	-e "APP_PROBE_EXECUTABLE_NAME=$executable_name" \
	-e "APP_PROBE_APPLICATION_NAME=${bundle_name%.app}" \
	-e "APP_PROBE_APPLICATION_PATH=/Applications/$bundle_name" \
	-e "APP_PROBE_EXECUTABLE_PATH=/Applications/$bundle_name/Contents/MacOS/$executable_name" \
	-e "APP_PROBE_FORCE_FLAT_NAMESPACE=$force_flat_namespace" \
	-e "APP_PROBE_FLAT_FALLBACK_TWO_LEVEL=$flat_fallback_two_level" \
	-e "ITERM2_PROBE_WAIT_SECONDS=$wait_seconds" \
	-e "ITERM2_PROBE_SHARED_CACHE=$shared_cache" \
	-e "ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=$prefer_disk_frameworks" \
	-e "ITERM2_PROBE_TRACE=$trace" \
	-e "ITERM2_PROBE_DSERVER_GDB=$dserver_gdb" \
	-e "ITERM2_PROBE_LIFECYCLE_DEBUG=$lifecycle_debug" \
	-e "ITERM2_PROBE_DEBUG=$debug" \
	-e "ITERM2_PROBE_DEBUG_SAMPLE=$debug_sample" \
	-e "ITERM2_PROBE_DEBUG_DELAY=$debug_delay" \
	-e "ITERM2_PROBE_DEBUG_BREAK_ADDRESS=$debug_break_address" \
	-e "ITERM2_PROBE_DEBUG_BREAK_SYMBOL=$debug_break_symbol" \
	-e "ITERM2_PROBE_DEBUG_SYSCALL=$debug_syscall" \
	-e "ITERM2_PROBE_DEBUG_SIGNAL=$debug_signal" \
	-e "ITERM2_PROBE_DEBUG_BREAK_CONDITION=$debug_break_condition" \
	-e "ITERM2_PROBE_DEBUG_CALL_ADDRESS=$debug_call_address" \
	-e "ITERM2_PROBE_DEBUG_FOLLOW_BREAK_ADDRESS=$debug_follow_break_address" \
	-e "ITERM2_PROBE_DEBUG_WATCH_ADDRESS=$debug_watch_address" \
	-e "ITERM2_PROBE_DEBUG_PROCESS=$debug_process" \
	-e "ITERM2_PROBE_DEBUG_PROCESS_MATCH_INDEX=$debug_process_match_index" \
	-e "ITERM2_PROBE_DISABLE_OBJC_PREOPT=$disable_objc_preopt" \
	-e "ITERM2_PROBE_DISABLE_PREATTACHED_CATEGORIES=$disable_preattached_categories"
	-e "ITERM2_PROBE_DYLD_PRINT_BINDINGS=$dyld_print_bindings"
	-e "ITERM2_PROBE_DYLD_PRINT_INITIALIZERS=$dyld_print_initializers"
	-e "ITERM2_PROBE_DYLD_PRINT_SEGMENTS=$dyld_print_segments"
	-e "ITERM2_PROBE_MLDR_DEBUG=$mldr_debug"
	-e "ITERM2_PROBE_LAUNCH_SERVICES=$launch_services"
	-e "ITERM2_PROBE_LAUNCH_SERVICES_DEBUG=$launch_services_debug"
	-e "ITERM2_PROBE_FULL_LAUNCHD=$full_launchd"
	-e "ITERM2_PROBE_ACTIVATE_DELAY=$activate_delay"
	-e "ITERM2_PROBE_REGISTER_DELAY=$register_delay"
	-e "ITERM2_PROBE_REGISTER_DUMP_DELAY=$register_dump_delay"
	-e "ITERM2_PROBE_REGISTER_KEEPALIVE=$register_keepalive"
	-e "ITERM2_PROBE_REGISTER_PATH=$register_path"
	-e "ITERM2_PROBE_ACTIVATE_SHARED_CACHE=$activate_shared_cache"
	-e "ITERM2_PROBE_ACTIVATE_APP_PATH=$activate_app_path"
	-e "ITERM2_PROBE_AE_DEBUG=$ae_debug"
	-e "ITERM2_PROBE_APPKIT_BOOTSTRAP=$appkit_bootstrap"
	-e "ITERM2_PROBE_APPKIT_REOPEN=$appkit_reopen"
	-e "ITERM2_PROBE_APPLE_LSD=$apple_lsd"
	-e "ITERM2_PROBE_APPLE_MDS=$apple_mds"
	-e "ITERM2_PROBE_CFPREFSD=$cfprefsd"
	-e "ITERM2_PROBE_CFPREFSD_DEBUG=$cfprefsd_debug"
	-e "ITERM2_PROBE_APPLE_CFPREFSD=$apple_cfprefsd"
	-e "ITERM2_PROBE_LANGUAGE_DATA=$language_data"
	-e "ITERM2_PROBE_SHALLOW_TOKENIZER=$shallow_tokenizer"
	-e "ITERM2_PROBE_MDUTIL_DELAY=$mdutil_delay"
	-e "ITERM2_PROBE_START_APP=$start_app"
	-e "ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=$disable_locale_discovery"
	-e "ITERM2_PROBE_DIRECT_PTY=$direct_pty"
	-e "ITERM2_PROBE_TAB_WORKFLOW=$tab_workflow"
	-e "ITERM2_PROBE_TAB_CLOSE_WORKFLOW=$tab_close_workflow"
	-e "ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE=$tab_close_debug_sample"
	-e "ITERM2_PROBE_SPLIT_WORKFLOW=$split_workflow"
	-e "ITERM2_PROBE_BASIC_KEY_INPUT=$basic_key_input"
	-e "ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=$stable_keyboard_source"
	-e "ITERM2_PROBE_OPAQUE_TEXT=$opaque_text"
	-e "ITERM2_PROBE_DISABLE_METAL=$disable_metal"
	-e "ITERM2_PROBE_TYPE_TEXT=$type_text"
	-e "ITERM2_PROBE_TYPE_RETURN=$type_return"
	-e "ITERM2_PROBE_RESIZE_WIDTH=$resize_width"
	-e "ITERM2_PROBE_RESIZE_HEIGHT=$resize_height"
	-e "ITERM2_PROBE_RESIZE_DELAY=$resize_delay"
	-e "ITERM2_PROBE_SCROLL_UP_TICKS=$scroll_up_ticks"
	-e "ITERM2_PROBE_SCROLL_UP_DELAY=$scroll_up_delay"
	-e "ITERM2_PROBE_SCROLL_UP_TICK_DELAY=$scroll_up_tick_delay"
	-e "ITERM2_PROBE_SELECTION_ENABLED=$selection_enabled"
	-e "ITERM2_PROBE_SELECTION_START_X=$selection_start_x"
	-e "ITERM2_PROBE_SELECTION_START_Y=$selection_start_y"
	-e "ITERM2_PROBE_SELECTION_END_X=$selection_end_x"
	-e "ITERM2_PROBE_SELECTION_END_Y=$selection_end_y"
	-e "ITERM2_PROBE_SELECTION_DELAY=$selection_delay"
	-e "ITERM2_PROBE_SELECTION_PASTE_BACK=$selection_paste_back"
	-e "ITERM2_PROBE_QUIT_DIALOG=$quit_dialog"
	-e "ITERM2_PROBE_QUIT_CONFIRM=$quit_confirm"
	-e "ITERM2_PROBE_SHUTDOWN_PREFIX=$shutdown_prefix"
	-e "ITERM2_PROBE_SETTINGS_PERSISTENCE=$settings_persistence"
	-e "ITERM2_PROBE_SOAK_SECONDS=$soak_seconds"
	-e "ITERM2_PROBE_SOAK_INTERVAL=$soak_interval"
)
if (( nofile_limit > 0 )); then
	docker_args+=(--ulimit "nofile=$nofile_limit:$nofile_limit")
fi
if [[ $shared_cache == 1 ]]; then
	docker_args+=(-v "$cache_root:/iterm-dyld-cache:ro")
fi
if [[ $language_data == 1 ]]; then
	docker_args+=(-v "$language_data_root/usr/share/langid:/apple-language-data:ro")
	docker_args+=(-v "$icu_data_root/usr/share/icu:/apple-icu-data:ro")
fi
if [[ $apple_lsd == 1 ]]; then
	docker_args+=(-v "$apple_lsd_root:/apple-lsd:ro")
	docker_args+=(-v "$apple_dirhelper_root:/apple-dirhelper:ro")
	docker_args+=(-v "$apple_lsregister_root:/apple-lsregister:ro")
	if [[ $apple_mds == 1 ]]; then
		docker_args+=(-v "$apple_metadata_root:/apple-metadata:ro")
		docker_args+=(-v "$apple_metadata_tools_root:/apple-metadata-tools:ro")
	fi
fi
if [[ $apple_cfprefsd == 1 ]]; then
	docker_args+=(-v "$apple_cfprefsd_root:/apple-cfprefsd:ro")
fi
docker run "${docker_args[@]}" "$image" bash -lc '
		set -euo pipefail
		export PATH=/opt/darling/bin:$PATH DISPLAY=:95 LANG=C.UTF-8 LC_ALL=C.UTF-8
		export DYLD_USE_CLOSURES=0 DARLING_ARM64_THREAD_BRIDGE=1
		export DARLING_XPC_SERVICE_DEBUG=1
		export DARLING_LAUNCHD_BOOTSTRAP_LOG=1
		export DARLING_LAUNCHCTL_DEBUG=1
		if [[ $ITERM2_PROBE_LIFECYCLE_DEBUG == 1 ]]; then
			export DARLING_LAUNCHD_SHUTDOWN_DEBUG=1
			export DSERVER_LOG_LEVEL=debug
		fi
		if [[ $ITERM2_PROBE_DYLD_PRINT_BINDINGS == 1 ]]; then
			export DYLD_PRINT_BINDINGS=1
		fi
		if [[ $ITERM2_PROBE_DYLD_PRINT_INITIALIZERS == 1 ]]; then
			export DYLD_PRINT_INITIALIZERS=1
		fi
		export DARLING_NOOVERLAYFS=1
		if [[ $ITERM2_PROBE_TRACE == 1 || $ITERM2_PROBE_DEBUG == 1 || $ITERM2_PROBE_DSERVER_GDB == 1 ||
			$ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE == 1 ||
			$ITERM2_PROBE_SELECTION_ENABLED == 1 || $ITERM2_PROBE_SOAK_SECONDS -gt 0 ||
			$ITERM2_PROBE_SETTINGS_PERSISTENCE == 1 ]]; then
			apt-get update -qq
			packages=()
			[[ $ITERM2_PROBE_TRACE == 1 ]] && packages+=(strace)
			[[ $ITERM2_PROBE_DEBUG == 1 || $ITERM2_PROBE_DSERVER_GDB == 1 ||
				$ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE == 1 ]] && packages+=(gdb)
			[[ $ITERM2_PROBE_SELECTION_ENABLED == 1 ]] && packages+=(xclip)
			[[ $ITERM2_PROBE_SOAK_SECONDS -gt 0 ]] && packages+=(xclip)
			[[ $ITERM2_PROBE_SETTINGS_PERSISTENCE == 1 ]] && packages+=(imagemagick)
			DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
		fi
		if [[ $ITERM2_PROBE_SHARED_CACHE == 1 && $ITERM2_PROBE_FULL_LAUNCHD != 1 ]]; then
			export DARLING_DYLD_SHARED_CACHE=1 DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE=1 DYLD_PRINT_SEGMENTS=1
			export CFStringDisableROM=1
			if [[ $ITERM2_PROBE_DISABLE_PREATTACHED_CATEGORIES == 1 ]]; then
				export OBJC_DISABLE_PREATTACHED_CATEGORIES=YES
			fi
		fi
		if [[ $ITERM2_PROBE_DISABLE_OBJC_PREOPT == 1 ]]; then
			export OBJC_DISABLE_PREOPTIMIZATION=YES OBJC_DISABLE_PREOPTIMIZED_CACHES=YES
		fi
		Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
		xvfb_pid=$!
		openbox_pid=
		server_pid=
		debugger_pid=
		cleanup() {
			cp /tmp/iterm.out /artifacts/darlingserver.out 2>/dev/null || true
			cp /tmp/iterm.err /artifacts/darlingserver.err 2>/dev/null || true
			cp "$prefix/tmp/launchservicesd.out" /artifacts/launchservicesd.out 2>/dev/null || true
			cp "$prefix/tmp/launchservicesd.err" /artifacts/launchservicesd.err 2>/dev/null || true
			cp "$prefix/tmp/launchctl-bootstrap.out" /artifacts/launchctl-bootstrap.out 2>/dev/null || true
			cp "$prefix/tmp/launchctl-bootstrap.err" /artifacts/launchctl-bootstrap.err 2>/dev/null || true
			cp "$prefix/private/tmp/launchctl-bootstrap.out" /artifacts/launchctl-bootstrap.out 2>/dev/null || true
			cp "$prefix/private/tmp/launchctl-bootstrap.err" /artifacts/launchctl-bootstrap.err 2>/dev/null || true
			cp "$prefix/private/var/log/com.apple.launchd/launchd-debug.system.log" \
				/artifacts/launchd-debug.log 2>/dev/null || true
			cp "$prefix/private/var/log/com.apple.launchd/launchd-shutdown.system.log" \
				/artifacts/launchd-shutdown.log 2>/dev/null || true
			cp "$prefix/private/var/log/dserver.log" /artifacts/dserver.log \
				2>/dev/null || true
			cp "$prefix/private/var/root/Library/Preferences/com.googlecode.iterm2.plist" \
				/artifacts/com.googlecode.iterm2.plist 2>/dev/null || true
			chmod 0644 /artifacts/com.googlecode.iterm2.plist 2>/dev/null || true
			find "$prefix/private/var/log" -type f -exec cp -t /artifacts {} + \
				2>/dev/null || true
			[[ -z $server_pid ]] || kill -KILL "$server_pid" 2>/dev/null || true
			[[ -z $debugger_pid ]] || kill -KILL "$debugger_pid" 2>/dev/null || true
			pkill -KILL -x mldr 2>/dev/null || true
			[[ -z $openbox_pid ]] || kill "$openbox_pid" 2>/dev/null || true
			kill "$xvfb_pid" 2>/dev/null || true
		}
		trap cleanup EXIT
		for attempt in {1..100}; do
			xdpyinfo >/dev/null 2>&1 && break
			sleep 0.05
		done
		xdpyinfo >/dev/null
		cp /etc/xdg/openbox/rc.xml /tmp/openbox-rc.xml
		python3 - /tmp/openbox-rc.xml <<-PY
				import sys
				import xml.etree.ElementTree as ET

				path = sys.argv[1]
				tree = ET.parse(path)
				root = tree.getroot()
				parents = {child: parent for parent in root.iter() for child in parent}
				[
				    parents[keybind].remove(keybind)
				    for keybind in list(root.iter())
				    if keybind.tag.endswith("keybind") and keybind.get("key") == "W-d"
				]
				tree.write(path, encoding="unicode", xml_declaration=True)
		PY
		openbox --config-file /tmp/openbox-rc.xml --sm-disable >/tmp/openbox.log 2>&1 &
		openbox_pid=$!

		prefix=/tmp/darling-stage18
		mkdir -p "$prefix/dev/pts" "$prefix/proc" "$prefix/sys" "$prefix/home" \
		"$prefix/private/var/db" "$prefix/private/var/folders" "$prefix/private/var/run" \
		"$prefix/private/var/tmp" "$prefix/private/var/log/com.apple.launchd" \
		"$prefix/private/tmp" "$prefix/tmp" "$prefix/artifacts" "$prefix/usr/bin" "$prefix/usr/sbin" \
			"$prefix/Applications/$APP_PROBE_BUNDLE_NAME" "$prefix/etc" "$prefix/private/var/root"
		ln -s private/var "$prefix/var"
		printf "%s\n" "root:*:0:0:System Administrator:/var/root:/bin/sh" >"$prefix/etc/passwd"
		printf "%s\n" "wheel:*:0:root" >"$prefix/etc/group"
		cp -a /dev/null /dev/urandom "$prefix/dev/"
		mount --bind /dev/pts "$prefix/dev/pts"
		mount --bind /artifacts "$prefix/artifacts"
		: >"$prefix/usr/bin/locale"
		mount --bind /usr/bin/locale "$prefix/usr/bin/locale"
		mount -o remount,bind,ro "$prefix/usr/bin/locale"
		ln -s pts/ptmx "$prefix/dev/ptmx"
		mount --bind /app-reference "$prefix$APP_PROBE_APPLICATION_PATH"
		mount -o remount,bind,ro "$prefix$APP_PROBE_APPLICATION_PATH"
		if [[ $ITERM2_PROBE_SHARED_CACHE == 1 ]]; then
			mkdir -p "$prefix/System/Library/dyld"
			mount --bind /iterm-dyld-cache "$prefix/System/Library/dyld"
			mount -o remount,bind,ro "$prefix/System/Library/dyld"
			mkdir -p "$prefix/System/Library/CoreServices"
			cat >"$prefix/System/Library/CoreServices/SystemVersion.plist" <<-'PLIST'
				<?xml version="1.0" encoding="UTF-8"?>
				<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
				<plist version="1.0">
				<dict>
					<key>ProductBuildVersion</key>
					<string>25F71</string>
					<key>ProductName</key>
					<string>macOS</string>
					<key>ProductUserVisibleVersion</key>
					<string>26.5</string>
					<key>ProductVersion</key>
					<string>26.5</string>
				</dict>
				</plist>
			PLIST
		fi
		if [[ $ITERM2_PROBE_LANGUAGE_DATA == 1 ]]; then
			mkdir -p "$prefix/usr/share/langid" "$prefix/usr/share/icu"
			mount --bind /apple-language-data "$prefix/usr/share/langid"
			mount -o remount,bind,ro "$prefix/usr/share/langid"
			mount --bind /apple-icu-data "$prefix/usr/share/icu"
			mount -o remount,bind,ro "$prefix/usr/share/icu"
		fi

	if [[ $ITERM2_PROBE_FULL_LAUNCHD == 1 ]]; then
		if [[ $ITERM2_PROBE_LIFECYCLE_DEBUG == 1 ]]; then
			: >"$prefix/private/var/db/.launchd_log_debug"
			: >"$prefix/private/var/db/.launchd_log_shutdown"
		fi
		mkdir -p "$prefix/System/Library/LaunchDaemons"
			if [[ $ITERM2_PROBE_SHUTDOWN_PREFIX == 1 ]]; then
				cat >"$prefix/System/Library/LaunchDaemons/org.darlinghq.prefix-shutdown.plist" <<-'PLIST'
					<?xml version="1.0" encoding="UTF-8"?>
					<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
					<plist version="1.0">
					<dict>
						<key>Label</key>
						<string>org.darlinghq.prefix-shutdown</string>
						<key>ProgramArguments</key>
						<array>
							<string>/bin/sh</string>
							<string>-c</string>
				<string>read request &lt;/artifacts/prefix-shutdown-request; /bin/launchctl list &gt;/artifacts/launchctl-list-before-shutdown.txt 2&gt;/artifacts/launchctl-list-before-shutdown.err; exec /bin/launchctl shutdown</string>
						</array>
						<key>RunAtLoad</key>
						<true/>
						<key>StandardOutPath</key>
						<string>/artifacts/launchctl-shutdown.out</string>
						<key>StandardErrorPath</key>
						<string>/artifacts/launchctl-shutdown.err</string>
					</dict>
					</plist>
				PLIST
			fi
			cp /usr/local/libexec/darling/System/Library/LaunchAgents/com.apple.coreservices.launchservicesd.plist \
				"$prefix/System/Library/LaunchDaemons/"
			cp /usr/local/libexec/darling/System/Library/LaunchDaemons/com.apple.notifyd.plist \
				"$prefix/System/Library/LaunchDaemons/"
			if [[ $ITERM2_PROBE_CFPREFSD == 1 ]]; then
				cp /usr/local/libexec/darling/usr/sbin/cfprefsd "$prefix/usr/sbin/"
				cp /usr/local/libexec/darling/System/Library/LaunchDaemons/com.apple.cfprefsd.xpc.daemon.plist \
					"$prefix/System/Library/LaunchDaemons/"
				python3 - "$prefix/System/Library/LaunchDaemons/com.apple.cfprefsd.xpc.daemon.plist" <<'PY'
import os
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    job = plistlib.load(stream)
job["EnvironmentVariables"] = {
    "HOME": "/var/root",
    "CFFIXED_USER_HOME": "/var/root",
    "USER": "root",
    "LOGNAME": "root",
    "TMPDIR": "/private/var/tmp/",
    "DYLD_USE_CLOSURES": "0",
    "DARLING_ARM64_THREAD_BRIDGE": "1",
    "DARLING_CFPREFSD_DEBUG": os.environ["ITERM2_PROBE_CFPREFSD_DEBUG"],
    "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
}
job["StandardOutPath"] = "/artifacts/cfprefsd.out"
job["StandardErrorPath"] = "/artifacts/cfprefsd.err"
with open(path, "wb") as stream:
    plistlib.dump(job, stream)
PY
			fi
			if [[ $ITERM2_PROBE_APPLE_CFPREFSD == 1 ]]; then
				: >"$prefix/usr/sbin/cfprefsd"
				mount --bind /apple-cfprefsd/usr/sbin/cfprefsd "$prefix/usr/sbin/cfprefsd"
				mount -o remount,bind,ro "$prefix/usr/sbin/cfprefsd"
				cp /apple-cfprefsd/System/Library/LaunchDaemons/com.apple.cfprefsd.xpc.daemon.plist \
					"$prefix/System/Library/LaunchDaemons/"
				python3 - "$prefix/System/Library/LaunchDaemons/com.apple.cfprefsd.xpc.daemon.plist" <<'PY'
import os
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    job = plistlib.load(stream)
job["EnvironmentVariables"] = {
    "HOME": "/var/root",
    "CFFIXED_USER_HOME": "/var/root",
    "USER": "root",
    "LOGNAME": "root",
    "TMPDIR": "/private/var/tmp/",
    "DYLD_USE_CLOSURES": "0",
    "DARLING_ARM64_THREAD_BRIDGE": "1",
    "DARLING_DYLD_SHARED_CACHE": "1",
    "DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE": "1",
    "CFStringDisableROM": "1",
    "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
}
job["StandardOutPath"] = "/artifacts/apple-cfprefsd.out"
job["StandardErrorPath"] = "/artifacts/apple-cfprefsd.err"
with open(path, "wb") as stream:
    plistlib.dump(job, stream)
PY
			fi
			if [[ $ITERM2_PROBE_APPLE_LSD == 1 ]]; then
				mkdir -p "$prefix/usr/libexec"
				: >"$prefix/usr/libexec/lsd"
				mount --bind /apple-lsd/usr/libexec/lsd "$prefix/usr/libexec/lsd"
				mount -o remount,bind,ro "$prefix/usr/libexec/lsd"
				: >"$prefix/usr/libexec/dirhelper"
				mount --bind /apple-dirhelper/usr/libexec/dirhelper "$prefix/usr/libexec/dirhelper"
				mount -o remount,bind,ro "$prefix/usr/libexec/dirhelper"
				lsregister_path="$prefix/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
				mkdir -p "${lsregister_path%/*}"
				: >"$lsregister_path"
				mount --bind /apple-lsregister/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister "$lsregister_path"
				mount -o remount,bind,ro "$lsregister_path"
				cp /apple-lsd/System/Library/LaunchDaemons/com.apple.lsd.plist \
					"$prefix/System/Library/LaunchDaemons/"
				cp /apple-dirhelper/System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist \
					"$prefix/System/Library/LaunchDaemons/"
				python3 - "$prefix/System/Library/LaunchDaemons/com.apple.lsd.plist" <<PY
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    job = plistlib.load(stream)
job["EnvironmentVariables"] = {
	"HOME": "/var/root",
	"CFFIXED_USER_HOME": "/var/root",
	"USER": "root",
	"LOGNAME": "root",
	"TMPDIR": "/private/var/tmp/",
    "DYLD_USE_CLOSURES": "0",
    "DARLING_ARM64_THREAD_BRIDGE": "1",
    "DARLING_DYLD_SHARED_CACHE": "1",
    "DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE": "1",
    "CFStringDisableROM": "1",
    "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
}
if "$ITERM2_PROBE_DYLD_PRINT_BINDINGS" == "1":
    job["EnvironmentVariables"]["DYLD_PRINT_BINDINGS"] = "1"
job["StandardOutPath"] = "/artifacts/apple-lsd.out"
job["StandardErrorPath"] = "/artifacts/apple-lsd.err"
with open(path, "wb") as stream:
    plistlib.dump(job, stream)
PY
				python3 - "$prefix/System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist" <<PY
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    job = plistlib.load(stream)
job["EnvironmentVariables"].update({
    "DYLD_USE_CLOSURES": "0",
    "DARLING_ARM64_THREAD_BRIDGE": "1",
    "DARLING_DYLD_SHARED_CACHE": "1",
    "DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE": "1",
    "CFStringDisableROM": "1",
    "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
})
job["StandardOutPath"] = "/artifacts/apple-dirhelper.out"
job["StandardErrorPath"] = "/artifacts/apple-dirhelper.err"
with open(path, "wb") as stream:
    plistlib.dump(job, stream)

machine_boot = dict(job)
machine_boot.pop("MachServices", None)
machine_boot.pop("EnablePressuredExit", None)
machine_boot["Label"] = "org.darlinghq.dirhelper-machine-boot"
machine_boot["ProgramArguments"] = ["/usr/libexec/dirhelper", "-machineBoot"]
machine_boot["StandardOutPath"] = "/artifacts/apple-dirhelper-machine-boot.out"
machine_boot["StandardErrorPath"] = "/artifacts/apple-dirhelper-machine-boot.err"
machine_boot_path = path.rsplit("/", 1)[0] + "/org.darlinghq.dirhelper-machine-boot.plist"
with open(machine_boot_path, "wb") as stream:
    plistlib.dump(machine_boot, stream)
PY
				if [[ $ITERM2_PROBE_APPLE_MDS == 1 ]]; then
					metadata_framework="$prefix/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework"
					metadata_support="$metadata_framework/Versions/A/Support"
					metadata_resources="${metadata_support%/Support}/Resources"
					mkdir -p "$metadata_support" "$metadata_resources" "$prefix/private/var/db/Spotlight-V100"
					ln -sfn Versions/Current/Resources "$metadata_framework/Resources"
					mount --bind /apple-metadata/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Resources \
						"$metadata_resources"
					mount -o remount,bind,ro "$metadata_resources"
					for metadata_binary in mds mds_stores mdsync mdworker mdworker_shared; do
						: >"$metadata_support/$metadata_binary"
						mount --bind "/apple-metadata/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/$metadata_binary" \
							"$metadata_support/$metadata_binary"
						mount -o remount,bind,ro "$metadata_support/$metadata_binary"
					done
					mkdir -p "$prefix/usr/bin"
					: >"$prefix/usr/bin/mdutil"
					mount --bind /apple-metadata-tools/usr/bin/mdutil "$prefix/usr/bin/mdutil"
					mount -o remount,bind,ro "$prefix/usr/bin/mdutil"
					cp /apple-metadata/System/Library/LaunchDaemons/com.apple.metadata.mds{,.index,.scan,.index.readonly}.plist \
						"$prefix/System/Library/LaunchDaemons/"
					python3 - "$prefix/System/Library/LaunchDaemons/com.apple.metadata.mds.plist" <<PY
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    job = plistlib.load(stream)
job["EnvironmentVariables"].update({
    "DYLD_USE_CLOSURES": "0",
    "DARLING_ARM64_THREAD_BRIDGE": "1",
    "DARLING_DYLD_SHARED_CACHE": "1",
    "DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE": "1",
    "CFStringDisableROM": "1",
    "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
    "DARLING_DISKARBITRATION_DEBUG": "1",
})
job["StandardOutPath"] = "/artifacts/apple-mds.out"
job["StandardErrorPath"] = "/artifacts/apple-mds.err"
with open(path, "wb") as stream:
    plistlib.dump(job, stream)

if int("$ITERM2_PROBE_MDUTIL_DELAY") > 0:
    mdutil = {
        "Label": "org.darlinghq.mdutil-enable",
        "ProgramArguments": ["/usr/bin/mdutil", "-i", "on", "/"],
        "EnvironmentVariables": dict(job["EnvironmentVariables"]),
        "StandardOutPath": "/artifacts/apple-mdutil.out",
        "StandardErrorPath": "/artifacts/apple-mdutil.err",
        "StartInterval": int("$ITERM2_PROBE_MDUTIL_DELAY"),
        "LaunchOnlyOnce": True,
    }
    mdutil_path = path.rsplit("/", 1)[0] + "/org.darlinghq.mdutil-enable.plist"
    with open(mdutil_path, "wb") as stream:
        plistlib.dump(mdutil, stream)

for label in ("com.apple.metadata.mds.index", "com.apple.metadata.mds.index.readonly", "com.apple.metadata.mds.scan"):
    worker_path = path.rsplit("/", 1)[0] + "/" + label + ".plist"
    with open(worker_path, "rb") as stream:
        worker = plistlib.load(stream)
    worker.pop("UserName", None)
    worker.pop("GroupName", None)
    worker.pop("Disabled", None)
    worker.pop("MultipleInstances", None)
    worker["EnvironmentVariables"] = dict(job["EnvironmentVariables"])
    worker["StandardOutPath"] = "/artifacts/" + label + ".out"
    worker["StandardErrorPath"] = "/artifacts/" + label + ".err"
    with open(worker_path, "wb") as stream:
        plistlib.dump(worker, stream)
PY
				fi
			fi
			python3 - "$prefix/System/Library/LaunchDaemons/com.apple.coreservices.launchservicesd.plist" <<PY
import os
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    job = plistlib.load(stream)
job["EnvironmentVariables"] = {}
if os.environ["ITERM2_PROBE_LAUNCH_SERVICES_DEBUG"] == "1":
    job["EnvironmentVariables"]["DARLING_LAUNCHSERVICES_DEBUG"] = "1"
if os.environ["ITERM2_PROBE_DYLD_PRINT_SEGMENTS"] == "1":
    job["EnvironmentVariables"]["DYLD_PRINT_SEGMENTS"] = "1"
job["StandardOutPath"] = "/artifacts/launchservicesd-job.out"
job["StandardErrorPath"] = "/artifacts/launchservicesd-job.err"
with open(path, "wb") as stream:
    plistlib.dump(job, stream)
PY
			python3 - "$prefix/System/Library/LaunchDaemons/org.darlinghq.iterm2-probe.plist" <<PY
import os
import plistlib
import sys

environment = {
    "DISPLAY": ":95",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
	"PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
	"HOME": "/var/root",
	"CFFIXED_USER_HOME": "/var/root",
	"USER": "root",
	"LOGNAME": "root",
	"SHELL": "/bin/sh",
	"TMPDIR": "/private/var/tmp/",
	"PWD": "/var/root",
    "DYLD_USE_CLOSURES": "0",
    "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
    "DARLING_ARM64_THREAD_BRIDGE": "1",
    "DARLING_DYLD_SHARED_CACHE": "1",
    "DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE": "1",
    "CFStringDisableROM": "1",
}
if os.environ["ITERM2_PROBE_PREFER_DISK_FRAMEWORKS"] == "1":
    environment["DARLING_DYLD_SHARED_CACHE_PREFER_DISK_FRAMEWORKS"] = "1"
if os.environ["APP_PROBE_FORCE_FLAT_NAMESPACE"] == "1":
    environment["DYLD_FORCE_FLAT_NAMESPACE"] = "1"
if os.environ["APP_PROBE_FLAT_FALLBACK_TWO_LEVEL"] == "1":
    environment["DARLING_DYLD_FLAT_FALLBACK_TWO_LEVEL"] = "1"
if os.environ["ITERM2_PROBE_DISABLE_OBJC_PREOPT"] == "1":
    environment["OBJC_DISABLE_PREOPTIMIZATION"] = "YES"
    environment["OBJC_DISABLE_PREOPTIMIZED_CACHES"] = "YES"
if os.environ["ITERM2_PROBE_DISABLE_PREATTACHED_CATEGORIES"] == "1":
    environment["OBJC_DISABLE_PREATTACHED_CATEGORIES"] = "YES"
if os.environ["ITERM2_PROBE_MLDR_DEBUG"] == "1":
    environment["DARLING_MLDR_DEBUG"] = "1"
if os.environ["ITERM2_PROBE_DYLD_PRINT_SEGMENTS"] == "1":
    environment["DYLD_PRINT_SEGMENTS"] = "1"
if os.environ["ITERM2_PROBE_DYLD_PRINT_INITIALIZERS"] == "1":
    environment["DYLD_PRINT_INITIALIZERS"] = "1"
if os.environ["ITERM2_PROBE_APPKIT_BOOTSTRAP"] == "1":
    inserted_libraries = ["/usr/lib/libDarlingAppKitBootstrap.dylib"]
    if os.environ["ITERM2_PROBE_PREFER_DISK_FRAMEWORKS"] == "1":
        inserted_libraries.extend([
            "/usr/lib/swift/libswiftAppKit.dylib",
            "/usr/lib/swift/libswiftCoreGraphics.dylib",
        ])
    environment["DYLD_INSERT_LIBRARIES"] = ":".join(inserted_libraries)
    environment["DARLING_APPKIT_BOOTSTRAP_DEBUG"] = "1"
    if os.environ["ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_ITERM2_LOCALE_MODE_DO_NOT_SET"] = "1"
    if os.environ["ITERM2_PROBE_DIRECT_PTY"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_ITERM2_RUN_JOBS_IN_SERVERS_OFF"] = "1"
    if os.environ["ITERM2_PROBE_BASIC_KEY_INPUT"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_ITERM2_BASIC_KEY_INPUT"] = "1"
    if os.environ["ITERM2_PROBE_STABLE_KEYBOARD_SOURCE"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_ITERM2_STABLE_KEYBOARD_SOURCE"] = "1"
    if os.environ["ITERM2_PROBE_OPAQUE_TEXT"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_ITERM2_OPAQUE_TEXT"] = "1"
    if os.environ["ITERM2_PROBE_SHALLOW_TOKENIZER"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_SHALLOW_TOKENIZER"] = "1"
    if int(os.environ["ITERM2_PROBE_RESIZE_WIDTH"]) > 0:
        environment["DARLING_APPKIT_BOOTSTRAP_ITERM2_RESIZE_DEBUG"] = "1"
    if os.environ["ITERM2_PROBE_DISABLE_METAL"] == "1":
        environment["DARLING_METAL_DISABLE"] = "1"
    if os.environ["ITERM2_PROBE_APPKIT_REOPEN"] == "1":
        environment["DARLING_APPKIT_BOOTSTRAP_REOPEN_AFTER_LAUNCH"] = "1"
app_arguments = [os.environ["APP_PROBE_EXECUTABLE_PATH"]]
if os.environ["ITERM2_PROBE_SETTINGS_PERSISTENCE"] == "1":
    app_arguments.extend(["-SUEnableAutomaticChecks", "NO"])
job = {
    "Label": "org.darlinghq.iterm2-probe",
    "ProgramArguments": app_arguments,
    "EnvironmentVariables": environment,
    "StandardOutPath": "/artifacts/iterm2-job.out",
    "StandardErrorPath": "/artifacts/iterm2-job.err",
    "RunAtLoad": os.environ["ITERM2_PROBE_START_APP"] == "1",
}
if os.environ["ITERM2_PROBE_AE_DEBUG"] == "1":
    job["EnvironmentVariables"]["AEDebugSends"] = "1"
    job["EnvironmentVariables"]["AEDebugReceives"] = "1"
    job["EnvironmentVariables"]["AEDebugFull"] = "1"
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(job, stream)
if os.environ["ITERM2_PROBE_SETTINGS_PERSISTENCE"] == "1":
    relaunch_job = {
        "Label": "org.darlinghq.iterm2-settings-relaunch",
        "ProgramArguments": [
            "/bin/sh",
            "-c",
            "read request </artifacts/settings-persistence-relaunch-request; "
            "exec " + os.environ["APP_PROBE_EXECUTABLE_PATH"] +
            " -SUEnableAutomaticChecks NO",
        ],
        "EnvironmentVariables": dict(environment),
        "StandardOutPath": "/artifacts/settings-persistence-relaunch.out",
        "StandardErrorPath": "/artifacts/settings-persistence-relaunch.err",
        "RunAtLoad": True,
    }
    relaunch_path = sys.argv[1].replace(
        "org.darlinghq.iterm2-probe", "org.darlinghq.iterm2-settings-relaunch")
    with open(relaunch_path, "wb") as stream:
        plistlib.dump(relaunch_job, stream)
PY
			if (( ITERM2_PROBE_ACTIVATE_DELAY > 0 )); then
				python3 - "$prefix/System/Library/LaunchDaemons/org.darlinghq.iterm2-activate.plist" <<PY
import os
import plistlib
import sys

arguments = ["/usr/bin/open", "-a", os.environ["APP_PROBE_APPLICATION_NAME"]]
if os.environ["ITERM2_PROBE_ACTIVATE_APP_PATH"] == "1":
    arguments = ["/usr/bin/open", os.environ["APP_PROBE_APPLICATION_PATH"]]

job = {
    "Label": "org.darlinghq.iterm2-activate",
    "ProgramArguments": arguments,
    "EnvironmentVariables": {
        "DISPLAY": ":95",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "__mldr_ROOT_PATH": "/usr/local/libexec/darling",
        "DARLING_ARM64_THREAD_BRIDGE": "1",
    },
    "StandardOutPath": "/artifacts/iterm2-activate.out",
    "StandardErrorPath": "/artifacts/iterm2-activate.err",
    "StartInterval": int(os.environ["ITERM2_PROBE_ACTIVATE_DELAY"]),
    "LaunchOnlyOnce": True,
}
if os.environ["ITERM2_PROBE_ACTIVATE_SHARED_CACHE"] == "1":
    job["EnvironmentVariables"].update({
        "DYLD_USE_CLOSURES": "0",
        "DARLING_DYLD_SHARED_CACHE": "1",
        "DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE": "1",
        "CFStringDisableROM": "1",
    })
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(job, stream)
if os.environ["ITERM2_PROBE_APPLE_LSD"] == "1":
    register_delay = os.environ["ITERM2_PROBE_REGISTER_DELAY"]
    if not register_delay:
        register_delay = str(max(1, int(os.environ["ITERM2_PROBE_ACTIVATE_DELAY"]) // 2))
    dump_delay = os.environ["ITERM2_PROBE_REGISTER_DUMP_DELAY"]
    if not dump_delay:
        dump_delay = str(max(1, int(os.environ["ITERM2_PROBE_ACTIVATE_DELAY"]) * 3 // 4))
    register_target = os.environ["ITERM2_PROBE_REGISTER_PATH"]
    register_mode = "-f" if register_target.endswith(".app") else "-r"
    register_job = {
        "Label": "org.darlinghq.iterm2-register",
        "ProgramArguments": [
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister",
            "-lint",
            "-v",
            register_mode,
            register_target,
        ],
        "EnvironmentVariables": dict(job["EnvironmentVariables"]),
        "StandardOutPath": "/artifacts/iterm2-register.out",
        "StandardErrorPath": "/artifacts/iterm2-register.err",
        "StartInterval": int(register_delay),
        "LaunchOnlyOnce": True,
    }
    if os.environ["ITERM2_PROBE_REGISTER_KEEPALIVE"] == "1":
        register_job.pop("LaunchOnlyOnce")
        register_job["KeepAlive"] = True
        register_job["ThrottleInterval"] = 1
        register_job["WaitForDebugger"] = True
    register_path = sys.argv[1].replace("iterm2-activate", "iterm2-register")
    with open(register_path, "wb") as stream:
        plistlib.dump(register_job, stream)
    dump_job = {
        "Label": "org.darlinghq.iterm2-register-dump",
        "ProgramArguments": [register_job["ProgramArguments"][0], "-dump"],
        "EnvironmentVariables": dict(job["EnvironmentVariables"]),
        "StandardOutPath": "/artifacts/iterm2-register-dump.out",
        "StandardErrorPath": "/artifacts/iterm2-register-dump.err",
        "StartInterval": int(dump_delay),
        "LaunchOnlyOnce": True,
    }
    dump_path = sys.argv[1].replace("iterm2-activate", "iterm2-register-dump")
    with open(dump_path, "wb") as stream:
        plistlib.dump(dump_job, stream)
PY
			fi
			export DSERVER_INIT=/sbin/launchd
		elif [[ $ITERM2_PROBE_LAUNCH_SERVICES == 1 ]]; then
			printf "%s\n" \
				"#!/bin/sh" \
				"unset DARLING_DYLD_SHARED_CACHE DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE DYLD_PRINT_SEGMENTS CFStringDisableROM" \
				"DARLING_LAUNCHSERVICES_DEBUG=1 DARLING_XPC_STANDALONE_SERVICES=1 /System/Library/CoreServices/launchservicesd >/tmp/launchservicesd.out 2>/tmp/launchservicesd.err &" \
				"export DARLING_DYLD_SHARED_CACHE=1 DARLING_DYLD_SHARED_CACHE_AUTHORITATIVE=1 DYLD_PRINT_SEGMENTS=1 CFStringDisableROM=1" \
				"exec $APP_PROBE_EXECUTABLE_PATH" \
				>"$prefix/iterm-with-launchservices"
			chmod 0755 "$prefix/iterm-with-launchservices"
			export DSERVER_INIT=/iterm-with-launchservices
		else
			export DSERVER_INIT=$APP_PROBE_EXECUTABLE_PATH
		fi
		exec 3>/tmp/ready
		date +%s%N >/artifacts/server-start-ns.txt
		if [[ $ITERM2_PROBE_DEBUG == 1 ]]; then
			darlingserver "$prefix" 0 0 3 0 >/tmp/iterm.out 2>/tmp/iterm.err &
			server_pid=$!
				app_pid=
				declare -A debug_seen_pids=()
				debug_match_count=0
			debug_target=${ITERM2_PROBE_DEBUG_PROCESS:-$APP_PROBE_EXECUTABLE_PATH}
			if [[ -z $ITERM2_PROBE_DEBUG_PROCESS && $ITERM2_PROBE_FULL_LAUNCHD == 1 ]]; then
				debug_target=/sbin/launchd
			fi
				for ((attempt = 0; attempt < ITERM2_PROBE_WAIT_SECONDS * 1000; ++attempt)); do
				for candidate in $(pgrep -x mldr 2>/dev/null || true); do
					cmdline=$(tr "\0" " " <"/proc/$candidate/cmdline" 2>/dev/null || true)
						if [[ $cmdline == *"$debug_target"* ]]; then
							if [[ -z ${debug_seen_pids[$candidate]+present} ]]; then
								debug_seen_pids[$candidate]=1
								((++debug_match_count))
							fi
							if (( debug_match_count >= ITERM2_PROBE_DEBUG_PROCESS_MATCH_INDEX )); then
								app_pid=$candidate
								break 2
							fi
					fi
				done
				sleep 0.001
			done
			if [[ -z $app_pid ]]; then
				echo "iTerm2 mldr process was not observed" >/artifacts/gdb.txt
			else
				tr "\0" "\n" <"/proc/$app_pid/environ" | sort >/artifacts/debug-process-environ.txt
				sleep "$ITERM2_PROBE_DEBUG_DELAY"
					if [[ -n $ITERM2_PROBE_DEBUG_SIGNAL ]]; then
						gdb -q -batch -p "$app_pid" \
							-ex "set pagination off" \
							-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "catch signal $ITERM2_PROBE_DEBUG_SIGNAL" \
						-ex "condition \$bpnum $ITERM2_PROBE_DEBUG_BREAK_CONDITION" \
						-ex continue \
							-ex "info proc mappings" \
							-ex "info registers" \
							-ex "set \$darling_tsd = \$tpidr" \
							-ex "printf \"active TPIDR_EL0 / TSD base: %p\\n\", \$darling_tsd" \
							-ex "printf \"pthread candidate at TSD - 0xe0: %p\\n\", \$darling_tsd - 0xe0" \
							-ex "x/64gx \$darling_tsd-0xe0" \
							-ex "x/256gx \$sp" \
							-ex "x/64gx \$x19" \
							-ex "x/256bx \$x19" \
							-ex "x/128i \$pc-256" \
							-ex "x/128i \$x30-256" \
							-ex "set \$darling_frame = \$x29" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "set \$darling_frame = *(void **)\$darling_frame" \
							-ex "x/2gx \$darling_frame" \
							-ex "thread apply all bt full" \
							>/artifacts/gdb.txt 2>&1 &
					elif [[ -n $ITERM2_PROBE_DEBUG_SYSCALL ]]; then
					debug_syscall_args=()
					for _ in {1..32}; do
						debug_syscall_args+=(
							-ex continue
							-ex "printf \"syscall buffer fd=%ld length=%ld: \", \$x0, \$x2"
							-ex "x/s \$x1"
						)
					done
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "catch syscall $ITERM2_PROBE_DEBUG_SYSCALL" \
						"${debug_syscall_args[@]}" \
						>/artifacts/gdb.txt 2>&1 &
				elif [[ -n $ITERM2_PROBE_DEBUG_WATCH_ADDRESS ]]; then
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "hbreak *0x10000c68a38" \
						-ex continue \
						-ex "printf \"adapter reached; watched word before mapping: \"" \
						-ex "x/gx $ITERM2_PROBE_DEBUG_WATCH_ADDRESS" \
						-ex "watch *(unsigned long *)$ITERM2_PROBE_DEBUG_WATCH_ADDRESS" \
						-ex "delete 1" \
						-ex continue \
						-ex "info registers" \
						-ex "info registers v0 v1 v2 v3 v4 v5 v6 v7 fpsr fpcr" \
						-ex "x/24i \$pc-48" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				elif [[ -n $ITERM2_PROBE_DEBUG_CALL_ADDRESS ]]; then
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "hbreak *$ITERM2_PROBE_DEBUG_BREAK_ADDRESS" \
						-ex "condition 1 $ITERM2_PROBE_DEBUG_BREAK_CONDITION" \
						-ex continue \
						-ex "call ((void (*)())$ITERM2_PROBE_DEBUG_CALL_ADDRESS)()" \
						-ex "delete 1" \
						-ex "hbreak *$ITERM2_PROBE_DEBUG_FOLLOW_BREAK_ADDRESS" \
						-ex continue \
						-ex "info registers" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				elif [[ -n $ITERM2_PROBE_DEBUG_BREAK_SYMBOL ]]; then
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "hbreak $ITERM2_PROBE_DEBUG_BREAK_SYMBOL" \
						-ex continue \
						-ex "info registers" \
						-ex "x/32i \$pc-64" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				elif [[ -n $ITERM2_PROBE_DEBUG_BREAK_ADDRESS && -n $ITERM2_PROBE_DEBUG_FOLLOW_BREAK_ADDRESS ]]; then
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "hbreak *$ITERM2_PROBE_DEBUG_BREAK_ADDRESS" \
						-ex continue \
						-ex "printf \"enumerator object: %p\\n\", \$x0" \
						-ex "x/64gx \$x0" \
						-ex "set \$darling_enumerator_state = *(void **)(\$x0 + 0x28)" \
						-ex "set \$darling_enumerator_properties = *(void **)(\$x0 + 0x30)" \
						-ex "printf \"enumerator state=%p properties=%p\\n\", \$darling_enumerator_state, \$darling_enumerator_properties" \
						-ex "x/64gx \$darling_enumerator_state" \
						-ex "x/64gx \$darling_enumerator_properties" \
						-ex "set \$darling_property_storage = *(void **)(\$darling_enumerator_state + 0x10)" \
						-ex "printf \"property storage=%p\\n\", \$darling_property_storage" \
						-ex "x/16gx \$darling_property_storage" \
						-ex "set \$darling_property_1 = *(void **)(\$darling_property_storage + 0x0)" \
						-ex "set \$darling_property_2 = *(void **)(\$darling_property_storage + 0x8)" \
						-ex "set \$darling_property_3 = *(void **)(\$darling_property_storage + 0x10)" \
						-ex "set \$darling_property_4 = *(void **)(\$darling_property_storage + 0x18)" \
						-ex "printf \"property objects=%p %p %p %p\\n\", \$darling_property_1, \$darling_property_2, \$darling_property_3, \$darling_property_4" \
						-ex "x/16gx \$darling_property_1" \
						-ex "x/16gx \$darling_property_2" \
						-ex "x/16gx \$darling_property_3" \
						-ex "x/16gx \$darling_property_4" \
						-ex "delete 1" \
						-ex "hbreak *$ITERM2_PROBE_DEBUG_FOLLOW_BREAK_ADDRESS" \
						-ex continue \
						-ex "set \$darling_error = *(void **)(\$sp + 0x18)" \
						-ex "printf \"enumerator result 1: %ld url=%p error=%p\\n\", \$x0, *(void **)(\$sp + 0x20), \$darling_error" \
						-ex "info registers" \
						-ex "x/24gx \$sp" \
						-ex "x/48i \$pc-32" \
						-ex continue \
						-ex "printf \"enumerator result 2: %ld url=%p error=%p\\n\", \$x0, *(void **)(\$sp + 0x20), *(void **)(\$sp + 0x18)" \
						-ex continue \
						-ex "printf \"enumerator result 3: %ld url=%p error=%p\\n\", \$x0, *(void **)(\$sp + 0x20), *(void **)(\$sp + 0x18)" \
						-ex continue \
						-ex "printf \"enumerator result 4: %ld url=%p error=%p\\n\", \$x0, *(void **)(\$sp + 0x20), *(void **)(\$sp + 0x18)" \
						-ex continue \
						-ex "printf \"enumerator result 5: %ld url=%p error=%p\\n\", \$x0, *(void **)(\$sp + 0x20), *(void **)(\$sp + 0x18)" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				elif [[ -n $ITERM2_PROBE_DEBUG_BREAK_ADDRESS ]]; then
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "handle SIGILL nostop noprint pass" \
						-ex "handle SIGSEGV nostop noprint pass" \
						-ex "hbreak *$ITERM2_PROBE_DEBUG_BREAK_ADDRESS" \
						-ex "condition 1 $ITERM2_PROBE_DEBUG_BREAK_CONDITION" \
						-ex continue \
						-ex "info registers" \
						-ex "printf \"Objective-C objects: %p keys: %p count: %lu\\n\", \$x2, \$x3, \$x4" \
						-ex "x/24gx \$x2" \
						-ex "x/24gx \$x3" \
						-ex "x/24i \$pc-48" \
						-ex "x/128i \$pc" \
						-ex "set \$darling_frame = \$x29" \
						-ex "printf \"frame 0: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 1: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 2: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 3: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 4: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 5: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 6: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"frame 7: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "x/32i 0x1800afb14" \
						-ex "x/192i 0x1800ab900" \
						-ex "x/192i 0x180097b00" \
						-ex "x/320i 0x180315d00" \
						-ex "x/256i 0x180316800" \
						-ex "printf \"helper input: %p\\n\", \$x0" \
						-ex "x/16gx \$x0" \
						-ex "set \$darling_payload = *(void **)(\$x0+0x10)" \
						-ex "printf \"helper payload: %p\\n\", \$darling_payload" \
						-ex "x/24gx \$darling_payload" \
						-ex "printf \"preserved metadata x8: %p\\n\", \$x8" \
						-ex "x/16gx \$x8" \
						-ex "printf \"preserved metadata name: \"" \
						-ex "x/s *(void **)(\$x8+0x18)" \
						-ex "set \$darling_class = \$x19" \
						-ex "printf \"candidate class x19: %p\\n\", \$darling_class" \
						-ex "x/16gx \$darling_class" \
						-ex "printf \"candidate cache x20: %p\\n\", \$x20" \
						-ex "x/32gx \$x20" \
						-ex "set \$darling_object_class = *(unsigned long *)\$x20 & 0x7ffffffffff8" \
						-ex "printf \"candidate object class: %p\\n\", \$darling_object_class" \
						-ex "x/12gx \$darling_object_class" \
						-ex "set \$darling_instance_ro = *(unsigned long *)(\$x20+0x20) & 0x7ffffffffff8" \
						-ex "printf \"candidate instance metadata: %p\\n\", \$darling_instance_ro" \
						-ex "x/12gx \$darling_instance_ro" \
						-ex "printf \"candidate instance name: \"" \
						-ex "x/s *(void **)(\$darling_instance_ro+0x18)" \
						-ex "printf \"candidate owner x22: %p\\n\", \$x22" \
						-ex "x/16gx \$x22" \
						-ex "printf \"candidate auxiliary x25: %p\\n\", \$x25" \
						-ex "x/32gx \$x25" \
						-ex "set \$darling_aux_payload = *(void **)(\$x25+0x10)" \
						-ex "printf \"candidate auxiliary payload: %p\\n\", \$darling_aux_payload" \
						-ex "x/24gx \$darling_aux_payload" \
						-ex "set \$darling_data = *(unsigned long *)(\$darling_class+0x20) & 0x7ffffffffff8" \
						-ex "printf \"candidate class data: %p\\n\", \$darling_data" \
						-ex "x/16gx \$darling_data" \
						-ex "set \$darling_ro = *(unsigned long *)(\$x0+8) & 0x7ffffffffff8" \
						-ex "printf \"candidate ro/ext: %p\\n\", \$darling_ro" \
						-ex "x/16gx \$darling_ro" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				elif [[ $ITERM2_PROBE_DEBUG_SAMPLE == 1 ]]; then
					gdb -q -batch -p "$app_pid" \
						-ex "set pagination off" \
						-ex "info proc mappings" \
						-ex "info registers" \
						-ex "x/24i \$pc-64" \
						-ex "x/16wx \$pc-64" \
						-ex "set \$darling_frame = \$x29" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = \$x29" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "printf \"XPC wrapper frame: %p\\n\", \$darling_frame" \
						-ex "x/2gx \$darling_frame-0x18" \
						-ex "set \$darling_xpc_message = *(void **)(\$darling_frame-0x18)" \
						-ex "printf \"XPC message: %p\\n\", \$darling_xpc_message" \
						-ex "x/24gx \$darling_xpc_message" \
						-ex "set \$darling_xpc_connection = *(void **)(\$darling_frame-0x10)" \
						-ex "printf \"XPC connection: %p\\n\", \$darling_xpc_connection" \
						-ex "x/40gx \$darling_xpc_connection" \
						-ex "x/gx \$darling_xpc_connection+0x18" \
						-ex "x/s *(void **)(\$darling_xpc_connection+0x18)" \
						-ex "thread apply all info registers x0 x1 x2 x3 x4 x5 x6 x7 x16 x17 x29 x30 sp pc" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				else
				gdb -q -batch -p "$app_pid" \
					-ex "set pagination off" \
					-ex "handle SIGILL nostop noprint pass" \
					-ex "handle SIGSEGV nostop noprint pass" \
					-ex "catch signal SIGTRAP" \
					-ex "condition \$bpnum (\$pc < 0x1000000000000)" \
					-ex "catch signal SIGSEGV" \
					-ex "condition \$bpnum (\$pc < 0x1000000000000)" \
					-ex continue \
						-ex "info proc mappings" \
					-ex "info registers" \
					-ex "x/128i \$pc-256" \
						-ex "x/64wx \$pc-256" \
						-ex "x/4gx \$x17" \
					-ex "x/32gx \$x20" \
						-ex "x/24gx \$sp" \
						-ex "set \$darling_frame = \$x29" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "set \$darling_frame = *(void **)\$darling_frame" \
						-ex "x/2gx \$darling_frame" \
						-ex "thread apply all info registers" \
						-ex "thread apply all bt full" \
						>/artifacts/gdb.txt 2>&1 &
				fi
				debugger_pid=$!
			fi
		elif [[ $ITERM2_PROBE_DSERVER_GDB == 1 ]]; then
			gdb -q -batch \
				-ex run \
				-ex "thread apply all bt full" \
				--args darlingserver "$prefix" 0 0 3 0 \
				>/tmp/iterm.out 2>/artifacts/dserver-gdb.txt &
		elif [[ $ITERM2_PROBE_TRACE == 1 ]]; then
			strace -ff -s 256 -o /artifacts/strace darlingserver "$prefix" 0 0 3 0 >/tmp/iterm.out 2>/tmp/iterm.err &
		else
			darlingserver "$prefix" 0 0 3 0 >/tmp/iterm.out 2>/tmp/iterm.err &
		fi
		[[ -n $server_pid ]] || server_pid=$!
		exec 3>&-
		input_pid=
		if [[ -n $ITERM2_PROBE_TYPE_TEXT ]]; then
			(
				wait_for_iterm2_window() {
					local candidate= geometry= width= height= area= best_area=0
					local best_window=
					for _ in {1..400}; do
						while read -r candidate; do
							[[ -n $candidate ]] || continue
							geometry=$(xdotool getwindowgeometry --shell "$candidate" \
								2>/dev/null || true)
							width=$(sed -n "s/^WIDTH=//p" <<<"$geometry")
							height=$(sed -n "s/^HEIGHT=//p" <<<"$geometry")
							[[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || continue
							area=$((width * height))
							if (( area > best_area )); then
								best_area=$area
								best_window=$candidate
							fi
						done < <(xdotool search --onlyvisible --class "^iTerm2$" \
							2>/dev/null || true)
						if [[ -n $best_window && -n $app_pid && -r /proc/$app_pid/status ]] &&
							! grep -q "^CoreDumping:[[:space:]]*1$" /proc/$app_pid/status; then
							printf "%s\n" "$best_window"
							return 0
						fi
						best_area=0
						best_window=
						sleep 0.05
					done
					return 1
				}
				for ((attempt = 0; attempt < ITERM2_PROBE_WAIT_SECONDS * 20; ++attempt)); do
					if ps -eo args= | grep -Fxq -- "-sh"; then
						shell_ready_ns=$(date +%s%N)
						server_start_ns=$(cat /artifacts/server-start-ns.txt)
						printf "server_start_ns=%s\nshell_ready_ns=%s\nelapsed_ms=%s\n" \
							"$server_start_ns" "$shell_ready_ns" \
							"$(( (shell_ready_ns - server_start_ns) / 1000000 ))" \
							>/artifacts/shell-ready.txt
						app_pid=$(ps -eo pid=,args= | awk \
							"\$2 == \"$APP_PROBE_EXECUTABLE_PATH\" { print \$1; exit }")
						if [[ -n $app_pid ]]; then
							cat "/proc/$app_pid/status" \
								>/artifacts/iterm2-before-input-status.txt 2>/dev/null || true
							cat "/proc/$app_pid/smaps_rollup" \
								>/artifacts/iterm2-before-input-smaps-rollup.txt 2>/dev/null || true
						fi
						window=$(wait_for_iterm2_window) || exit 1
						xdotool windowactivate --sync "$window"
						sleep 0.5
						xdotool type --delay 20 --clearmodifiers -- "$ITERM2_PROBE_TYPE_TEXT"
						if [[ $ITERM2_PROBE_TYPE_RETURN == 1 ]]; then
							sleep 0.5
							xdotool key Return
						fi
						if [[ $ITERM2_PROBE_SETTINGS_PERSISTENCE == 1 ]]; then
							wait_for_settings_window() {
								local settings_window=
								for _ in {1..200}; do
									settings_window=$(xdotool search --onlyvisible \
										--name "^Settings$" 2>/dev/null | tail -1)
									[[ -z $settings_window ]] || break
									sleep 0.05
								done
								[[ -n $settings_window ]] || return 1
								printf "%s\n" "$settings_window"
							}
							quit_settings_app() {
								local expected_pid=$1 phase=$2 target_window=$3
								local dialog= dialog_x= dialog_y=
								xdotool windowactivate --sync "$target_window"
								xdotool key --clearmodifiers super+q
								for _ in {1..100}; do
									if ! kill -0 "$expected_pid" 2>/dev/null; then
										break
									fi
									dialog=$(xwininfo -root -tree 2>/dev/null |
										awk "/510x126/ { print \$1; exit }")
									[[ -z $dialog ]] || break
									sleep 0.05
								done
								if [[ -n $dialog ]]; then
									dialog_x=$(xwininfo -id "$dialog" |
										awk "/Absolute upper-left X:/ { print \$4 }")
									dialog_y=$(xwininfo -id "$dialog" |
										awk "/Absolute upper-left Y:/ { print \$4 }")
									xdotool mousemove "$((dialog_x + 466))" "$((dialog_y + 98))"
									xdotool click 1
								fi
								for _ in {1..200}; do
									kill -0 "$expected_pid" 2>/dev/null || break
									sleep 0.05
								done
								local exited=0
								kill -0 "$expected_pid" 2>/dev/null || exited=1
								printf "pid=%s\ndialog=%s\nexited=%s\n" \
									"$expected_pid" "$dialog" "$exited" \
									>"/artifacts/settings-persistence-$phase-quit.txt"
								(( exited == 1 ))
							}

							find "$prefix/private/var/root" "$prefix/home" -type f \
								-printf "%T@ %s %p\n" 2>/dev/null | sort \
								>/artifacts/settings-persistence-before-files.txt
							xdotool key --clearmodifiers super+comma
							settings_window=$(wait_for_settings_window)
							xdotool windowmove "$settings_window" 493 0
							xdotool windowactivate --sync "$settings_window"
							sleep 0.5
							settings_x=$(xwininfo -id "$settings_window" |
								awk "/Absolute upper-left X:/ { print \$4 }")
							settings_y=$(xwininfo -id "$settings_window" |
								awk "/Absolute upper-left Y:/ { print \$4 }")
							scrot /artifacts/settings-persistence-before.png >/dev/null 2>&1
							convert /artifacts/settings-persistence-before.png \
								-crop "20x20+$((settings_x + 294))+$((settings_y + 122))" \
								+repage /artifacts/settings-persistence-before-crop.png
							xdotool mousemove "$((settings_x + 304))" "$((settings_y + 133))"
							xdotool click 1
							sleep 0.5
							scrot /artifacts/settings-persistence-mutated.png >/dev/null 2>&1
							convert /artifacts/settings-persistence-mutated.png \
								-crop "20x20+$((settings_x + 294))+$((settings_y + 122))" \
								+repage /artifacts/settings-persistence-mutated-crop.png
							printf "window=%s\nx=%s\ny=%s\n" \
								"$settings_window" "$settings_x" "$settings_y" \
								>/artifacts/settings-persistence-first-window.txt
							quit_settings_app "$app_pid" first "$settings_window"
							find "$prefix/private/var/root" "$prefix/home" -type f \
								-printf "%T@ %s %p\n" 2>/dev/null | sort \
								>/artifacts/settings-persistence-after-first-quit-files.txt

							printf "relaunch\n" >/artifacts/settings-persistence-relaunch-request
							relaunch_pid=
							for _ in {1..400}; do
								relaunch_pid=$(ps -eo pid=,args= | awk \
									-v old="$app_pid" -v executable="$APP_PROBE_EXECUTABLE_PATH" \
									"\$1 != old && \$2 == executable { print \$1; exit }")
								[[ -z $relaunch_pid ]] || break
								sleep 0.05
							done
							[[ $relaunch_pid =~ ^[1-9][0-9]*$ ]]
							for _ in {1..400}; do
								ps -eo args= | grep -Fxq -- "-sh" && break
								sleep 0.05
							done
							sleep 1
							relaunch_window=$(xdotool getactivewindow)
							xdotool key --clearmodifiers super+comma
							relaunch_settings_window=$(wait_for_settings_window)
							xdotool windowmove "$relaunch_settings_window" 493 0
							xdotool windowactivate --sync "$relaunch_settings_window"
							sleep 0.5
							relaunch_settings_x=$(xwininfo -id "$relaunch_settings_window" |
								awk "/Absolute upper-left X:/ { print \$4 }")
							relaunch_settings_y=$(xwininfo -id "$relaunch_settings_window" |
								awk "/Absolute upper-left Y:/ { print \$4 }")
							scrot /artifacts/settings-persistence-relaunch.png >/dev/null 2>&1
							convert /artifacts/settings-persistence-relaunch.png \
								-crop "20x20+$((relaunch_settings_x + 294))+$((relaunch_settings_y + 122))" \
								+repage /artifacts/settings-persistence-relaunch-crop.png
							set +e
							before_mutated_pixels=$(compare -metric AE \
								/artifacts/settings-persistence-before-crop.png \
								/artifacts/settings-persistence-mutated-crop.png null: 2>&1)
							mutated_relaunch_pixels=$(compare -metric AE \
								/artifacts/settings-persistence-mutated-crop.png \
								/artifacts/settings-persistence-relaunch-crop.png null: 2>&1)
							set -e
							printf "before_mutated_pixels=%s\nmutated_relaunch_pixels=%s\n" \
								"$before_mutated_pixels" "$mutated_relaunch_pixels" \
								>/artifacts/settings-persistence-pixels.txt
							printf "window=%s\nx=%s\ny=%s\n" \
								"$relaunch_settings_window" "$relaunch_settings_x" \
								"$relaunch_settings_y" \
								>/artifacts/settings-persistence-relaunch-window.txt
							quit_settings_app "$relaunch_pid" relaunch \
								"$relaunch_settings_window"
							find "$prefix/private/var/root" "$prefix/home" -type f \
								-printf "%T@ %s %p\n" 2>/dev/null | sort \
								>/artifacts/settings-persistence-after-relaunch-quit-files.txt
							printf "first_pid=%s\nrelaunch_pid=%s\n" \
								"$app_pid" "$relaunch_pid" \
								>/artifacts/settings-persistence-result.txt
						fi
						if [[ $ITERM2_PROBE_TAB_WORKFLOW == 1 ]]; then
							for _ in {1..600}; do
								[[ -f /artifacts/silver-tab1-ready.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-tab1-ready.txt ]] || exit 1
							tab1_kernel_pid=$(ps -eo pid=,args= | \
								awk "\$2 == \"-sh\" { print \$1 }")
							[[ $tab1_kernel_pid =~ ^[1-9][0-9]*$ ]] || exit 1
							printf "%s\n" "$tab1_kernel_pid" \
								>/artifacts/silver-tab1-kernel-pid.txt
							xdotool key --clearmodifiers super+t
							for _ in {1..600}; do
								(( $(ps -eo args= | grep -Fxc -- "-sh") >= 2 )) && break
								sleep 0.05
							done
							(( $(ps -eo args= | grep -Fxc -- "-sh") >= 2 )) || exit 1
							xdotool windowactivate --sync "$window"
							sleep 1
							dollar=$(printf "\044")
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-tab2-pid.txt;printf ready >/artifacts/silver-tab2-ready.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..600}; do
								[[ -f /artifacts/silver-tab2-ready.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-tab2-ready.txt ]] || exit 1
							tab2_kernel_pid=$(ps -eo pid=,args= | \
								awk "\$2 == \"-sh\" { print \$1 }" | \
								grep -vx -- "$tab1_kernel_pid")
							[[ $tab2_kernel_pid =~ ^[1-9][0-9]*$ ]] || exit 1
							printf "%s\n" "$tab2_kernel_pid" \
								>/artifacts/silver-tab2-kernel-pid.txt
							xdotool key --clearmodifiers super+1
							sleep 1
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-tab1-return-pid.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..600}; do
								[[ -f /artifacts/silver-tab1-return-pid.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-tab1-return-pid.txt ]] || exit 1
							xdotool key --clearmodifiers super+2
							sleep 1
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-tab2-return-pid.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..600}; do
								[[ -f /artifacts/silver-tab2-return-pid.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-tab2-return-pid.txt ]] || exit 1
							xdotool key --clearmodifiers super+1
							sleep 0.5
							scrot /artifacts/silver-tabs.png >/dev/null 2>&1 || true
							printf "shells=%s\nwindow=%s\n" \
								"$(ps -eo args= | grep -Fxc -- "-sh")" "$window" \
								>/artifacts/silver-tabs.txt
							if [[ $ITERM2_PROBE_TAB_CLOSE_WORKFLOW == 1 ]]; then
								if [[ $ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE == 1 ]]; then
									{
										for task in /proc/$app_pid/task/*; do
											tid=${task##*/}
											printf "tid=%s comm=" "$tid"
											cat "$task/comm" 2>/dev/null || true
											printf "wchan="
											cat "$task/wchan" 2>/dev/null || true
											printf "syscall="
											cat "$task/syscall" 2>/dev/null || true
										done
									} >/artifacts/silver-tabs-threads.txt
								fi
								xdotool type --delay 20 --clearmodifiers -- exit
								xdotool key --clearmodifiers Return
								for _ in {1..200}; do
									app_alive=0
									kill -0 "$app_pid" 2>/dev/null && app_alive=1
									shells=$(ps -eo args= | grep -Fxc -- "-sh")
									(( app_alive == 0 || shells == 1 )) && break
									sleep 0.05
								done
								sleep 1
								xdotool type --delay 20 --clearmodifiers -- \
									"printf %s ${dollar}${dollar} >/artifacts/silver-tab-close-survivor-pid.txt;printf ready >/artifacts/silver-tab-close-survivor-ready.txt"
								xdotool key --clearmodifiers Return
								for _ in {1..200}; do
									[[ -f /artifacts/silver-tab-close-survivor-ready.txt ]] && break
									sleep 0.05
								done
								app_alive=0
								[[ -d /proc/$app_pid/task ]] && kill -0 "$app_pid" 2>/dev/null && app_alive=1
								shells=$(ps -eo args= | grep -Fxc -- "-sh")
								survivor_ready=0
								[[ -f /artifacts/silver-tab-close-survivor-ready.txt ]] && survivor_ready=1
								printf "app_alive=%s\nshells=%s\nsurvivor_ready=%s\n" \
									"$app_alive" "$shells" "$survivor_ready" \
									>/artifacts/silver-tab-close.txt
								xwininfo -root -tree >/artifacts/silver-tab-close-windows.txt 2>&1 || true
								scrot /artifacts/silver-tab-close.png >/dev/null 2>&1 || true
								if [[ $ITERM2_PROBE_TAB_CLOSE_DEBUG_SAMPLE == 1 && -d /proc/$app_pid/task ]] &&
									kill -0 "$app_pid" 2>/dev/null; then
									{
										for task in /proc/$app_pid/task/*; do
											tid=${task##*/}
											printf "tid=%s comm=" "$tid"
											cat "$task/comm" 2>/dev/null || true
											printf "wchan="
											cat "$task/wchan" 2>/dev/null || true
											printf "syscall="
											cat "$task/syscall" 2>/dev/null || true
										done
									} >/artifacts/silver-tab-close-threads.txt
									gdb -q -batch -p "$app_pid" \
										-ex "set pagination off" \
										-ex "info proc mappings" \
										-ex "thread apply all info registers x0 x1 x2 x3 x4 x5 x6 x7 x8 x19 x20 x21 x22 x23 x24 x25 x26 x27 x28 x29 x30 sp pc tpidr" \
										-ex "thread apply all x/64gx \$sp" \
										-ex "thread apply all x/32gx \$x29" \
										-ex "thread apply all bt full" \
										>/artifacts/silver-tab-close-gdb.txt 2>&1 || true
								fi
							fi
						fi
						if [[ $ITERM2_PROBE_SPLIT_WORKFLOW == 1 ]]; then
							for _ in {1..600}; do
								[[ -f /artifacts/silver-pane1-ready.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-pane1-ready.txt ]] || exit 1
							pane1_kernel_pid=$(ps -eo pid=,args= | awk \
								"\$2 == \"-sh\" { print \$1 }")
							[[ $pane1_kernel_pid =~ ^[1-9][0-9]*$ ]] || exit 1
							printf "%s\n" "$pane1_kernel_pid" \
								>/artifacts/silver-pane1-kernel-pid.txt
							xdotool key --clearmodifiers super+d
							for _ in {1..600}; do
								(( $(ps -eo args= | grep -Fxc -- "-sh") >= 2 )) && break
								sleep 0.05
							done
							(( $(ps -eo args= | grep -Fxc -- "-sh") == 2 )) || exit 1
							sleep 0.5
							dollar=$(printf "\044")
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-pane2-pid.txt;printf ready >/artifacts/silver-pane2-ready.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..600}; do
								[[ -f /artifacts/silver-pane2-ready.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-pane2-ready.txt ]] || exit 1
							pane2_kernel_pid=$(ps -eo pid=,args= | awk \
								-v first="$pane1_kernel_pid" \
								"\$2 == \"-sh\" && \$1 != first { print \$1 }")
							[[ $pane2_kernel_pid =~ ^[1-9][0-9]*$ ]] || exit 1
							printf "%s\n" "$pane2_kernel_pid" \
								>/artifacts/silver-pane2-kernel-pid.txt
							xdotool key --clearmodifiers super+bracketleft
							sleep 0.5
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-pane1-return-pid.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..600}; do
								[[ -f /artifacts/silver-pane1-return-pid.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-pane1-return-pid.txt ]] || exit 1
							xdotool key --clearmodifiers super+bracketright
							sleep 0.5
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-pane2-return-pid.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..600}; do
								[[ -f /artifacts/silver-pane2-return-pid.txt ]] && break
								sleep 0.05
							done
							[[ -f /artifacts/silver-pane2-return-pid.txt ]] || exit 1
							scrot /artifacts/silver-splits.png >/dev/null 2>&1 || true
							printf "shells=%s\nwindow=%s\n" \
								"$(ps -eo args= | grep -Fxc -- "-sh")" "$window" \
								>/artifacts/silver-splits.txt
							xdotool key --clearmodifiers super+bracketleft
							sleep 0.5
							xdotool type --delay 20 --clearmodifiers -- exit
							xdotool key --clearmodifiers Return
							for _ in {1..200}; do
								(( $(ps -eo args= | grep -Fxc -- "-sh") == 1 )) && break
								sleep 0.05
							done
							sleep 1
							xdotool windowactivate --sync "$window"
							xdotool key --clearmodifiers super+bracketright
							sleep 0.5
							xdotool type --delay 20 --clearmodifiers -- \
								"printf %s ${dollar}${dollar} >/artifacts/silver-split-survivor-pid.txt;printf ready >/artifacts/silver-split-survivor-ready.txt"
							xdotool key --clearmodifiers Return
							for _ in {1..200}; do
								[[ -f /artifacts/silver-split-survivor-ready.txt ]] && break
								sleep 0.05
							done
							app_alive=0
							[[ -d /proc/$app_pid/task ]] && kill -0 "$app_pid" 2>/dev/null && app_alive=1
							shells=$(ps -eo args= | grep -Fxc -- "-sh")
							survivor_ready=0
							[[ -f /artifacts/silver-split-survivor-ready.txt ]] && survivor_ready=1
							printf "app_alive=%s\nshells=%s\nsurvivor_ready=%s\n" \
								"$app_alive" "$shells" "$survivor_ready" \
								>/artifacts/silver-split-close.txt
							xwininfo -root -tree >/artifacts/silver-split-close-windows.txt 2>&1 || true
							scrot /artifacts/silver-split-close.png >/dev/null 2>&1 || true
						fi
						if (( ITERM2_PROBE_SOAK_SECONDS > 0 )); then
							soak_start=$(date +%s)
							soak_start_ns=$(date +%s%N)
							soak_iteration=0
							soak_completed=1
							soak_failure=none
							soak_session_exited=0
							while (( $(date +%s) - soak_start < ITERM2_PROBE_SOAK_SECONDS )); do
								if ! kill -0 "$app_pid" 2>/dev/null; then
									soak_completed=0
									soak_failure=application-exited
									break
								fi
								((++soak_iteration))
								printf -v soak_id "%04d" "$soak_iteration"
								window=$(xdotool getactivewindow)
								if (( soak_iteration % 2 == 0 )); then
									xdotool windowsize "$window" 760 500
								else
									xdotool windowsize "$window" 900 600
								fi
								soak_command="/bin/sh -c \"exit 37\";printf \"%s\\n\" \"\$?\" >/artifacts/soak-status-$soak_id.txt;printf \"SOAK_$soak_id\\n\""
								xdotool type --delay 5 --clearmodifiers -- "$soak_command"
								xdotool key --clearmodifiers Return
								for _ in {1..600}; do
									[[ -f /artifacts/soak-status-$soak_id.txt ]] && break
									sleep 0.05
								done
								if ! grep -Fxq 37 /artifacts/soak-status-$soak_id.txt 2>/dev/null; then
									soak_completed=0
									soak_failure=foreground-status
									break
								fi
								if (( soak_iteration % 6 == 0 )); then
									xdotool type --delay 5 --clearmodifiers -- \
										"terminal-size --lines 200;printf done >/artifacts/soak-scroll-$soak_id.txt"
									xdotool key --clearmodifiers Return
									for _ in {1..600}; do
										[[ -f /artifacts/soak-scroll-$soak_id.txt ]] && break
										sleep 0.05
									done
									if [[ ! -f /artifacts/soak-scroll-$soak_id.txt ]]; then
										soak_completed=0
										soak_failure=scroll-output
										break
									fi
									xdotool mousemove --window "$window" 500 250
									for _ in {1..4}; do xdotool click 4; done
									for _ in {1..4}; do xdotool click 5; done
								fi
								if (( soak_iteration % 12 == 0 )); then
									soak_token="SOAK_PASTE_$soak_id"
									printf "%s" "$soak_token" | xclip -selection clipboard
									xdotool type --delay 5 --clearmodifiers -- \
										"cat >/artifacts/soak-paste-$soak_id.txt"
									xdotool key --clearmodifiers Return
									sleep 0.25
									xdotool key --clearmodifiers super+v
									sleep 0.5
									xdotool key --clearmodifiers ctrl+d
									sleep 0.25
									xdotool key --clearmodifiers ctrl+d
									for _ in {1..600}; do
										[[ -f /artifacts/soak-paste-$soak_id.txt ]] &&
											[[ $(cat /artifacts/soak-paste-$soak_id.txt) == "$soak_token" ]] && break
										sleep 0.05
									done
									if [[ $(cat /artifacts/soak-paste-$soak_id.txt 2>/dev/null || true) != "$soak_token" ]]; then
										soak_completed=0
										soak_failure=clipboard-paste
										break
									fi
								fi
								soak_stat_sampled=0
								for _ in {1..20}; do
									if cat "/proc/$app_pid/stat" \
										>"/artifacts/soak-stat-$soak_id.txt" 2>/dev/null; then
										soak_stat_sampled=1
										break
									fi
									sleep 0.05
								done
								if (( soak_stat_sampled == 0 )); then
										soak_completed=0
										soak_failure=process-stat
										break
								fi
								cat "/proc/$app_pid/smaps_rollup" \
									>"/artifacts/soak-smaps-$soak_id.txt" 2>/dev/null || true
								printf "iteration=%s\nelapsed_seconds=%s\napp_pid=%s\nwindow=%s\n" \
									"$soak_iteration" "$(( $(date +%s) - soak_start ))" \
									"$app_pid" "$window" >/artifacts/soak-heartbeat.txt
								soak_remaining=$(( ITERM2_PROBE_SOAK_SECONDS - ($(date +%s) - soak_start) ))
								if (( soak_remaining > 0 )); then
									if (( soak_remaining < ITERM2_PROBE_SOAK_INTERVAL )); then
										sleep "$soak_remaining"
									else
										sleep "$ITERM2_PROBE_SOAK_INTERVAL"
									fi
								fi
							done
							soak_end_ns=$(date +%s%N)
							soak_elapsed=$(( (soak_end_ns - soak_start_ns) / 1000000000 ))
							if (( soak_completed == 1 && soak_elapsed < ITERM2_PROBE_SOAK_SECONDS )); then
								sleep "$((ITERM2_PROBE_SOAK_SECONDS - soak_elapsed))"
								soak_end_ns=$(date +%s%N)
								soak_elapsed=$(( (soak_end_ns - soak_start_ns) / 1000000000 ))
							fi
							if (( soak_elapsed < ITERM2_PROBE_SOAK_SECONDS )); then
								soak_completed=0
								[[ $soak_failure != none ]] || soak_failure=duration
							fi
							scrot /artifacts/soak-final.png >/dev/null 2>&1 || true
							if kill -0 "$app_pid" 2>/dev/null; then
								xdotool windowactivate --sync "$window"
								xdotool type --delay 20 --clearmodifiers -- exit
								xdotool key --clearmodifiers Return
								for _ in {1..600}; do
									if ! ps -eo args= | grep -Fxq -- "-sh"; then
										soak_session_exited=1
										break
									fi
									sleep 0.05
								done
								if (( soak_session_exited == 0 && soak_completed == 1 )); then
									soak_completed=0
									soak_failure=session-exit
								fi
							fi
							printf "requested_seconds=%s\nelapsed_seconds=%s\niterations=%s\ncompleted=%s\nfailure=%s\nsession_exited=%s\n" \
								"$ITERM2_PROBE_SOAK_SECONDS" "$soak_elapsed" \
								"$soak_iteration" "$soak_completed" "$soak_failure" \
								"$soak_session_exited" \
								>/artifacts/soak-summary.txt
						fi
						if (( ITERM2_PROBE_RESIZE_WIDTH > 0 )); then
							sleep "$ITERM2_PROBE_RESIZE_DELAY"
							xdotool windowsize "$window" \
								"$ITERM2_PROBE_RESIZE_WIDTH" \
								"$ITERM2_PROBE_RESIZE_HEIGHT"
							printf "window=%s\nwidth=%s\nheight=%s\n" "$window" \
								"$ITERM2_PROBE_RESIZE_WIDTH" \
								"$ITERM2_PROBE_RESIZE_HEIGHT" \
								>/artifacts/resize-input.txt
						fi
						if (( ITERM2_PROBE_SCROLL_UP_TICKS > 0 )); then
							sleep "$ITERM2_PROBE_SCROLL_UP_DELAY"
							xdotool mousemove --window "$window" 500 250
							xdotool getmouselocation --shell \
								>/artifacts/scroll-pointer.txt
							for ((tick = 0; tick < ITERM2_PROBE_SCROLL_UP_TICKS; ++tick)); do
								xdotool click 4
								if (( tick + 1 < ITERM2_PROBE_SCROLL_UP_TICKS )); then
									sleep "$ITERM2_PROBE_SCROLL_UP_TICK_DELAY"
								fi
							done
							printf "window=%s\nticks=%s\n" "$window" \
								"$ITERM2_PROBE_SCROLL_UP_TICKS" \
								>/artifacts/scroll-up-input.txt
						fi
						if [[ $ITERM2_PROBE_SELECTION_ENABLED == 1 ]]; then
							sleep "$ITERM2_PROBE_SELECTION_DELAY"
							xdotool mousemove --window "$window" \
								"$ITERM2_PROBE_SELECTION_START_X" \
								"$ITERM2_PROBE_SELECTION_START_Y"
							xdotool mousedown 1
							xdotool mousemove --sync --window "$window" \
								"$ITERM2_PROBE_SELECTION_END_X" \
								"$ITERM2_PROBE_SELECTION_END_Y"
							xdotool mouseup 1
							sleep 0.5
							xdotool key --clearmodifiers super+c
							sleep 0.5
							timeout 5s xclip -selection clipboard -out \
								>/artifacts/selection-clipboard.txt \
								2>/artifacts/selection-clipboard.err || true
							timeout 5s xclip -selection primary -out \
								>/artifacts/selection-primary.txt \
								2>/artifacts/selection-primary.err || true
							scrot /artifacts/selection-screen.png \
								>/dev/null 2>&1 || true
							printf "window=%s\nstart=%s,%s\nend=%s,%s\n" "$window" \
								"$ITERM2_PROBE_SELECTION_START_X" \
								"$ITERM2_PROBE_SELECTION_START_Y" \
								"$ITERM2_PROBE_SELECTION_END_X" \
								"$ITERM2_PROBE_SELECTION_END_Y" \
								>/artifacts/selection-input.txt
							if [[ $ITERM2_PROBE_SELECTION_PASTE_BACK == 1 ]]; then
								xdotool type --delay 20 --clearmodifiers -- \
									"cat >/artifacts/selection-paste.txt"
								xdotool key --clearmodifiers Return
								sleep 0.25
								xdotool key --clearmodifiers super+v
								sleep 0.5
								xdotool key --clearmodifiers ctrl+d
								sleep 0.25
								xdotool key --clearmodifiers ctrl+d
							fi
						fi
						if [[ $ITERM2_PROBE_QUIT_DIALOG == 1 ]]; then
							sleep 1
							xdotool windowactivate --sync "$window"
							xdotool key --clearmodifiers super+q
							sleep 2
							if [[ $ITERM2_PROBE_QUIT_CONFIRM == 1 ]]; then
								shutdown_window=
								for ((dialog_attempt = 0; dialog_attempt < 50; ++dialog_attempt)); do
									shutdown_window=$(xwininfo -root -tree 2>/dev/null |
										awk "/510x126/ { print \$1; exit }")
									[[ -z $shutdown_window ]] || break
									sleep 0.1
								done
								if [[ -z $shutdown_window ]]; then
									echo "quit confirmation window not found" \
										>/artifacts/quit-confirmation.txt
								else
									shutdown_info=$(xwininfo -id "$shutdown_window")
									shutdown_x=$(awk "/Absolute upper-left X:/ { print \$4 }" \
										<<<"$shutdown_info")
									shutdown_y=$(awk "/Absolute upper-left Y:/ { print \$4 }" \
										<<<"$shutdown_info")
									xdotool mousemove "$((shutdown_x + 466))" \
										"$((shutdown_y + 98))"
									xdotool click 1
									app_exited=0
									for ((exit_attempt = 0; exit_attempt < 50; ++exit_attempt)); do
										if ! kill -0 "$app_pid" 2>/dev/null; then
											app_exited=1
											break
										fi
										sleep 0.1
									done
									printf "window=%s\nclick=%s,%s\napp_pid=%s\napp_exited=%s\n" \
										"$shutdown_window" "$((shutdown_x + 466))" \
										"$((shutdown_y + 98))" "$app_pid" "$app_exited" \
										>/artifacts/quit-confirmation.txt
									if [[ $ITERM2_PROBE_SHUTDOWN_PREFIX == 1 ]]; then
										launchd_pid=$(ps -eo pid=,args= | awk \
											"\$2 == \"/sbin/launchd\" { print \$1; exit }")
										shutdown_requested=0
										shutdown_status=
										server_exited=0
										if [[ $app_exited == 1 && -n $launchd_pid ]]; then
											ps -ef >/artifacts/processes-before-shutdown.txt
											set +e
											timeout 5s tee /artifacts/prefix-shutdown-request \
												<<<"shutdown" >/dev/null
											shutdown_status=$?
											set -e
											shutdown_requested=1
											for ((shutdown_attempt = 0; shutdown_attempt < 100; ++shutdown_attempt)); do
												if ! kill -0 "$server_pid" 2>/dev/null; then
													server_exited=1
													break
												fi
												sleep 0.1
												done
											ps -ef >/artifacts/processes-after-shutdown.txt
										fi
										printf "launchd_pid=%s\nshutdown_requested=%s\nshutdown_status=%s\nserver_pid=%s\nserver_exited=%s\n" \
											"$launchd_pid" "$shutdown_requested" "$shutdown_status" "$server_pid" \
											"$server_exited" >/artifacts/prefix-shutdown.txt
									fi
								fi
							fi
						fi
						sleep 1
						printf "window=%s\ntext=%s\n" "$window" \
							"$ITERM2_PROBE_TYPE_TEXT" >/artifacts/input.txt
						exit 0
					fi
					sleep 0.05
				done
				exit 1
			) &
			input_pid=$!
		fi
		attempts=$((ITERM2_PROBE_WAIT_SECONDS * 10))
		for ((attempt = 0; attempt < attempts; ++attempt)); do
			kill -0 "$server_pid" 2>/dev/null || break
			sleep 0.1
		done
		if [[ -n $input_pid ]]; then
			wait "$input_pid" || true
		fi

		if kill -0 "$server_pid" 2>/dev/null; then
			echo running >/artifacts/status.txt
		else
			set +e
			wait "$server_pid"
			status=$?
			set -e
			echo "exit:$status" >/artifacts/status.txt
			server_pid=
		fi
		xwininfo -root -tree >/artifacts/windows.txt 2>&1 || true
		awk "/^[[:space:]]*0x[0-9a-f]+/ { print \$1 }" /artifacts/windows.txt |
			sort -u |
			while read -r window_id; do
				echo "window: $window_id"
				xwininfo -id "$window_id" 2>&1 || true
			done >/artifacts/window-details.txt
		scrot /artifacts/screen.png >/dev/null 2>&1 || true
		ps -ef >/artifacts/processes.txt
		app_pid=$(ps -eo pid=,args= | awk \
			"\$2 == \"$APP_PROBE_EXECUTABLE_PATH\" { print \$1; exit }")
		if [[ -n $app_pid ]]; then
			cat "/proc/$app_pid/status" \
				>/artifacts/iterm2-final-status.txt 2>/dev/null || true
			cat "/proc/$app_pid/smaps_rollup" \
				>/artifacts/iterm2-final-smaps-rollup.txt 2>/dev/null || true
		fi
		for process in /proc/[0-9]*; do
			[[ $(cat "$process/comm" 2>/dev/null || true) == mldr ]] || continue
			pid=${process##*/}
			{
				printf "pid=%s\ncmdline=" "$pid"
				tr "\0" " " <"$process/cmdline" 2>/dev/null || true
				printf "\nstat="
				cat "$process/stat" 2>/dev/null || true
				printf "\nstatus:\n"
				cat "$process/status" 2>/dev/null || true
			} >"/artifacts/mldr-$pid.txt"
			{
				printf "pid=%s\n" "$pid"
				ls -l "$process/fd" 2>/dev/null || true
			} >"/artifacts/mldr-$pid-fds.txt"
		done
		cp /tmp/iterm.out /artifacts/darlingserver.out
		cp /tmp/iterm.err /artifacts/darlingserver.err
		cp "$prefix/tmp/launchservicesd.out" /artifacts/launchservicesd.out 2>/dev/null || true
		cp "$prefix/tmp/launchservicesd.err" /artifacts/launchservicesd.err 2>/dev/null || true
		cp "$prefix/tmp/launchctl-bootstrap.out" /artifacts/launchctl-bootstrap.out 2>/dev/null || true
		cp "$prefix/tmp/launchctl-bootstrap.err" /artifacts/launchctl-bootstrap.err 2>/dev/null || true
		cp "$prefix/private/tmp/launchctl-bootstrap.out" /artifacts/launchctl-bootstrap.out 2>/dev/null || true
		cp "$prefix/private/tmp/launchctl-bootstrap.err" /artifacts/launchctl-bootstrap.err 2>/dev/null || true
		cp "$prefix/private/var/log/com.apple.launchd/launchd-debug.system.log" \
			/artifacts/launchd-debug.log 2>/dev/null || true
		cp "$prefix/private/var/log/com.apple.launchd/launchd-shutdown.system.log" \
			/artifacts/launchd-shutdown.log 2>/dev/null || true
		cp "$prefix/private/var/log/dserver.log" /artifacts/dserver.log \
			2>/dev/null || true
		find "$prefix/private/var/log" -type f -exec cp -t /artifacts {} + \
			2>/dev/null || true
'

cat "$artifact_root/status.txt"
cat "$artifact_root/darlingserver.err"
cat "$artifact_root/darlingserver.out"
