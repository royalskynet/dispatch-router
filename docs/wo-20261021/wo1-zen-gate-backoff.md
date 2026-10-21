## 任務：zen-gate 延遲倍增退避＋半開（借鏡 OmniRoute circuitBreaker）

cwd＝`/Users/you/dev/dispatch-router-wt/opt`（git worktree，分支 opt-1021）。先讀 `bin/zen-gate`（閘檔 `$DG` 存到期 epoch 秒；`until` 取 dc 與 Jev 兩份最大值；`trip` 只延長不縮短）、`bin/dc` 第 133–145 行與 opencode run 之後偵測 ABUSE_RE 的地方、`bin/dcq` 的 `take_slot`。
背景：Zen 免費層判本機 IP 濫用會 403，官方不公布期限。現在 trip 固定封 6h。借鏡 OmniRoute（`src/shared/utils/circuitBreaker.ts`）：半開只放 1 個探測；連續 3 輪「到期→探測→又被封」才開始倍增，上限 16 倍。

1. `bin/zen-gate`：
   - 計數檔 `$DG.streak`（整數）。`trip` 只在呼叫當下閘是開的（兩份最大值 ≤ now）才 +1；閘還關著時重複 trip 不加計數。
   - 封鎖秒數：streak ≤3 → `GATE_S`；streak >3 → `GATE_S × 2^(streak−3)`，上限 `DC_ZEN_GATE_MAX_S`（預設 172800）。
   - 新子命令 `ok`：刪 streak 檔。新子命令 `halfopen`：streak 檔存在且 `until` ≤ now → exit 0，否則 exit 1。
   - 檔頭說明補上述三點，註明借鏡來源與日期 2026-10-21。
2. `bin/dc`：模型是 `opencode/*`、opencode run 結束後輸出不含 ABUSE_RE、且有任何模型輸出（不論驗收過不過）→ 跑 `"$ZG" ok >/dev/null 2>&1`。恢復判準是「請求被上游正常回應」，不是「工單通過」。
3. `bin/dcq`：`take_slot` 裡 provider＝zen 且 `"$ZG" halfopen` 成立時，該 provider 上限當 1。
4. 新增 `test/zen_gate_test.sh`（mktemp、`DC_ZEN_GATE`／`JEV_ZEN_STATUS_FILE` 指到暫存檔、`DC_ZEN_GATE_S=100`、PATH 前放假 `hpush`）。每次 trip 前把閘檔寫成過去時間，斷言到期≈now+（誤差 ≤5）：第 1、2、3 次 100，第 4 次 200，第 5 次 400；`DC_ZEN_GATE_MAX_S=300` 時第 5 次封頂 300；閘未到期再 trip 到期不變且 streak 不變；`halfopen` 在到期＋有 streak 時 exit 0、`ok` 後 exit 1、`ok` 後下一次 trip 回到 100；Jev 檔 `cooldown_until` 在未來時 `halfopen` exit 1。失敗 exit 1。

## 禁止
- 改 `bin/dc` 的 ABUSE_RE、改 Jev 檔格式、改 jev-gate-mcp repo。
- 用 Jev 檔的 `blocked:false` 當解封依據（429 也寫 false）。
- 真的呼叫 hpush 或打網路。

## 驗收
```bash
bash test/zen_gate_test.sh
bash test/dcq_test.sh
bash test/dc_model_test.sh
bash test/dc_upstream_test.sh
```

預期：全部 exit 0。
