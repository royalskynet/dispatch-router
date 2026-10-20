#!/usr/bin/env bash
# oc-probe daily：未滿 7 天不探測；滿 7 天且閘外才探測並寫 stamp；閘內不探測、不寫 stamp。
# 每天都跑 go-sync（它自己有週閘）與選配 hook；hook 不存在就略過；daily 不讀推文（推文由 oc-probe x 負責）。
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
printf '#!/usr/bin/env bash\necho CATALOG >> "$CALLS"\n' > "$T/stub/dcq"
printf '#!/usr/bin/env bash\nexit "${GATE_RC:-0}"\n' > "$T/stub/zen-gate"
printf '#!/usr/bin/env bash\necho HOOK >> "$CALLS"\n' > "$T/home/.config/oc-probe/hook"
chmod +x "$T/bin/"* "$T/stub/"* "$T/home/.config/oc-probe/hook"
run() { : > "$T/calls"; HOME="$T/home" CALLS="$T/calls" DCQ_BIN="$T/stub/dcq" PATH="$T/stub:$PATH" \
  "$T/bin/oc-probe" daily >/dev/null; tr '\n' ' ' < "$T/calls"; }
STAMP="$T/home/.dcq/logs/oc-probe.last"

echo $(( $(date +%s) - 2 * 86400 )) > "$STAMP"
[ "$(run)" = "GOSYNC HOOK " ] || { echo "FAIL: 2 天前探測過，應只跑 go-sync＋hook：$(run)"; exit 1; }

echo $(( $(date +%s) - 7 * 86400 + 1800 )) > "$STAMP"
[ "$(run)" = "PROBE CATALOG GOSYNC HOOK " ] || { echo "FAIL: 7 天差半小時應探測：$(run)"; exit 1; }
[ $(( $(date +%s) - $(cat "$STAMP") )) -lt 60 ] || { echo "FAIL: 探測後沒更新 stamp"; exit 1; }

old=$(( $(date +%s) - 8 * 86400 )); echo $old > "$STAMP"
out="$(GATE_RC=1 run)"
[ "$out" = "GOSYNC HOOK " ] || { echo "FAIL: 閘內不該探測：$out"; exit 1; }
[ "$(cat "$STAMP")" = "$old" ] || { echo "FAIL: 閘內不該寫 stamp"; exit 1; }

rm "$T/home/.config/oc-probe/hook"; echo $(( $(date +%s) - 2 * 86400 )) > "$STAMP"
[ "$(run)" = "GOSYNC " ] || { echo "FAIL: 沒裝 hook 應略過：$(run)"; exit 1; }
echo "PASS oc_probe_schedule_test"
