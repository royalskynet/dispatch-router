#!/usr/bin/env bash
# oc-probe daily（2026-10-24 起）：不排程實打探測，不論 stamp 多舊都不呼叫 oc-free-check。
# 每天跑 dcq rescan（零 token 清單掃）、go-sync（它自己有週閘）與選配 hook；hook 不存在就略過。
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/stub" "$T/home/.dcq/logs" "$T/home/.config/oc-probe"
cp "$REPO/bin/oc-probe" "$T/bin/"
cat > "$T/bin/oc-free-check" <<'S'
#!/usr/bin/env bash
if [ "$1" = "--x-only" ]; then echo X_READ >> "$CALLS"; else echo PROBE >> "$CALLS"; fi
S
printf '#!/usr/bin/env bash\necho GOSYNC >> "$CALLS"\n' > "$T/bin/go-sync"
printf '#!/usr/bin/env bash\necho "DCQ_$1" >> "$CALLS"\n' > "$T/stub/dcq"
printf '#!/usr/bin/env bash\nexit "${GATE_RC:-0}"\n' > "$T/stub/zen-gate"
printf '#!/usr/bin/env bash\necho HOOK >> "$CALLS"\n' > "$T/home/.config/oc-probe/hook"
chmod +x "$T/bin/"* "$T/stub/"* "$T/home/.config/oc-probe/hook"
run() { : > "$T/calls"; HOME="$T/home" CALLS="$T/calls" DCQ_BIN="$T/stub/dcq" PATH="$T/stub:$PATH" \
  "$T/bin/oc-probe" daily >/dev/null; tr '\n' ' ' < "$T/calls"; }
STAMP="$T/home/.dcq/logs/oc-probe.last"
for age in 2 8 30; do
  echo $(( $(date +%s) - age * 86400 )) > "$STAMP"
  [ "$(run)" = "DCQ_rescan GOSYNC HOOK " ] || { echo "FAIL: ${age} 天前探測過，也不該實打：$(run)"; exit 1; }
done
rm "$T/home/.config/oc-probe/hook"
[ "$(run)" = "DCQ_rescan GOSYNC " ] || { echo "FAIL: 沒裝 hook 應略過：$(run)"; exit 1; }
echo "PASS oc_probe_schedule_test"
