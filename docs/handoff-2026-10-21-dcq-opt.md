# 交接：dcq 優化（2026-10-21，舊 session 跑 7h+ 後交接）

計畫與驗屍全文：`docs/plan-2026-10-21-dcq-opt.md`（含末段「/fix 診斷」）。本檔只列狀態與待辦。

## 一、本 session 已落地的 dr 補丁（主 repo main，未推公開版；publish-sync 週日 10:00）

| commit | 內容 | 驗證 |
|---|---|---|
| fd85352 | 防空轉併進 dcq watchdog（git cwd 420s 無變化 → why=spin），移除手動 dcq-spinwatch | dcq_test 90 PASS |
| 5ac370e | dcq_test 10c：非 git cwd 改真測（原斷言恆真） | 破壞判斷後 FAIL |
| f3a92bb | dc 的 ABUSE_RE／RL_RE／UA_RE 不再比中模型印出的 dc 原始碼（首字母 []＋ABUSE 只認 level=ERROR／Error: 行） | dc_upstream_test 21 PASS，舊 dc 2 FAIL；fixindex 11160 |

狀態修復：兩份 Zen 閘被 f3a92bb 前的誤判關到 12:37，已還原（備份 `/tmp/jev-zen-before-reset.json`、`/tmp/dc-zen-before-reset`）；Jev 06:55 實打 Zen ok。

## 二、三張工單：全未完成

工單：`docs/wo-20261021/wo1-zen-gate-backoff.md`、`wo2-rank-tail-paid.md`、`wo3-preflight-once.md`（已照 codex 驗屍改寫，lint 過）。
worktree：`~/dev/dispatch-router-wt/opt`，branch `opt-1021`，WIP commit `b247034`（未驗收，勿直接合併）。

| 工單 | dr 結果 | worktree 現況 |
|---|---|---|
| WO-1 Zen 閘延遲倍增＋半開 | FAIL rc=124（免費層 5 隻全被 slow/spin 殺，撞 JOB_MAX 2700） | 改了 bin/dc、bin/dcq、bin/zen-gate，新增 test/zen_gate_test.sh；相關測試 zen_gate/dc_upstream/dcq/dc_verify_gate 全 rc=0，wo-verify 完整驗收未跑 |
| WO-2 兜底／訂閱層內排序 | FAIL rc=124（同上） | 疊在 WO-1 未提交改動上做；dcq_rank_test 3 FAIL |
| WO-3 前置檢查憑證 | 手動取消（跑在混雜工作樹上） | 無有效改動 |

注意：上表測試結果是在 WO-1＋WO-2 混在一起的工作樹（commit 前、內容同 b247034）跑的，不能單獨歸給 WO-1；「3 FAIL 來自 WO-2」是推論（WO-2 改了 dcq_rank_test.sh），未拆開驗。

收尾建議：主 session 自己做（不再派 dr，原因見三）。
1. WO-1：跑 `wo-verify` 驗收＋讀 diff 審查 → 拆出乾淨 commit。
2. WO-2、WO-3：在 WO-1 之上主 session 自做，照工單驗收。
3. 全套 `test/*.sh`（12 支，全離線：假 opencode／假 curl／假 hpush）→ ff 合 main。

## 三、未解：opencode run「逾時」根因（/fix 進行中，證據強度中）

- 不是上游慢：LLM 每步 3–8s（只量 1 個 session）；每次嘗試僅 3–12 次工具呼叫。
- 時間被模型自跑 `bash test/dcq_test.sh` 吃掉（單次 120–160s+、無輸出）；opencode bash 工具預設 120s 逾時砍掉（log 原文「shell tool terminated command after exceeding timeout 120000 ms」）→ 模型重跑 → 撞 ATTEMPT_MAX=600（slow）或 SPIN_S=420（spin）。只抽 3/10 個 attempt。
- watchdog 訊息「已跑 Ns」印的是整張工單秒數（t - t0），不是這次嘗試，會誤導。
- 本機線索：opencode 1.18.35 二進位含 `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS`（用途由名稱推斷，未讀程式、未實測）。
- wheel：registry 無舊卡；舊 session 派了 prior-art 研究（opencode／SWE-agent／OpenHands／Claude Code／CircleCI／Jenkins），結果未回收 → 新 session 重跑 `/wheel`。

新 session 第一步：
1. 量其餘 7 個 attempt（opencode.db `~/.local/share/opencode/opencode.db`，session title `dc: wo1-*`／`dc: wo2-*`）的最後工具與每步耗時；單獨計時 `bash test/dcq_test.sh`。
2. 驗 `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS` 是否生效。
3. 候選修法（/wheel 後定序）：嘗試秒數訊息改 t - ta；工具子程序存活時不計 spin；ATTEMPT_MAX／SPIN_S 依 tier 分級或 dcq_test 提速；dc prompt 叫模型只跑相關測試、全套交 wo-verify。

## 四、另一個待 /fix

`zen-gate` 閘檔指向非正式路徑（測試／手動試跑）時仍送真 hpush。實例：WO-1 首輪模型在 shell 手動 `zen-gate trip t1..t5`，發出 5 則 TG 誤報（證據 `~/.dcq/logs/1792535411-87514-wo1-zen-gate-backoff.minimax-m3.1-flash-free.out:284`）。修法方向：閘檔≠預設路徑就不推播。等 WO-1 合併後改（同檔，避免衝突）。

## 五、接續詞

/fix 接手 ~/dev/dispatch-router/docs/handoff-2026-10-21-dcq-opt.md：先做「三、新 session 第一步」並重跑 /wheel，修 opencode run 逾時；再收尾「二」三張工單（主 session 自做）；最後「四」zen-gate 推播限制。

## 六、/wheel 結果（已回收，輪子卡已登記 10-21，30 天）

輪子：設定｜借鏡（無可直接採用的輪子；opencode 有官方設定可調，其餘借鏡設計）
- 設定：`OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS`（opencode runtime-flags.ts:53，v1.19.3；本機 1.18.35 二進位確認是 runtime flag `bashDefaultTimeoutMs`，未實跑驗證效果）。每次呼叫另可帶 `timeout` 參數。opencode run 本身沒有 agent 層停滯偵測。
- 社群：opencode #4197（測試 120s 被砍→回覆用 tmux 背景）、#11313（超時後 agent 重跑而非讀已存輸出＝本案症狀，stale 關閉）、#51832（600000 也被砍）。dev 分支新 shell 工具有 `background`＋`timeout=0`，未進正式版。
- 借鏡：SWE-agent `total_execution_timeout=1800` 不打斷執行中指令＋`max_consecutive_execution_timeouts=3`；mini-swe-agent 只在步驟間查上限；OpenHands 30s 無輸出＝軟超時（不殺，交 agent 決定）；Jenkins build-timeout Elastic／LikelyStuck（依歷史時長）；CircleCI no_output_timeout 預設 10 分。
- 建議修法序：
  1. 派工注入 bash 預設逾時（如 240000），且 dcq STALL_S（200）要大於它，否則 bash 未逾時 watchdog 先砍。
  2. opencode 下有存活 bash 子程序時暫停 stall／spin 計時，只留 ATTEMPT_MAX 硬上限。
  3. 同一慢指令連續逾時 2 次即結束該嘗試。
  4. 工單驗收改定向子案例，全套交 wo-verify（Anthropic best practices「Prefer running single tests」）。
  5. 之後再做：ATTEMPT_MAX 依歷史時長／tier 彈性化。
- 未查到（新 session 先實測）：opencode run 跑 bash 期間 .out 是否即時寫入（決定 1、2 怎麼實作）。
