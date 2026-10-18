#!/usr/bin/env bash
# 驗收：install.sh 的 plist 段把 /Users/you 代換成 $HOME，產出檔不殘留佔位、可用 plutil 解析。
# 用法：./test/plist_install_test.sh
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/Library/LaunchAgents" "$T/.dcq/logs"
SEG="$T/plist-seg.sh"
sed -n '/# 每日 06:00 探測免費模型/,/local.dispatch-router.dcq-probe.plist$/p' "$REPO/install.sh" | sed '/^launchctl /d' > "$SEG"
HOME="$T" REPO="$REPO" bash -c 'set -e; '"$(cat "$SEG")"
OUT="$T/Library/LaunchAgents/local.dispatch-router.dcq-probe.plist"
fail=0
[ -f "$OUT" ] || { echo "FAIL 未產出 plist"; exit 1; }
! /usr/bin/grep -q "/Users/you" "$OUT" || { echo "FAIL 仍有 /Users/you 佔位"; fail=1; }
/usr/bin/grep -q "$T/.local/bin/oc-free-check" "$OUT" || { echo "FAIL 路徑未代換"; fail=1; }
plutil -lint "$OUT" >/dev/null || { echo "FAIL plist 格式錯"; fail=1; }
echo "plist_install_test: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
