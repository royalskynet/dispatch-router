# dcq 優化計畫（2026-10-21）

來源：happy session cmvgqs7lcjwzj0q0vdaelwdyz（本機 transcript 6d9ccb19）＋ gaps.tsv／probe.tsv／opencode.db 實測。
輪子卡：~/.wheel/registry.tsv 第 234 列。執行：派dr，cwd＝worktree `~/dev/dispatch-router-wt/opt`（分支 opt-1021），
不在主 repo 改：runner 跑的就是主 repo 的 bin/dcq，bash 邊讀邊執行，改檔會打壞執行中的 runner。

## 三個疑點的裁決

1. **Zen 鎖 IP**：成立，已有雙閘（dc ABUSE_RE＋zen-gate 6h）。缺口：dc 側固定 6h，Jev 側 10-19 已改倍增（fix 10990）；
   閘到期後 dcq 立刻用 zen=2 併發回打，等於解封瞬間又送一波。官方 #57144 不給期限、只能寄信，不繞封鎖。
2. **總選第一順位**：成立。autorank 只排免費主層；兜底層、訂閱層是清冊固定順序。
   實例：兜底層 opencode-go/longcat 12 跑 2 過排在 opencode-go/beam 11 跑 8 過之前。
   omniroute/go-free 33 次秒敗（Model not found）10-20 已從清冊移除，不再派；dc tier() 留有舊名，無害。
3. **冷啟動長**：部分成立，位置判錯。opencode 本體開機 0.5s、首回應 1–12s。
   慢在 dc 每次嘗試（每換一隻模型）重跑 deep-lint、wo-verify --dry/--dump、do-nothing 對照（整套驗收，上限 120s）、
   freecheck、opencode debug config ×2。`opencode serve` + `run --attach` 淘汰：#38661/#31435 提早 exit 0，會拿半成品驗收。

## 工單（同一 cwd，dcq 自動序列化）

| 單 | 內容 | 驗收 |
|---|---|---|
| WO-1 | zen-gate 延遲倍增（前 3 輪固定 6h，之後倍增封頂 48h，借鏡 OmniRoute）＋半開 zen 併發 1＋請求層級成功才清計數 | test/zen_gate_test.sh 新增 |
| WO-2 | rank_free 套到兜底層與訂閱層（層內排序，不跨層） | dcq_rank_test 新增段 |
| WO-3 | dc 前置檢查通過憑證（per-job 目錄存第一次的 pin；沿用原評分器，跳過 lint／negctl） | dc_verify_gate_test＋dcq_test 新增段 |

## 根治／預防

- 根治：WO-1 退避＋半開；WO-2 層內 autorank；WO-3 前置檢查只跑一次。
- 預防：三張都附會失敗的測試（mutation：把新邏輯拿掉要 FAIL）；全套 test/*.sh 重跑 exit 0。

## 合併

主 session 收件：worktree 全套測試 → 確認無 dcq runner 在跑 → merge opt-1021 進 main → 刪 worktree。

## 不做

- 繞 IP 封鎖（換 IP、偽造指紋）：違反上游條款，輪子卡 177 已記不做。
- run --attach 常駐 server：上游 bug 未修。
- Thompson sampling：樣本不足（dcq 第 176 行 ponytail 條件未達）。

## 驗屍修正（2026-10-21，codex roast＋prior-art 研究）

- WO-1 撤回「Jev 回報成功即提早解封」：探針冷卻期內不送請求，此路徑不可達；Jev `blocked:false` 在 429 也成立，會誤開。
  上游實際何時解封未知，倍增只證明降低本機請求頻率，不證明降低再封機率。Jev 側倍增（6→48h 立即倍增）未改，改要另議（他 repo 規則）。
- WO-2 照派；補耗時反例與 DCQ_MODELS 覆寫測試。已知限制：後棒接手前棒殘局、前棒拿全部工單，分數非公平比較。
- WO-3 原前提錯（lint 失敗是 exit 1 會被重試；watchdog 可在 negctl 完成前殺 dc）。改成 dc 明確寫出的通過憑證，並沿用第一次的 pin，順帶堵住「前棒改驗收、下次重釘」的既有漏洞。
- 未採用：每次重試重置工作樹（aider benchmark 做法）——會丟掉前棒的進度，要另評估。

## 進度（10-21 07:5x）
- 第一輪派工被 dc 自我誤判濫用（模型 cat dc 原始碼）→ 修 f3a92bb（fixindex 11160），閘已還原，三張重派：1792536952-5859／1792536953-5974／1792536954-6090，worktree ~/dev/dispatch-router-wt/opt（branch opt-1021）。
- 待辦（合併後）：全套 test/*.sh → ff 合 main → /fix「zen-gate 閘檔非正式路徑仍送真 hpush」（WO-1 首輪模型手動 trip t1–t5 發出 5 則 TG 誤報，證據 ~/.dcq/logs/1792535411-87514-…minimax….out:284）。
- 另查：deepseek 嘗試在 1208s 被 watchdog 殺（2s 無輸出），hard 單次上限是否過短。

## /fix 診斷：opencode run「逾時」（10-21 09:0x，證據已取）
結論：不是 opencode／上游慢，是 dcq 時間預算被模型自己跑的慢測試吃光。
- opencode.db（ses_ea43df24…、ses_ea437739…、ses_ea4645dc…）：LLM 每步 3–8s；每次嘗試只有 3–12 次工具呼叫。
- 每隻模型最後一個工具都是 `bash test/dcq_test.sh`（單次 120–160s+、全程無輸出），opencode bash 工具 120s 預設逾時會砍掉它（log：「shell tool terminated command after exceeding timeout 120000 ms」），模型再重跑 → 吃光 ATTEMPT_MAX=600 或 SPIN_S=420（跑測試不改檔＝判空轉）。
- watchdog 訊息「已跑 Ns」印的是整張工單秒數（t - t0），不是這次嘗試，誤導診斷（bin/dcq watch_oc）。
- hard 工單 JOB_MAX=2700 只夠 4–5 次嘗試，全落在免費層，從未升兜底／訂閱。
- 真正上游錯誤只有 1 次（WO-3 deepseek rc=1）。
待修（下個 session /fix 接手，wheel 第 0 步無舊卡）：
1. 嘗試秒數訊息改印 t - ta。
2. spin：attempt 有存活的工具子程序（opencode 之下的 bash）時不計空轉（或暫停計時）。
3. ATTEMPT_MAX／SPIN_S 依 tier 分級（hard 放寬），或 dcq_test 提速（先量它慢在哪：sleep 型假模型？）。
4. 工單／dc prompt：叫模型只跑相關測試，全套交給 wo-verify；bash 工具 timeout 參數給足。
狀態：WO-3 已取消；runner 已退出；worktree opt-1021 有 WO-1（相關測試全過）＋WO-2（dcq_rank_test 3 FAIL）未提交改動。另待 /fix：zen-gate 非正式閘檔仍送真 hpush。
證據強度：中。只抽 3/10 個 attempt session；「LLM 每步 3–8s」只量 1 個 session。新 session 第一步：量其餘 7 個 attempt 的最後工具與每步耗時、單獨量 dcq_test.sh 總秒數，再決定 4 點修法優先序。
