#!/bin/bash
# dcq-spinwatch：工作樹不變就殺嘗試、有改檔就不殺、工單結束就自己停。用假 DCQ_HOME，不碰真佇列。
set -u
B="$(cd "$(dirname "$0")/.." && pwd)/bin"; T=$(mktemp -d)
export DCQ_HOME="$T/q" SPIN_POLL=1; mkdir -p "$DCQ_HOME"/{running,pending,logs}
fail=0; check() { if [ "$1" = "$2" ]; then echo "PASS $3"; else echo "FAIL $3（得 $1，要 $2）"; fail=1; fi; }
for w in idle busy; do git init -q "$T/$w"; done

sleep 300 & IDLE=$!; sleep 300 & BUSY=$!
touch "$DCQ_HOME/running/j1.job" "$DCQ_HOME/running/j2.job"
echo $IDLE > "$DCQ_HOME/running/j1.pid"; echo $BUSY > "$DCQ_HOME/running/j2.pid"
( for i in 1 2 3 4 5 6; do echo $i > "$T/busy/f$i"; sleep 1; done ) &
"$B/dcq-spinwatch" -s 3 j1="$T/idle" j2="$T/busy" > "$T/out" 2>&1 & SW=$!
sleep 6
if kill -0 $IDLE 2>/dev/null; then r=alive; else r=killed; fi; check $r killed "工作樹不變的嘗試被殺"
if kill -0 $BUSY 2>/dev/null; then r=alive; else r=killed; fi; check $r alive "一直改檔的嘗試不殺"
rm -f "$DCQ_HOME"/running/*; sleep 3
if kill -0 $SW 2>/dev/null; then r=alive; else r=gone; fi; check $r gone "工單都結束後自己停"
grep -q "j1 空轉" "$DCQ_HOME/logs/spinwatch.log"; check $? 0 "有寫空轉紀錄"
kill $BUSY $SW 2>/dev/null; rm -rf "$T"; exit $fail
