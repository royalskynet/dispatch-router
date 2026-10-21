## 任務：前置檢查通過憑證（同一張工單只驗一次、沿用第一次的評分器）

cwd＝`/Users/you/dev/dispatch-router-wt/opt`（git worktree，分支 opt-1021）。先讀 `bin/dc` 第 85–112 行（deep-lint 失敗 exit 1、wo-verify --dump 釘住評分器 `$pin`、do-nothing 對照 negctl）、`bin/dcq` 的 `watch_oc`（第 502 行呼叫 dc）與 `run_job`、`test/dc_verify_gate_test.sh`、`test/dcq_test.sh` 假 dc 寫法。
背景：dcq 每換一隻模型就重呼叫 dc，dc 每次重跑 lint 與 negctl（整套驗收，上限 120s），還會從工單重新抽評分器——前一隻模型若改了工單驗收區塊，下一次會把改過的版本釘成新基準。不能用「第幾次嘗試」判斷已驗過：lint 失敗是 exit 1 會被重試，watchdog 也可能在 negctl 跑完前殺掉 dc。

1. `bin/dc`：有 `DC_PREFLIGHT_DIR`（目錄路徑）時：
   - 目錄裡有 `pin` 檔＝憑證存在：跳過 deep-lint 與 negctl，評分器改用 `$DC_PREFLIGHT_DIR/pin`（不重新 --dump），印 `dc: 沿用本單前置檢查憑證`。之後照舊比對工單當下的驗收區塊，不一致 exit 3。
   - 沒有憑證：照原流程；lint 與 negctl 都通過後才把 `$pin` 複製成 `$DC_PREFLIGHT_DIR/pin`（先寫暫存檔再 mv）。任一關失敗或中途被殺都不得留下 `pin`。
   - 沒設變數時行為完全不變。
2. `bin/dcq`：`run_job` 設 `DC_PREFLIGHT_DIR="$Q/.preflight/$id"` 傳給每次 dc；工單結束（PASS、FAIL、取消）刪掉該目錄。加註解（2026-10-21、為什麼）。
3. `test/dc_verify_gate_test.sh` 加一段（用真 wo-verify、假 opencode）：
   - 有 `DC_PREFLIGHT_DIR` 且 negctl 通過 → 目錄出現 `pin`；deep-lint 失敗 → 不出現 `pin`。
   - 憑證存在、工單驗收在動工前就會過 → 不因 do-nothing 對照中止（輸出含「沿用本單前置檢查憑證」）。
   - 憑證存在、假 opencode 把工單驗收改成 `true` → dc exit 3。
4. `test/dcq_test.sh` 加一段：假 dc 記錄收到的 `DC_PREFLIGHT_DIR`；同一張工單兩次嘗試收到同一個路徑，工單結束後該目錄不存在。
失敗 exit 1。

## 禁止
- 改 negctl 的判定本身、改既有測試的斷言、跳過驗收當下的評分器比對。

## 驗收
```bash
grep -q 'DC_PREFLIGHT_DIR' bin/dc
bash test/dc_verify_gate_test.sh
bash test/dcq_test.sh
bash test/dc_lock_test.sh
```

預期：全部 exit 0。
