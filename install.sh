#!/usr/bin/env bash
# 把 dispatch-router 裝到使用者路徑。無 admin 需求，全部 user-level。
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

mkdir -p ~/.local/bin ~/.claude/skills

ln -sfn "$REPO/bin/dc" ~/.local/bin/dc
ln -sfn "$REPO/bin/dcq" ~/.local/bin/dcq
ln -sfn "$REPO/bin/oc-free-check" ~/.local/bin/oc-free-check
# 每日 06:00 探測免費模型（dcq rank 讀 ~/.dcq/logs/probe.tsv）
cp "$REPO/launchd/com.host.dcq-probe.plist" ~/Library/LaunchAgents/
launchctl bootout gui/$(id -u)/com.host.dcq-probe 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.host.dcq-probe.plist

# ~/.claude/skills/dc：若已是實體目錄（非 symlink），先備份進 repo 再連結
if [ -d ~/.claude/skills/dc ] && [ ! -L ~/.claude/skills/dc ]; then
  mkdir -p "$REPO/.bak"
  mv ~/.claude/skills/dc "$REPO/.bak/dc-$(date +%Y%m%d-%H%M%S)"
fi
ln -sfn "$REPO/skills/dc" ~/.claude/skills/dc

echo "Installed symlinks:"
for t in ~/.local/bin/dc ~/.local/bin/dcq ~/.local/bin/oc-free-check ~/.claude/skills/dc; do
  ls -l "$t"
  [ -e "$t" ] || { echo "DANGLING: $t"; exit 1; }
done

echo
echo "相依：wo-verify 與 deep-lint（來自 deep-agent，需在 PATH 或設 DC_BIN）。"
if command -v wo-verify >/dev/null; then echo "  wo-verify  ok"; else echo "  wo-verify  缺 — 先跑 deep-agent/install.sh"; fi
if command -v deep-lint >/dev/null; then echo "  deep-lint  ok"; else echo "  deep-lint  缺 — 先跑 deep-agent/install.sh"; fi
