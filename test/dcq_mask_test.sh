#!/usr/bin/env bash
# dcq .out 遮罩：HOME 底下沒有 ~/.claude/tools（雲端 clone 情境）也要遮掉憑證（2026-10-24，Grok 雲端 .out 留原文）。
# 假 dc 印一把假 key，跑完檢查 .out 只剩遮罩標記。不打上游。
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME" "$T/bin" "$T/w"
export DCQ_HOME="$T/q" DC_BIN="$T/bin" PATH="$T/bin:$PATH"
export DC_FREECHECK=off DC_NEGCTL=0 DCQ_POLL_S=1 DCQ_POOLSYNC=0
export DC_ZEN_GATE="$T/zen-gate" JEV_ZEN_STATUS_FILE="$T/jev-zen.json"
export DCQ_FREE_ROUNDS=1 DCQ_POOL_PAID="" DCQ_POOL_TAIL="" DCQ_ORDER=default
unset DCQ_MASK
# 假 key 用拼接產生，檔案本身不含 key 樣字串
export FAKEKEY="sk-or-v1-$(printf 'a1b2c3d4%.0s' 1 2 3 4)"
printf '#!/usr/bin/env bash\necho "OPENROUTER_API_KEY=$FAKEKEY"\necho "raw $FAKEKEY"\nexit 0\n' > "$T/bin/dc"
for g in deep-lint wo-verify; do printf '#!/bin/sh\nexit 0\n' > "$T/bin/$g"; done
chmod +x "$T/bin/"*
echo '# m' > "$T/m.md"
id="$("$REPO/bin/dcq" add "$T/m.md" "$T/w" easy)"
DCQ_MODELS="m1" "$REPO/bin/dcq" run -j 1 >"$T/run.out" 2>&1
fail=0
outs="$(ls "$DCQ_HOME"/logs/"$id".*.out 2>/dev/null)"
[ -n "$outs" ] || { echo "FAIL 沒有 .out"; fail=1; }
if [ -n "$outs" ] && grep -q "$FAKEKEY" $outs; then echo "FAIL .out 留著原文 key"; fail=1; else echo "PASS .out 沒有原文 key"; fi
if [ -n "$outs" ] && grep -q 'MASKED' $outs; then echo "PASS .out 有遮罩標記"; else echo "FAIL .out 沒有遮罩標記"; fail=1; fi
if grep -q '遮罩失敗' "$T/run.out"; then echo "FAIL 遮罩失敗警告：$(grep 遮罩失敗 "$T/run.out")"; fail=1; else echo "PASS 沒有遮罩失敗警告"; fi
[ "$fail" = 0 ] || { echo "--- run.out ---"; cat "$T/run.out"; }
exit $fail
