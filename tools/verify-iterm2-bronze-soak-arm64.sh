#!/usr/bin/env bash
set -euo pipefail

source_root=$(cd "$(dirname "$0")/.." && pwd)
workspace_root=$(cd "$source_root/.." && pwd)
duration=${ITERM2_SOAK_SECONDS:-1800}
interval=${ITERM2_SOAK_INTERVAL:-10}
artifact_root=${ITERM2_SOAK_ARTIFACTS:-$workspace_root/artifacts/stage18-iterm2-bronze-soak}
bundle=${ITERM2_BUNDLE:-$workspace_root/downloads/iterm2/3.6.11/reference/iTerm.app}
expected_hash=42824bb06b3106f5cdc8a831848a0fd0cd58da8938435035a053bcab5a83d240

[[ $duration =~ ^[1-9][0-9]*$ && $interval =~ ^[1-9][0-9]*$ ]] || {
	echo "ITERM2_SOAK_SECONDS and ITERM2_SOAK_INTERVAL must be positive integers." >&2
	exit 2
}
case "$artifact_root" in "$workspace_root"/*) ;; *)
	echo "Soak artifacts must remain below $workspace_root." >&2
	exit 2
esac

actual_hash=$(sha256sum "$bundle/Contents/MacOS/iTerm2" | awk '{print $1}')
[[ $actual_hash == "$expected_hash" ]] || {
	echo "Official iTerm2 executable checksum mismatch." >&2
	exit 1
}

env \
	ITERM2_PROBE_ARTIFACTS="$artifact_root" \
	ITERM2_PROBE_WAIT_SECONDS="$((duration + 60))" \
	ITERM2_PROBE_SHARED_CACHE=1 \
	ITERM2_PROBE_PREFER_DISK_FRAMEWORKS=1 \
	ITERM2_PROBE_FULL_LAUNCHD=1 \
	ITERM2_PROBE_APPKIT_BOOTSTRAP=1 \
	ITERM2_PROBE_APPKIT_REOPEN=1 \
	ITERM2_PROBE_DISABLE_LOCALE_DISCOVERY=1 \
	ITERM2_PROBE_DIRECT_PTY=1 \
	ITERM2_PROBE_STABLE_KEYBOARD_SOURCE=1 \
	ITERM2_PROBE_OPAQUE_TEXT=1 \
	ITERM2_PROBE_DISABLE_METAL=1 \
	ITERM2_PROBE_TYPE_TEXT="printf 'SOAK_START\\n'" \
	ITERM2_PROBE_SOAK_SECONDS="$duration" \
	ITERM2_PROBE_SOAK_INTERVAL="$interval" \
	ITERM2_PROBE_QUIT_DIALOG=1 \
	ITERM2_PROBE_QUIT_CONFIRM=1 \
	ITERM2_PROBE_SHUTDOWN_PREFIX=1 \
	ITERM2_PROBE_APPLE_LSD=0 \
	ITERM2_PROBE_APPLE_MDS=0 \
	"$source_root/tools/probe-iterm2-launch-arm64.sh" >/tmp/iterm2-bronze-soak.log

value() {
	local key=$1 file=$2
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$file"
}

summary=$artifact_root/soak-summary.txt
[[ -f $summary ]] || { echo "Missing soak summary." >&2; exit 1; }
elapsed=$(value elapsed_seconds "$summary")
iterations=$(value iterations "$summary")
[[ $(value requested_seconds "$summary") == "$duration" ]]
[[ $(value completed "$summary") == 1 ]]
[[ $(value failure "$summary") == none ]]
[[ $(value session_exited "$summary") == 1 ]]
(( elapsed >= duration ))
(( iterations > 0 ))
[[ $(cat "$artifact_root/status.txt") == exit:0 ]]
[[ $(value app_exited "$artifact_root/quit-confirmation.txt") == 1 ]]
[[ $(value shutdown_status "$artifact_root/prefix-shutdown.txt") == 0 ]]
[[ $(value server_exited "$artifact_root/prefix-shutdown.txt") == 1 ]]

mapfile -t status_files < <(find "$artifact_root" -maxdepth 1 \
	-type f -name 'soak-status-[0-9][0-9][0-9][0-9].txt' | sort)
[[ ${#status_files[@]} -eq $iterations ]] || {
	echo "Expected $iterations exit-status samples, found ${#status_files[@]}." >&2
	exit 1
}
for file in "${status_files[@]}"; do
	[[ $(cat "$file") == 37 && $(wc -c <"$file") -eq 3 ]] || {
		echo "Incorrect foreground exit status in $file." >&2
		exit 1
	}
done

mapfile -t paste_files < <(find "$artifact_root" -maxdepth 1 \
	-type f -name 'soak-paste-[0-9][0-9][0-9][0-9].txt' | sort)
expected_pastes=$((iterations / 12))
[[ ${#paste_files[@]} -eq $expected_pastes ]] || {
	echo "Expected $expected_pastes clipboard samples, found ${#paste_files[@]}." >&2
	exit 1
}
for file in "${paste_files[@]}"; do
	id=${file##*-}
	id=${id%.txt}
	[[ $(cat "$file") == "SOAK_PASTE_$id" ]] || {
		echo "Incorrect clipboard payload in $file." >&2
		exit 1
	}
done

mapfile -t smaps_files < <(find "$artifact_root" -maxdepth 1 \
	-type f -name 'soak-smaps-[0-9][0-9][0-9][0-9].txt' | sort)
[[ ${#smaps_files[@]} -eq $iterations ]]
first_rss=$(awk '/^Rss:/ { print $2; exit }' "${smaps_files[0]}")
max_rss=$first_rss
for file in "${smaps_files[@]}"; do
	rss=$(awk '/^Rss:/ { print $2; exit }' "$file")
	(( rss > max_rss )) && max_rss=$rss
done
rss_growth_kib=$((max_rss - first_rss))
(( rss_growth_kib <= 524288 )) || {
	echo "Soak RSS grew by $rss_growth_kib KiB; limit is 524288 KiB." >&2
	exit 1
}

mapfile -t stat_files < <(find "$artifact_root" -maxdepth 1 \
	-type f -name 'soak-stat-[0-9][0-9][0-9][0-9].txt' | sort)
[[ ${#stat_files[@]} -eq $iterations ]]
first_ticks=$(awk '{ print $14 + $15 }' "${stat_files[0]}")
last_ticks=$(awk '{ print $14 + $15 }' "${stat_files[-1]}")
cpu_ticks=$((last_ticks - first_ticks))
clock_ticks=$(getconf CLK_TCK)
(( cpu_ticks * 100 <= elapsed * clock_ticks * 75 )) || {
	echo "iTerm2 used $cpu_ticks CPU ticks during a ${elapsed}s soak; busy-loop ceiling exceeded." >&2
	exit 1
}

if find "$artifact_root" -maxdepth 1 -name 'mldr-[0-9]*.txt' -print -quit | grep -q .; then
	echo "A Mach-O process remained after prefix shutdown." >&2
	exit 1
fi
if rg -i -q 'uncaught exception|segmentation fault|trace/bpt trap' \
	"$artifact_root/iterm2-job.err" "$artifact_root/darlingserver.err"; then
	echo "Fatal runtime diagnostic found in soak logs." >&2
	exit 1
fi

cat >"$artifact_root/verification.txt" <<EOF
duration_seconds=$elapsed
iterations=$iterations
clipboard_round_trips=$expected_pastes
first_rss_kib=$first_rss
max_rss_kib=$max_rss
rss_growth_kib=$rss_growth_kib
cpu_ticks=$cpu_ticks
clock_ticks_per_second=$clock_ticks
iterm2_sha256=$actual_hash
EOF

echo "iTerm2 Bronze soak passed: ${elapsed}s, $iterations iterations, $expected_pastes clipboard round trips"
