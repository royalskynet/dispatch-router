#!/usr/bin/env bash
# dc 的上游提早結束自檢：opencode 碰到上游不可用／限流／啟動卡住時會自己久等或重試，
# dc 要在幾秒內以 rc=1 結束（dcq 才會換模型），而且不能跑驗收。正常開工的不可被誤殺。
# 假 opencode 照真實 log 格式吐一行 ERROR 後 sleep，模擬它在程序內重試。
set -u
DC="$(cd "$(dirname "$0")/.." && pwd)/bin/dc"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/w" "$T/cfg/opencode"
export DC_BIN="$T/bin" PATH="$T/bin:$PATH"
export DCQ_HOME="$T/q" XDG_CONFIG_HOME="$T/cfg"
# DC_NEGCTL=0：這些測試的 wo-verify 是 `exit 0` 的假貨，do-nothing 對照會當場中止派工。
# 負向對照本身由 dc_verify_gate_test.sh 驗。
export DC_FREECHECK=off DC_NO_TIMEOUT_WARN=1 DC_NEGCTL=0
export VERIFIED="$T/verified"

cat > "$T/bin/opencode" <<'X'
#!/usr/bin/env bash
[ "$1" = debug ] && { echo '{}'; exit 0; }
e='timestamp=2026-10-11T02:48:47.936Z level=ERROR run=b4472e2a message="stream error" providerID=opencode modelID=x session.id=ses_x small=false agent=build mode=primary error.error="AI_APICallError:'
case "$FAKE" in
  unavail)  echo '> build · x'; echo "$e Upstream request failed: Model is unavailable.\""; sleep 30 ;;
  endpoint) echo '> build · x'; echo "$e Upstream request failed: Endpoint is unavailable.\""; sleep 30 ;;
  gone)     echo '> build · x'; echo "$e Model exo-free has been deprecated.\""; sleep 30 ;;
  ratelimit) echo '> build · x'; echo "$e Rate limit exceeded\""; sleep 30 ;;
  hang)     sleep 30 ;;
  slow)     echo '> build · x'; sleep 4; echo done ;;
  title)    echo "${e/small=false/small=true} Upstream request failed: Model is unavailable.\""; echo '> build · x'; echo done ;;
esac
X
# dc 派工前會先跑 wo-verify --dry 驗語法、--dump 拍 pin，那兩次不算跑驗收
printf '#!/bin/sh\ncase "$2" in --dry|--dump) ;; *) echo ok > "$VERIFIED";; esac\nexit 0\n' > "$T/bin/wo-verify"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/deep-lint"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/hpush"
chmod +x "$T/bin"/*
printf '# t\n' > "$T/t.md"

fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }
# 印「rc:有沒有跑驗收:秒數是否在上限內:錯誤訊息關鍵字」
try() { local lim="$1" key="$2"; shift 2; rm -f "$VERIFIED"; local s=$(date +%s)
  env "$@" "$DC" "$T/t.md" "$T/w" > "$T/err" 2>&1; local rc=$? d=$(( $(date +%s) - s ))
  local v=no; [ -f "$VERIFIED" ] && v=yes
  local f=slow; [ "$d" -le "$lim" ] && f=fast
  local k=nokey; grep -q "$key" "$T/err" && k=key
  echo "$rc:$v:$f:$k"; }

chk "Model is unavailable 提早結束"       "$(try 8 '上游不可用' FAKE=unavail)"  1:no:fast:key
chk "Endpoint is unavailable 提早結束"    "$(try 8 'Endpoint is unavailable' FAKE=endpoint)" 1:no:fast:key
chk "已下架提早結束"                       "$(try 8 'has been deprecated' FAKE=gone)" 1:no:fast:key
chk "限流照舊提早結束"                     "$(try 8 '上游限流' FAKE=ratelimit)" 1:no:fast:key
chk "啟動卡住在 DC_START_S 內結束"         "$(try 8 '沒開工' FAKE=hang DC_START_S=3)" 1:no:fast:key
# 開工後的靜默不歸 dc 管（STALL_S 在 dcq），不可被啟動看門狗誤殺
chk "已開工的慢模型不誤殺"                 "$(try 15 '提早結束\|沒開工' FAKE=slow DC_START_S=2)" 0:yes:fast:nokey
# 只認主 agent：small=true（取標題等小模型）的上游錯誤不算
chk "小模型錯誤不觸發"                     "$(try 8 '上游不可用' FAKE=title)" 0:yes:fast:nokey
exit "$fail"
