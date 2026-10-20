#!/usr/bin/env bash
# oc-probe（dr 選配）使用者層安裝：指令連到 ~/.local/bin，註冊每日（06:00）與推文（每 4 小時）兩個 launchd job。
# 先裝 dr 本體（../install.sh，提供 dcq／zen-gate）。只支援 macOS launchd。
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.local/bin ~/.dcq/logs ~/Library/LaunchAgents
for b in oc-probe oc-free-check go-sync; do ln -sfn "$REPO/bin/$b" ~/.local/bin/$b; done
command -v zen-gate >/dev/null || [ -x ~/.local/bin/zen-gate ] || { echo "缺 zen-gate：先跑 dr 的 install.sh"; exit 1; }

for L in local.opencode-probe local.opencode-probe.x; do
  sed "s#__HOME__#$HOME#g" "$REPO/launchd/$L.plist" > ~/Library/LaunchAgents/$L.plist
  launchctl bootout gui/$(id -u)/$L 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$L.plist
done
echo "oc-probe 已裝：$(launchctl list | grep -c 'local.opencode-probe') 個 launchd job"
