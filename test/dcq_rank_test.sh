#!/usr/bin/env bash
# dcq 自動重排自檢：假 gaps.tsv 驗三條規則
# 1) 停滯率 ≥30% 的合格模型降到最後  2) 合格者在自己的位置裡依「每 PASS 秒數」重排（等待時間算進去）
# 3) 樣本不足的留在手排位置；rc=2 不算樣本；DCQ_AUTORANK=0 照手排
set -u
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export DCQ_HOME="$T/q"; mkdir -p "$DCQ_HOME/logs"
G="$DCQ_HOME/logs/gaps.tsv"; D="$(date +%F)_00:00:00"
row() { printf '%s\t%s\t10\t%s\t%s\n' "$D" "$1" "$2" "$3" >> "$G"; }
rep() { local i; for i in $(seq "$1"); do row "$2" "$3" "$4"; done; }
rowd() { printf '%s\t%s\t10\t%s\texit\t%s\n' "$D" "$1" "$2" "$3" >> "$G"; }
rep 10 a 0 exit            # a：100%
rep 5 b 0 exit; rep 5 b 1 exit   # b：50%
rep 6 c 0 exit; rep 4 c 143 stall # c：停滯 40% → 降級
rep 2 d 1 exit             # d：樣本不足（<RANK_ZERO_N=3，不觸發 0 PASS 短路），留原位
rep 9 e 0 exit; rep 5 e 2 exit    # e：扣掉 rc=2 只剩 9 筆 → 不合格
for i in $(seq 10); do rowd f 0 300; done                         # f：100% 但每張 300s → 300 s/pass
for i in $(seq 6); do rowd g 0 30; done; for i in $(seq 4); do rowd g 1 30; done  # g：60%、每張 30s → 50 s/pass
fail=0
got="$(DCQ_MODELS= DCQ_POOL_ZEN="c b d a e f g" DCQ_POOL_GO="" dcq rank | sed -n 's/^順序：//p')"
want="a d b e g f"   # g 通過率較低但等得少，排在 f 前；c 停滯 40% 進懲罰層
pen="$(DCQ_MODELS= DCQ_POOL_ZEN="c b d a e f g" DCQ_POOL_GO="" dcq rank | sed -n 's/^懲罰層（訂閱層之後）：//p')"
[ "$pen" = "c" ] || { echo "FAIL pen: got [$pen] want [c]"; fail=1; }
[ "$got" = "$want" ] || { echo "FAIL order: got [$got] want [$want]"; fail=1; }
got="$(DCQ_AUTORANK=0 DCQ_POOL_ZEN="c b d a e" DCQ_POOL_GO="" dcq status 2>&1 | awk '/busy=/{printf "%s ", $1}')"
case "$got" in "c b d a e "*) ;; *) echo "FAIL autorank=0: [$got]"; fail=1 ;; esac
# 4) 每日探測（probe.tsv 最新一批）：非 OK 的移到最後；manual 位置依探測秒數排；舊批次（>36h）不算
P="$DCQ_HOME/logs/probe.tsv"; now="$(date +%F_%T)"; old="$(date -v-3d +%F_%T 2>/dev/null || date -d '-3 days' +%F_%T)"
printf '%s\topencode\tx\tOK\t50\n%s\topencode\ty\tOK\t5\n%s\topencode\tz\tOK\t9\n' "$old" "$old" "$old" > "$P"
printf '%s\topencode\tx\tOK\t9\n%s\topencode\ty\tTIMEOUT\t60\n%s\topencode-go\ty\tFAIL\t1\n%s\topencode\tw\tOK\t3\n' "$now" "$now" "$now" "$now" >> "$P"
got="$(DCQ_MODELS= DCQ_POOL_ZEN="a x y z w" DCQ_POOL_GO="" dcq rank | sed -n 's/^順序：//p')"
want="a w x z y"   # y 最新一批全掛→最後；w 3s 先於 x 9s；z 只有舊批次＝無資料，排在有資料的後面
[ "$got" = "$want" ] || { echo "FAIL probe: got [$got] want [$want]"; fail=1; }
: > "$P"; printf '%s\topencode\ty\tTIMEOUT\t60\n' "$old" > "$P"   # 只有過期批次 → 不降級
got="$(DCQ_MODELS= DCQ_POOL_ZEN="y a" DCQ_POOL_GO="" dcq rank | sed -n 's/^順序：//p')"
[ "$got" = "y a" ] || { echo "FAIL stale probe: got [$got] want [y a]"; fail=1; }
# 5) 假釋：累犯最近一筆 >7 天 → 回免費層 manual；7 天內 → 留懲罰層
: > "$P"; old="$(date -v-10d +%F 2>/dev/null || date -d '-10 days' +%F)_00:00:00"
for i in 1 2 3; do printf '%s\th\t10\t1\texit\n' "$old" >> "$G"; printf '%s\tk\t10\t1\texit\n' "$D" >> "$G"; done
out="$(DCQ_MODELS= DCQ_POOL_ZEN="h k a" DCQ_POOL_GO="" dcq rank)"
got="$(printf '%s\n' "$out" | sed -n 's/^順序：//p')"; pen="$(printf '%s\n' "$out" | sed -n 's/^懲罰層（訂閱層之後）：//p')"
[ "$got" = "h a" ] && [ "$pen" = "k" ] || { echo "FAIL parole: got [$got | $pen] want [h a | k]"; fail=1; }
[ "$fail" = 0 ] && echo PASS
exit "$fail"
