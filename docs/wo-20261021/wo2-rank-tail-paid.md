## 任務：autorank 擴到兜底層與訂閱層（層內排序）

cwd＝`/Users/you/dev/dispatch-router-wt/opt`（git worktree，分支 opt-1021）。先讀 `bin/dcq` 的 `rank_free`（輸出「順序|懲罰」）、第 170–260 行組 `POOL_TAIL`／`POOL_PAID` 的段落、`cmd` 的 `rank)` 分支、`test/dcq_rank_test.sh`。
背景：`rank_free` 只排免費主層。兜底層與訂閱層照清冊固定順序，永遠先派第一隻。實例：兜底層 opencode-go/longcat 12 跑 2 過，排在 11 跑 8 過的 opencode-go/beam 前面。

1. `bin/dcq`：在 `POOL_TAIL="$(oc_declared "$POOL_TAIL")"` 之後、`DCQ_MODELS` 沒設且 `DCQ_AUTORANK` 不是 0 時，`POOL_TAIL` 與 `POOL_PAID` 各自跑一次 `rank_free`，結果＝順序 後面接 懲罰（同一層內，懲罰的排在該層最後）。不跨層搬移，不分難度。
2. 這段上方加註解：日期 2026-10-21、為什麼（上面的實例）、規則與免費層相同。
3. `test/dcq_rank_test.sh` 加一段（`DCQ_GO_STATE` 指到不存在的暫存路徑，`DCQ_POOL_ZEN="a"`）：
   - gaps.tsv 造 `x/lo` 10 跑 2 過、`x/hi` 10 跑 8 過、`x/z` 3 跑 0 過；`DCQ_POOL_TAIL="x/z x/lo x/hi"` → `dcq rank` 的「兜底層：」行＝`x/hi x/lo x/z`。
   - 同樣資料放 `DCQ_POOL_PAID` → 「訂閱層：」行＝`x/hi x/lo x/z`。
   - `DCQ_AUTORANK=0` → 兜底層維持 `x/z x/lo x/hi`。
   - 耗時反例：`x/fast` 10 跑 6 過每筆 30s、`x/slow` 10 跑 10 過每筆 300s（用 rowd 造第 6 欄）→ 兜底層＝`x/fast x/slow`（證明排的是每 PASS 秒數，不是通過率）。
   - `DCQ_MODELS="m1"` 有設時兜底層不排序（維持 `DCQ_POOL_TAIL` 原順序）。
   失敗 exit 1。

## 禁止
- 改免費主層的排序規則、層級先後、`rank_free` 既有輸出格式。
- 讀寫真的 `~/.dcq`（測試一律用 `DCQ_HOME` 暫存）。

## 驗收
```bash
grep -q 'x/hi' test/dcq_rank_test.sh
PATH="$PWD/bin:$PATH" bash test/dcq_rank_test.sh
PATH="$PWD/bin:$PATH" bash test/dcq_tier_test.sh
bash test/dcq_test.sh
```

預期：全部 exit 0。
