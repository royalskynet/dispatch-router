#!/usr/bin/env bash
# 把 dispatch-router 裝到使用者路徑。無 admin 需求，全部 user-level。
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.local/bin ~/.claude/skills

ln -sfn "$REPO/bin/dc" ~/.local/bin/dc
ln -sfn "$REPO/bin/dcq" ~/.local/bin/dcq
ln -sfn "$REPO/bin/oc-free-check" ~/.local/bin/oc-free-check
# PATH 上的 wo-verify 也由本 repo 提供（手動驗收、其他腳本用）；dc 自己不走 PATH
ln -sfn "$REPO/bin/wo-verify" ~/.local/bin/wo-verify
# 每日 06:00 探測免費模型（dcq rank 讀 ~/.dcq/logs/probe.tsv）
# plist 在 repo 內用 /Users/you 佔位（不寫死某台機器的家目錄），裝機時代換成 $HOME。
mkdir -p ~/Library/LaunchAgents ~/.dcq/logs
sed "s#/Users/you#$HOME#g" "$REPO/launchd/local.dispatch-router.dcq-probe.plist" \
  > ~/Library/LaunchAgents/local.dispatch-router.dcq-probe.plist
# bootout 是非同步：緊接 bootstrap 會撞上仍在卸載的舊 job（Bootstrap failed: 5）。
# 先等 job 真的消失再掛，最多等 5 秒；仍失敗則 plist 已就位，下次登入會自動載入。
launchctl bootout gui/$(id -u)/local.dispatch-router.dcq-probe 2>/dev/null || true
for _i in 1 2 3 4 5 6 7 8 9 10; do
  launchctl print gui/$(id -u)/local.dispatch-router.dcq-probe >/dev/null 2>&1 || break
  sleep 0.5
done
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.dispatch-router.dcq-probe.plist 2>/dev/null \
  || echo "WARN: launchd job 未掛上，plist 已就位，下次登入生效" >&2
# 10-17 前舊 label
for _o in ~/Library/LaunchAgents/com.*.dcq-probe.plist; do
  [ -f "$_o" ] || continue
  launchctl bootout gui/$(id -u) "$_o" 2>/dev/null || true; rm -f "$_o"
done

# skill 安裝到各 agent 客戶端的 skills 目錄（可重複執行、冪等）：
#   ~/.claude/skills/dr  Claude Code（正本位置）
#   ~/.agents/skills/dr  讀 ~/.agents/skills 的其他 agent
#   ~/.codex/skills/dr   Codex CLI
# DR_SKILL_HOME 可覆寫（測試注入暫存 HOME 用），多個目錄以空白分隔。
# 若某處已是實體目錄（非 symlink），先備份進 repo 再連結。
SKILL_DIRS="${DR_SKILL_HOME:-$HOME/.claude/skills $HOME/.agents/skills $HOME/.codex/skills}"
SKILL_DIRS="$(printf '%s\n' $SKILL_DIRS | while read -r _p; do echo "${_p/#\~/$HOME}"; done | tr '\n' ' ')"
for _d in $SKILL_DIRS; do
  mkdir -p "$_d"
  if [ -d "$_d/dr" ] && [ ! -L "$_d/dr" ]; then
    mkdir -p "$REPO/.bak"
    mv "$_d/dr" "$REPO/.bak/dr-$(basename "$_d")-$(date +%Y%m%d-%H%M%S)"
  fi
  ln -sfn "$REPO/skills/dr" "$_d/dr"
  [ -L "$_d/dc" ] && rm "$_d/dc"  # 10-16 前舊名（放在最後時 false 會讓 set -e 中斷整個安裝）
  :
  :
done

echo "Installed symlinks:"
for t in ~/.local/bin/dc ~/.local/bin/dcq ~/.local/bin/oc-free-check ~/.local/bin/wo-verify; do
  ls -l "$t"
  [ -e "$t" ] || { echo "DANGLING: $t"; exit 1; }
done
for _d in $SKILL_DIRS; do
  t="$_d/dr"
  ls -l "$t"
  [ -e "$t" ] || { echo "DANGLING: $t"; exit 1; }
done

echo
# wo-verify／deep-lint 已收進 bin/，dc 直接用同目錄那份，不依賴 deepclaude／deep-agent。
for g in wo-verify deep-lint; do
  [ -x "$REPO/bin/$g" ] || { echo "MISSING: $REPO/bin/$g"; exit 1; }
done
echo "  wo-verify／deep-lint：repo 自帶（bin/）"
