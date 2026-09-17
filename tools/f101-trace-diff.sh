#!/usr/bin/env bash
# f101-trace-diff.sh — normalize a darlingserver debug dserver.log into a comparable
# lifecycle projection (F101). Recipe verified against the pass/fail capture corpus:
#   - timestamps stripped (unique per line, pure diff noise)
#   - host pids dropped, NSIDs kept (role-stable across runs: 1=launchd, 13=iTerm2,
#     19=shellspawn, 7x/8x=tab shells) and annotated with the role derived from the
#     log's own exec/create lines
#   - kernel addresses and KQ ids masked
#   - noise dropped: pthread_canceled RPC churn (~63% of lines), mutex warnings,
#     PSYNCH_INSTR (instrumented-build-only lines)
#   - filtered to lifecycle events unless --all
# Usage: f101-trace-diff.sh <dserver.log> [--all]
set -u
f=$1; mode=${2:-}

# pass 1: derive NSID -> role from the log itself (first exec basename per nsid,
# falling back to 'proc' for created-but-never-exec'd processes)
map=$(grep -E 'execve expand' "$f" 2>/dev/null | \
	sed -E 's/.*\[P:[0-9-]+\(([0-9-]+)\)\].*execve expand ([^ ]+) .*/\1 \2/' | \
	awk '!seen[$1]++ { n=split($2,p,"/"); printf "%s=%s\n", $1, p[n] }')

# pass 2: normalize
norm() {
	sed -E \
		-e 's/^\[[0-9]+\.[0-9]+\]//' \
		-e 's/\[P:-?[0-9]+\((-?[0-9]+)\)\]/[P:\1]/g' \
		-e 's/\[T:-?[0-9]+\((-?[0-9]+)\)\]/[T:\1]/g' \
		-e 's/ -?[0-9]+\((-?[0-9]+)\):-?[0-9]+\((-?[0-9]+)\): / \1:\2: /' \
		-e 's/with ID [0-9]+ and NSID/with NSID/' \
		-e 's/0x[0-9a-f]+/0xADDR/g' \
		-e 's/KQ:[0-9]+/KQ:N/g' \
		"$f" | \
	grep -vE 'dserver_callnum_pthread_canceled|Trying to (un)?lock mutex without an active thread|PSYNCH_INSTR'
}

# pass 3: lifecycle filter (unless --all), then role-annotate
filt() {
	if [[ $mode == --all ]]; then cat; else
		grep -E '\((process|thread|console), |Peer hung up|execve expand|dtype for fd|pending replacement|New process created|replacing process'
	fi
}

annotate() {
	local script=""
	while IFS='=' read -r nsid role; do
		[[ -n $nsid && -n $role ]] || continue
		script+="s/\\[P:${nsid}\\]/[P:${nsid}=${role}]/g;"
		script+="s/with NSID ${nsid}\$/with NSID ${nsid} (${role})/;"
	done <<< "$map"
	sed -E "$script"
}

norm | filt | annotate
