#!/usr/bin/env bash
# oc-free-check 通知判準自檢：假 TSV 歷史 + 假 hpush，不起 opencode server。
# 斷言加白語意：FAIL 立刻喊掛；單一模型第一次逾時不吵；連兩批逾時才喊掛；
# 多個模型同時由 OK 轉逾時只報共因，不列名說掛了；額度用完／限流不算掛；下架另報。
set -u
cd "$(dirname "$0")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
cat > "$T/bin/hpush" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HPUSH_LOG"
EOF
chmod +x "$T/bin/hpush"
export PATH="$T/bin:$PATH"

fail=0
chk() { # name tsv_history results_py want_grep
  local log="$T/push.log" tsv="$T/probe.tsv"
  : > "$log"; printf '%s' "$2" > "$tsv"
  HPUSH_LOG="$log" python3 - "$tsv" "$3" <<'PY' || { echo "FAIL $1: 腳本錯誤"; fail=1; return; }
import importlib.util, sys, ast
spec = importlib.util.spec_from_loader("ofc", importlib.machinery.SourceFileLoader("ofc", "bin/oc-free-check"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.append_tsv(sys.argv[1], ast.literal_eval(sys.argv[2]))
PY
  if grep -q "$4" "$log"; then echo "PASS $1"; else echo "FAIL $1: 推播=[$(tr '\n' '|' < "$log")] 想要符合 $4"; fail=1; fi
}

H1=$'2026-10-09_00:00:00\topencode\tm1\tOK\t2.0\n2026-10-10_00:00:00\topencode\tm1\tOK\t2.0\n'
chk "FAIL 立刻喊掛" "$H1" "[('opencode','m1','FAIL','HTTP 404',0.0)]" "免費模型掛了"

# 第一次逾時：只有一個模型，不該有任何推播
log="$T/push.log"; : > "$log"; printf '%s' "$H1" > "$T/probe.tsv"
HPUSH_LOG="$log" python3 - "$T/probe.tsv" "[('opencode','m1','TIMEOUT','逾時 60s',60.0)]" <<'PY'
import importlib.util, importlib.machinery, sys, ast
spec = importlib.util.spec_from_loader("ofc", importlib.machinery.SourceFileLoader("ofc", "bin/oc-free-check"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.append_tsv(sys.argv[1], ast.literal_eval(sys.argv[2]))
PY
if [ -s "$log" ]; then echo "FAIL 單一模型第一次逾時不吵: [$(cat "$log")]"; fail=1; else echo "PASS 單一模型第一次逾時不吵"; fi

H2=$'2026-10-09_00:00:00\topencode\tm1\tOK\t2.0\n2026-10-10_00:00:00\topencode\tm1\tTIMEOUT\t60.0\t逾時 60s\n'
chk "連兩批逾時才喊掛" "$H2" "[('opencode','m1','TIMEOUT','逾時 60s',60.0)]" "連兩批不回應"

H3=$'2026-10-10_00:00:00\topencode\tm1\tOK\t2.0\n2026-10-10_00:00:00\topencode\tm2\tOK\t2.0\n2026-10-10_00:00:00\topencode\tm3\tOK\t2.0\n'
R3="[('opencode','m1','TIMEOUT','逾時 60s',60.0),('opencode','m2','TIMEOUT','逾時 60s',60.0),('opencode','m3','TIMEOUT','逾時 60s',60.0)]"
chk "多個同時逾時報共因" "$H3" "$R3" "探測整體變慢"
log="$T/push.log"; if grep -q "免費模型掛了" "$log"; then echo "FAIL 共因時不該喊掛了"; fail=1; else echo "PASS 共因時不喊掛了"; fi

R4="[('opencode','m1','QUOTA','Free usage exceeded（10-11 08:00 重置）',1.0)]"
chk "額度用完報額度" "$H1" "$R4" "額度用完"
if grep -q "掛了" "$T/push.log"; then echo "FAIL 額度用完不該喊掛了"; fail=1; else echo "PASS 額度用完不喊掛了"; fi

chk "OK 轉 GONE 報下架" "$H1" "[('opencode','m1','GONE','deprecated',0.0)]" "已下架"

# 限流分類：opencode 重試狀態要能直接判成 QUOTA／RATELIMIT，不能等到逾時
python3 - <<'PY' && echo "PASS 重試原因分類" || { echo "FAIL 重試原因分類"; fail=1; }
import importlib.util, importlib.machinery
spec = importlib.util.spec_from_loader("ofc", importlib.machinery.SourceFileLoader("ofc", "bin/oc-free-check"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.classify_retry({"message": "Free usage exceeded", "action": {"reason": "free_tier_limit"}, "next": 1791676801031})[0] == "QUOTA"
assert m.classify_retry({"message": "Rate limit exceeded. Please try again later."})[0] == "RATELIMIT"
assert m.classify_retry({"message": "Upstream request failed: Model is unavailable."})[0] is None
PY

chk "官方新上架報一次" "$H1" "[('opencode','m9-free','NOCLIENT','x',0.0)]" "新上架"

# 官方清單併入：快取有但官方沒有→GONE；官方有但快取沒有→NOCLIENT；deprecated 仍 GONE
printf '%s' '{"opencode":{"models":{"a-free":{"cost":{"input":0,"output":0}},"b-free":{"cost":{"input":0,"output":0}},"c-free":{"status":"deprecated","cost":{"input":0,"output":0}},"paid":{"cost":{"input":1,"output":1}}}}}' > "$T/models.json"
MODELS_JSON="$T/models.json" python3 - <<'PY' && echo "PASS 官方清單併入分類" || { echo "FAIL 官方清單併入分類"; fail=1; }
import importlib.util, importlib.machinery
spec = importlib.util.spec_from_loader("ofc", importlib.machinery.SourceFileLoader("ofc", "bin/oc-free-check"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
got = {mid: st for _p, mid, st in m.free_models(["opencode"], "", {"a-free", "c-free", "new-free", "paid"})}
assert got == {"a-free": None, "b-free": "GONE", "c-free": "GONE", "new-free": "NOCLIENT"}, got
got = {mid: st for _p, mid, st in m.free_models(["opencode"], "", None)}
assert got == {"a-free": None, "b-free": None, "c-free": "GONE"}, got
PY

# reason 要進第 6 欄，否則事後查不出真因
if awk -F'\t' 'NF>=6 && $4=="NOCLIENT" && $6=="x" {ok=1} END{exit !ok}' "$T/probe.tsv"; then
  echo "PASS 原因寫進第 6 欄"
else
  echo "FAIL 原因沒寫進第 6 欄"; fail=1
fi
exit $fail
