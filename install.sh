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
cp "$REPO/launchd/com.host.dcq-probe.plist" ~/Library/LaunchAgents/
launchctl bootout gui/$(id -u)/com.host.dcq-probe 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.host.dcq-probe.plist

# ~/.claude/skills/dr：若已是實體目錄（非 symlink），先備份進 repo 再連結
if [ -d ~/.claude/skills/dr ] && [ ! -L ~/.claude/skills/dr ]; then
  mkdir -p "$REPO/.bak"
  mv ~/.claude/skills/dr "$REPO/.bak/dr-$(date +%Y%m%d-%H%M%S)"
fi
ln -sfn "$REPO/skills/dr" ~/.claude/skills/dr
[ -L ~/.claude/skills/dc ] && rm ~/.claude/skills/dc  # 10-16 前舊名

echo "Installed symlinks:"
for t in ~/.local/bin/dc ~/.local/bin/dcq ~/.local/bin/oc-free-check ~/.local/bin/wo-verify ~/.claude/skills/dr; do
  ls -l "$t"
  [ -e "$t" ] || { echo "DANGLING: $t"; exit 1; }
done

echo
# wo-verify／deep-lint 已收進 bin/，dc 直接用同目錄那份，不依賴 deepclaude／deep-agent。
for g in wo-verify deep-lint; do
  [ -x "$REPO/bin/$g" ] || { echo "MISSING: $REPO/bin/$g"; exit 1; }
done
echo "  wo-verify／deep-lint：repo 自帶（bin/）"
