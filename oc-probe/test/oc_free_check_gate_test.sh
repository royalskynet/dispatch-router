#!/bin/bash
# 10-18：被封期間 oc-free-check 跳過整輪卻只印 stdout，18h 無警報。跳過時必須 hpush。
set -eu
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\necho "$1" >> %s/pushed\n' "$T" > "$T/hpush"; chmod +x "$T/hpush"
echo $(( $(date +%s) + 3600 )) > "$T/gate"
PATH="$T:$PATH" DC_ZEN_GATE="$T/gate" JEV_ZEN_STATUS_FILE="$T/jev.json" "$(dirname "$0")/../bin/oc-free-check" > "$T/out"
grep -q "本輪不探測" "$T/out" || { echo "FAIL: 沒走跳過分支"; cat "$T/out"; exit 1; }
grep -q "dr 免費池" "$T/pushed" 2>/dev/null || { echo "FAIL: 跳過卻沒 hpush"; exit 1; }
echo "oc_free_check_gate OK"
