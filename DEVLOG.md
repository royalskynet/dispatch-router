# DEVLOG

## 2026-10-21：慢測試不誤殺、Zen 閘退避、重試只驗一次、推播閘

- **慢測試誤殺**（80184d1）：opencode bash 工具內建 120s 逾時，模型自己跑的慢測試先被砍，再被 watchdog 判 slow／spin 換模型。`dc` 設 `OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS=300000`；dcq 的 `oc_busy` 看到 opencode 底下有工具子程序就不計停滯與防空轉。
- **WO-1 zen-gate 延遲倍增＋半開**（df303ed）：連續 3 輪後封鎖時間每輪 ×2，上限 48h；到期只放一個探測，上游正常回應才清計數。借鏡 OmniRoute `circuitBreaker`。
- **WO-3 前置檢查憑證**（3eddc84）：第一次 lint 與負向對照都過就存下 pin，重試沿用，不重跑也不重抽評分器。
- **WO-2 層內排序**（4427735）：兜底層與訂閱層照免費層的 `rank_free` 排。
- **推播閘**（d9bb54f、e2c6e7b）：狀態路徑不是正式路徑就不送 TG，`DC_PUSH=1` 強制推。起因是工單模型把 `DC_ZEN_GATE` 指到暫存後手動 trip 5 次，發出 5 則誤報。涵蓋 zen-gate、dc 帳單、freecheck、oc-free-check、go-sync；go-sync 補了第一支推播測試。
- **踩坑**：測試迴圈寫成 `echo "$(basename $f) rc=$?"`，`$?` 取到 `basename` 的 0，一度把全套誤報成全過。rc 要先存變數。

## 2026-10-19：清冊驅動＋難度分層＋provider 併發

- `catalog/models.tsv`：本機模型清冊（free／sub／api），加 `dc_id`、`fit` 欄；dcq 各層預設名單改由清冊組，不再寫死。
- Agnes 2.0 Flash 7 天 0/801 成功，移出兜底層。
- `bin/triage`：入列時用本機 Laya 判 easy／mid／hard；hard 不派 `fit=easy`；`gaps.tsv` 加第 7 欄難度，autorank 依難度分開排。
- `catalog/providers.tsv`：per-provider 併發槽（zen 2，防 Zen IP 閘判濫用）。
- API 層接在訂閱層後，`DCQ_ALLOW_API=1` 才開。
- 測試：`test/dcq_tier_test.sh` 23 項；弄壞 fit 過濾與 provider 槽各一次，測試都會 fail。

## 2026-10-01 ～ 10-03：oc-agent → dispatch-router

### 做了什麼
- **issue #1 cwd 鎖**：dc 自己拿鎖，dc 與 dcq 共用 `~/.dcq/.cwdlock/<hash>`；撞鎖 exit 75，持有者已死的孤兒鎖自動清除（f746f65）。
- **issue #2 乾等／無法取消**：新增 `dcq cancel <id>`，被 kill 不算模型失敗（b0ddf4f）。
- **模型池＋個別冷卻＋watchdog**（4aac2d5）：Go 免費 → Zen 免費 → 付費。每個模型連敗 2 次冷卻 120s、同時最多 3 張；`.out` 超過 300s 沒動靜就殺整棵程序樹並冷卻該模型；總時限 2700s。每張的最大靜默時間記 `logs/gaps.tsv`。
- **免費優先**（19c3212）：免費模型跑滿 2 輪都失敗，或全在冷卻，才動用付費層，jobfile 標 `PAID=1`。
- **改名**（af14532）：oc／ocq → dc／dcq，repo 改名 dispatch-router。它已不限於 opencode，OmniRoute 也是上游之一。
- **計費分級只警示不擋**（af14532、0a67347）：`tier()` 分 free／sub／metered，跟 provider 無關。非免費一律先記 `logs/billing.tsv`，再發 TG；TG 10 分鐘最多一則，下一則附被壓掉的筆數（`DC_TG_EVERY`，d124dbd）。
- **模型擴充**：Zen 加入 mimo、nemotron-3-ultra、muse-spark-1.3-contributor-free 與 omniroute/free-tools 兜底；付費層從 2 個擴到 8 個 Go 模型（d4591c1、83d1ede）。
- **排序**：依 2026-10-03 同一張修 bug 工單的實測，寫得對優先、反應快其次（d124dbd）。

### 踩坑（細節在 fixindex）
- **opencode 免費層只認 CLI 身分**：經 API 呼叫或 OmniRoute 代打一律 403，偽裝 User-Agent 也沒用。所以 big-pickle 只能由 dc 直接派，已移出 OmniRoute 的 free-tools（9753）。
- **big-pickle 偶發用文字假扮工具呼叫**：輸出看起來有寫檔、跑驗收，磁碟上其實沒有任何檔案。用 `-- --format json` 看 `tool_use` 事件數就能分辨（9775）。
- **模型名稱帶 -free 不等於免費**：限時免費到期後名字不變，計費會變，要以額度和計費端點為準（9773）。
- **Go 額度是每個模型各自計算**：付費層多放幾個模型＝容量相加（9773）。
- **agent 工作的成本主要在 cache read 和 input**：output 單價影響很小。每張工單成本可以從 `--format json` 的 step_finish 加總，deepseek flash 約 $0.004，kimi-k3／grok 約 $0.12（9773）。
- **bash 3.2 下變數名緊接全形字元**：`$X（` 會在 set -u 下崩潰，一律寫成 `${X}`，已加 lint（9750）。

### 實測（2026-10-03，修 bug 工單，每個模型 1 個樣本）
| 組 | 模型 | 秒數 | 備註 |
|---|---|---|---|
| Go 免費 | space-bunny／longcat-2.5-preview | 8／9 | |
| Zen 免費 | nemotron-3-ultra／muse-spark／mimo-flash | 12／17／28 | |
| Zen 免費 | big-pickle | ~30 | 4 次裡卡住 1 次、假扮工具呼叫 1 次 |
| Zen 免費 | nemotron-3.5-lightning | 94 | 改錯 |
| Zen 免費 | fledge-alpha／ling-3.x | — | 連最小請求都失敗，不收 |
| 付費 | glm-5.3-flash／deepseek-v4-flash／v4.1-flash／v4-pro／minimax-m3／qwen3.8-flash | 12–28 | 已收 |
| 付費 | kimi-k3／qwen3.8-max／grok-4.7 | 22–27 | 每月額度不到 1k 次，不收 |
| 付費 | gpt-6-luna／hy4-preview | 114／222 | 太慢，不收 |

### 待辦／已結案
- （條件觸發，現在不做）依真實工單的通過率與耗時自動排序：等真實工單顯示目前排序明顯不對時再做。
- （已結案）freecheck 回報 Go 每週額度 5%：來源是 Hermes 的 Coco，它自 10-01 起預設 `opencode-go/deepseek-v4.1-flash`（訂閱模型）。Go 額度按模型各自計，Coco 和 dcq 付費層的 deepseek-v4.1-flash 共用同一份月額度（13 萬次），量級不衝突。
- （已結案，不是問題）`dc` 蓋過 `/usr/bin/dc` 計算機：本機腳本（openclaw／claude scripts、hooks、~/.local/bin、~/dev/*/bin）沒有人把 dc 當計算機用（`| dc`、`dc -e` 皆 0 筆）。注意 33 個 LaunchAgent 的 PATH 含 `~/.local/bin`，日後若有腳本要用計算機請寫 `/usr/bin/dc`。就算誤呼叫，dc 也會報錯退出，不會靜默算錯。
