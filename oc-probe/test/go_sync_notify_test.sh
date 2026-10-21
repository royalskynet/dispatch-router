#!/usr/bin/env bash
# go-sync 推播閘：state 指到暫存（測試、手動試跑）不推真 TG；正式路徑或 DC_PUSH=1 才推。
# 直接載入模組呼叫 notify()，不連網、不跑週掃。
set -u
cd "$(dirname "$0")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/pushed"\n' "$T" > "$T/bin/hpush"; chmod +x "$T/bin/hpush"
export PATH="$T/bin:$PATH"

fail=0
push() { # 在給定 env 下呼叫一次 notify，回推播行數
  rm -f "$T/pushed"
  env "$@" python3 - <<'PY'
import importlib.util, importlib.machinery
spec = importlib.util.spec_from_loader("gs", importlib.machinery.SourceFileLoader("gs", "bin/go-sync"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.notify("測試")
PY
  if [ -f "$T/pushed" ]; then wc -l < "$T/pushed" | tr -d ' '; else echo 0; fi
}
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got=[$2] want=[$3]"; fail=1; fi; }

chk "暫存 state 不推"          "$(push HOME="$T/home" DCQ_GO_STATE="$T/go.json")" "0"
chk "暫存 state＋DC_PUSH=1 推" "$(push HOME="$T/home" DCQ_GO_STATE="$T/go.json" DC_PUSH=1)" "1"
chk "正式 state（預設路徑）推"  "$(push HOME="$T/home")" "1"
exit "$fail"
