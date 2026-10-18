#!/usr/bin/env bash
# install.sh 的 skill 段：把 dr 連結到每個 agent 客戶端目錄、重跑冪等、清掉舊名 dc 連結、實體目錄先備份。
# 只截出 skill 段執行，不碰 ~/.local/bin 與 launchd；HOME 指向暫存目錄。用法：./test/install_skill_test.sh
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/skills/dr" "$T/.agents/skills"
ln -s /nonexistent "$T/.agents/skills/dc"
SEG="$T/skill-seg.sh"
sed -n '/skill 安裝到各 agent/,/^done$/p' "$REPO/install.sh" > "$SEG"
[ -s "$SEG" ] || { echo "FAIL 找不到 install.sh 的 skill 段"; exit 1; }
run() { HOME="$T" REPO="$REPO" bash -c 'set -e; '"$(cat "$SEG")"; }
run || { echo "FAIL 第一次執行"; exit 1; }
run || { echo "FAIL 第二次執行（不冪等）"; exit 1; }
fail=0
[ -L "$T/.claude/skills/dr" ] || { echo "FAIL ~/.claude/skills/dr 未建立"; fail=1; }
[ -L "$T/.agents/skills/dr" ] || { echo "FAIL ~/.agents/skills/dr 未建立"; fail=1; }
[ "$(readlink "$T/.agents/skills/dr")" = "$REPO/skills/dr" ] || { echo "FAIL 連結指向錯"; fail=1; }
{ [ ! -e "$T/.agents/skills/dc" ] && [ ! -L "$T/.agents/skills/dc" ]; } || { echo "FAIL 舊名 dc 連結未清"; fail=1; }
ls -d "$REPO"/.bak/dr-skills-* >/dev/null 2>&1 || { echo "FAIL 實體目錄未備份"; fail=1; }
rm -rf "$REPO"/.bak/dr-skills-*   # 測試產物不留在 repo
echo "install_skill_test: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
