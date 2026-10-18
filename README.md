# dispatch-router

`dc` — 把 opencode 當執行人派工的最小封裝。一個任務檔進、機械驗收過的成果出。

與 [`deep-agent`](https://github.com/royalskynet/deep-agent) 平行：deep 走 deepclaude 在沙箱外跑，dc 走 opencode 客戶端路徑。

## Quick install／快速安裝

```bash
git clone https://github.com/royalskynet/dispatch-router && cd dispatch-router && ./install.sh
```

需求：macOS、[opencode](https://opencode.ai) CLI。`install.sh` 只做使用者層級安裝：把 `dc`／`dcq`／`oc-free-check` 連到 `~/.local/bin`、註冊每日探測免費模型的 launchd job（plist 內的 `/Users/you` 佔位會代換成實際 `$HOME`）、把 skill 連到各 agent 客戶端的 skills 目錄（見下節）。

## English

**dispatch-router** wraps [opencode](https://opencode.ai) as a task executor for coding agents: one task file goes in, and the work comes back only when a machine check says it is done.

- `dc <task.md> [cwd]` dispatches one work order. The exit code is the exit code of the task's own acceptance script (`wo-verify`), not the model's claim of success.
- Before dispatching, a lint gate refuses tasks without a runnable acceptance block, and a do-nothing control run rejects acceptance checks that would pass without any work.
- The acceptance script is pinned before the run; if the executor edits it, the run is judged as tampering (rc=3). Acceptance is re-run K times (default 2) to catch flaky results.
- `dcq` runs many work orders in parallel with per-directory locks, a model pool with per-model cooldown, and a stall watchdog.
- Model billing tiers are checked before each dispatch; paid models still run but trigger a Telegram warning.

Use plain `opencode run` if you only need a model to try something once. dc is for when "done" has to be decided by a script, not by the model.

The rest of this README is in Traditional Chinese.


## dc 到底比 `opencode run` 多什麼

只有這幾樣是真的多了東西，其餘都是把原生旗標設好預設值：

| # | 加了什麼 | 為什麼 opencode 自己做不到 |
|---|---|---|
| 1 | **exit code ＝ `wo-verify` 的 rc** | opencode 的 exit code 反映它自己有沒有跑完，不反映任務對不對。dc 把成敗綁在驗收腳本上。 |
| 2 | **派工前 `deep-lint` 閘** | 沒有可跑的驗收區塊就不派工 —— 否則模型做完也無法判定成敗。 |
| 3 | **計費分級警示** | 有 key 之後 `opencode models` 會列出付費模型；dc 把實際要派的模型分級，非免費照派但發 TG。 |
| 4 | **評分器釘住（`--pinned`，rc=3）** | 驗收區塊就在工單裡，執行人改得到的評分器他早晚會改到過關。派工前拍一份 pin，驗收跑 pin 並逐行比對；不一致即判篡改，不跑被改過的版本。 |
| 5 | **do-nothing 負向對照（派工前，rc=2）** | 什麼都不做也會通過的驗收不是驗收。派工前先在同一 cwd 跑一次，此刻就過＝空包彈或 no-op，不派工。逃生門 `NEG-CONTROL: n/a`。 |
| 6 | **驗收重跑 K 次（`DC_VERIFY_K`，預設 2）** | 單次通過只代表「至少成功過一次」。重跑才抓得到時好時壞的驗收與副作用。 |

設好的預設（不是新能力，但沒有它們 dc 根本不會動）：

- **`--auto`**：`permission.bash="ask"` 在 headless 下會被自動拒絕 —— 沒這道模型**一跑 bash 就死**（連 `ls` 都過不了），只能靠 write/edit 硬寫。執行人本來就要能跑 bash，故預設開；`DC_NO_AUTO=1` 可關（會嚴重降能）。
- **`--pure`**：同模型 4.5s vs 16s（`agentpet.js` 外掛佔 ~11s）。
- **`--dir` + `-f`**：任務檔常在專案外，用 `--dir` 指定工作目錄、`-f` 附加任務檔。
- **message 放最前面**：`-f` 是陣列旗標，會把後續位置參數當附件路徑吞掉。
- **驗收在 `--dir` 的目錄底下跑**：驗收斷言用相對路徑，在呼叫端 cwd 跑會全部找不到檔案而誤判 FAIL。

**如果你只是要 opus 等級的模型跑一次、不在乎成敗由誰判定，直接用 `opencode run`。** dc 的價值在「完成」是機械判定的。

## 計費分級（不擋，非免費發 TG）

每次派工先把模型分成 free／sub（扣訂閱額度）／metered（按量計費，或沒查過的組合），跟 provider 無關。**全部照派**，非 free 一律先記 `~/.dcq/logs/billing.tsv`，再 `hpush` 發 TG 警示（背景送，TG 掛了不影響派工；`DC_TG_EVERY` 秒內只發一則，預設 600，下一則附被壓掉的筆數）：

- free：opencode 系（`opencode/`、`opencode-go/`）id 以 `-free` 結尾，加上明列的 `big-pickle`。
- 未指定模型時釘死 `space-bunny-free`（2026-10-09 起；此前是 longcat，19 跑 9 停滯故換掉。Go 版 space-bunny 已改付費，這裡走 Zen 的 `opencode/` 免費端點），**不吃 opencode config 的 per-agent 付費 model**。
- 別家路由器的組合名帶 `-free`（如 `omniroute/auto/best-free`）不算 free，成員沒逐一查過就當 metered。唯一查過的是 `omniroute/free-tools`：不經 opencode.ai 的兜底上游，成員 `big-pickle → agnes → openrouter/free` 逐一查過全免費（2026-10-02；nim-pool 實測卡 600s 已移出）。omniroute 的組合改了就要重查。key 由 dc 從 kv 注入。
- 「免費全敗才動用訂閱」的權重在 dcq 的模型池（見下），dc 只負責分級與警示。
- 白名單可用 `DC_FREE_EXTRA` 補。

有 key 的價值在免費模型這一側：Go 讓 `space-bunny-free`／`longcat-2.5-preview-free` 變 Unlimited、速率放寬；不在於把 dc 升級成付費執行器。

### `freecheck` —— 停止免費就終止並跳警報

**名字有 `-free` 不代表還免費。** Go 的免費是「限時」無限，時限到了 id 不會變、計費會變。所以名字比對只是第一層，真正的判準是額度：

`bin/freecheck` 在 `dc` 每次派工前、`dcq run` 開跑前各查一次 `https://opencode.ai/zen/go/v1/usage`，任一成立就警報：

| 判準 | 意思 |
|---|---|
| 任一窗 `status != ok` | Go 額度窗受限，再跑只會排隊或轉付費 |
| 任一窗 `percent > 0` | 免費模型開始吃 Go 付費額度 |
| 要用的 Go 模型從 `/models` 消失 | 免費池收攤 |

警報動作：寫 `~/.dcq/.ALARM`、`hpush` 推播、`dc` 回 rc=2（fatal，不換模型重試，因為這是全域事實不是單一模型的問題）。`dcq` 一看到 `.ALARM` 就全隊停止收單，已在跑的那張讓它跑完（殺掉會留半套產物）。下一次 `dcq run` 會直接拒絕開跑，要人確認後刪掉 `.ALARM`。

`/models` 沒有價格欄位（只有 `id`／`object`／`created`／`owned_by`），所以只能從額度側判斷。已知天花板：**別處**（hermes、opencode TUI）用 Go 付費模型也會讓 `percent` 上升而誤報。寧可誤停不可誤花；確定是誤報就 `DC_FREECHECK=off`。

## 安裝

```bash
./install.sh
```

連結 `~/.local/bin/dc` 與 skill `dr` 到各 agent 客戶端的 skills 目錄：

| 目錄 | 誰讀 |
|---|---|
| `~/.claude/skills/dr` | Claude Code（另有 opencode，它本身也讀這裡） |
| `~/.agents/skills/dr` | 讀 `~/.agents/skills` 的其他 agent |
| `~/.codex/skills/dr` | Codex CLI |

`DR_SKILL_HOME` 可改成其他目錄清單（空白分隔），重跑 `install.sh` 是冪等的。

**client 支援範圍**：`dc`／`dcq` 是 shell 指令，任何能跑 bash 的 agent（Claude Code、Codex CLI、opencode）都能用；skill 只是把用法教給該客戶端。Codex CLI 讀 `~/.codex/skills/`（`SKILL.md` 的 YAML frontmatter 格式相同），`install.sh` 一併連結；若你的 Codex 版本尚未支援 skills，直接照本 README 的派工章節用 `dc`／`dcq` 即可，不影響功能。

**相依**：`wo-verify`、`deep-lint` 收在本 repo `bin/`，dc 直接用同目錄那份，不需要裝 `deep-agent`／deepclaude。`DC_BIN=<dir>` 只用來覆寫（測試注入假閘）。

另需 `jq`：`dc` 有 7 處要用，其中 `bin/dc:135` 靠它深度合併 `OPENCODE_CONFIG_CONTENT`。`dcq start` 另需 `tmux`（`bin/dcq:408` 直接 die）；`dcq run` 不用。

### Windows（git-bash）

`install.sh` 用 `ln -sfn`，Windows 沒有這個；`New-Item -ItemType SymbolicLink` 即使開了開發者模式也常要管理員權限。最省的做法是**跳過 symlink，直接把 `bin` 目錄加進 git-bash 的 `PATH`**（寫進 `~/.bashrc`，git-bash 會讀）：

```bash
export PATH="$HOME/.deepclaude/dispatch-router/bin:$PATH"
```

`dc`／`dcq`／`wo-verify`／`deep-lint` 都是 bash script，**Windows 上只能經 git-bash 執行**，PowerShell 直接打不會動。裝完先確認六支都在：

```bash
which dc dcq wo-verify deep-lint opencode jq
```

## 用法

```bash
dc <task.md> [cwd] [-- <opencode run 原生旗標>...]
```

- 任務檔路徑必須絕對。
- 契約（`deep-lint`／驗收 shell 區塊／「預期：」行／`## 禁止` 段）照 `deep` skill 的定義。
- `--agent <name>` 可指定 opencode agent 控制工具權限，模型仍由 dc 釘死。

環境變數：`DC_FREE_EXTRA`、`DC_FREE_MODEL`、`DC_SKIP_LINT=1`、`DC_BIN`、`DC_LOCK_WAIT`、`DC_NO_TIMEOUT_WARN=1`。
`DC_FREE_MODEL` 含 `/` 時當完整 `provider/model` 用，否則自動補 `opencode/` 前綴。

### cwd 互斥鎖在 `dc`，不只在 `dcq`

鎖只做在 `dcq` 的時代，直接呼叫 `dc` 可以完全繞過它 —— 兩個 session 對同一目錄派工，
產物互相覆蓋，只是運氣沒發生。所以鎖下沉到 `dc`：進入時對 cwd 取 `mkdir` 原子鎖，
路徑 `${DCQ_HOME:-~/.dcq}/.cwdlock/<cwd 的 shasum 前 12 碼>`，與 `dcq` **共用同一把**
（換個目錄名就等於兩把獨立的鎖，等於沒修）。

- 撞上別人持鎖：預設**不等**，`exit 75` 並印持鎖者 pid。`DC_LOCK_WAIT=<秒>` 才排隊。
- 持鎖者 pid 已死（`kill -9`、機器重開）：視為孤兒自動清掉再搶。
- `dcq` claim 時已持鎖，會帶 `DC_LOCK_HELD=1` 讓 `dc` 不重複拿（否則自己卡自己）。

### 上游停滯的 `chunkTimeout` WARN

opencode 對串流停滯的等待上限是 provider 的 `chunkTimeout`。5 分鐘預設值是 v1.18.27 才加的，
更舊的版本可能根本沒有上限 —— 上游一停滯就乾等，外觀等同卡死。`dc` 派工前唸一次合併後的 `opencode debug config`，
該 provider 沒設或設 > 180000 就 WARN。只出聲不擋：那是使用者的 config，`dc` 無權改。
建議在 `opencode.json` 設 `provider.<p>.options.chunkTimeout: 120000`。

**訂了 Go 之後**：`opencode-go/` provider 其實存在（29 個模型），只是本機 `opencode.json` 的 `enabled_providers` 白名單沒列它所以看不到。dc 遇到 `opencode-go/` 模型會用 `OPENCODE_CONFIG_CONTENT` 臨時把它加進白名單，不動使用者的 config；key 沿用 `opencode` 的憑證。免費的 `longcat`／`space-bunny` 掛在 `opencode/` 底下也能跑，兩條路都通（2026-10-02 實測）。

## Go lane 的 HTTP endpoint（`dc`／`dcq` 不走，但值得知道）

`https://opencode.ai/zen/go/v1/{chat/completions,messages,responses,models}` **對外可用**，訂閱就開。它跟被 `FreeTierError` 擋死的免費 Zen lane 是兩道完全不同的閘。2026-09-30 實測：

| | |
|---|---|
| 必要標頭 | `Authorization: Bearer <key>`、`x-opencode-session: ses_...`、**自訂 User-Agent**（文檔：`my-coding-agent/1.0` 這種，不要用 SDK 預設名） |
| 缺 session 標頭 | HTTP 400 `MissingSessionID` —— 只帶 Bearer 會以為「訂閱沒解鎖 API」，其實只是少一個標頭 |
| 模型 id | 線上用**裸 id**（`space-bunny-free`）。`opencode-go/space-bunny-free` 回 `Model is unavailable` —— 那個前綴是客戶端 config 的命名，不是 wire 上的 id |
| 目錄差異 | Go 的 `/models` 有 30 個，**不含 `big-pickle`**（Zen 專屬）。免費的兩隻：`space-bunny-free`、`longcat-2.5-preview-free` |
| prompt caching | **有**。回應帶 `prompt_tokens_details.cached_tokens`（實測 162 prompt 中 149 命中） |
| 併發 | 8 併發各帶自己的 session：全 200、每發約 1.5s、wall 2s，無 429 |
| 共用 session | 8 發共用同一個 `x-opencode-session` 會塞車（兩發拖到 8.3s／10.9s）。**session 是路由與快取的 key，一個並行單位配一個** |
| 對照組 | 同一把 key 打免費 Zen lane `/zen/v1` 仍是 403 `FreeTierError` |

但 HTTP 給的是推理不是 agent，改檔案仍得跑 CLI —— 所以 `dcq` 還是開 N 個 `dc` 進程，不打 HTTP。

### Hermes 已經內建 `opencode-go`，不用自己寫 shim

想把 Go lane 接到 Hermes 的話：**它內建就有**，上面那些標頭細節它都處理好了。2026-09-30 實測。

| | |
|---|---|
| provider | `hermes_cli/auth.py` 內建 `opencode-go`，base_url `https://opencode.ai/zen/go/v1`，env `OPENCODE_GO_API_KEY` |
| session 標頭 | `agent/opencode_affinity.py` 每發自動帶 `x-opencode-session`，沒有會話 id 時生 `oneshot-<hex>`。註解直接寫明是為了 Go lane 的 `MissingSessionID` 400，上游早修過同一個坑 |
| 快取親和 | session key 綁對話 root，compaction 後不變；壓縮／標題／vision 這些輔助呼叫共用同一顆 |
| 模型 id | `opencode-go` 屬 flat-namespace reseller，用裸 id，跟 wire 一致 |
| 目錄 | live-first，靠 `GET /models` 補進來，所以靜態清單沒有的 `*-free` 兩隻也會出現 |
| 存 key | `hermes auth add opencode-go --type api-key`；不存也行，設 `OPENCODE_GO_API_KEY` 即可 |

```
hermes --provider opencode-go -m space-bunny-free -z '...'        # PONG, rc=0
hermes --provider opencode-go -m longcat-2.5-preview-free -z '...' # PONG, rc=0
```

教訓：要幫工具補上游的協定細節之前，先 grep 那支工具的原始碼找 provider 名與標頭名 —— 修過的坑會留在註解裡。

## dcq — 併發跑者

`dc` 一次一張。`dcq` 是它的佇列前端：工單丟進去，N 個 slot 併發跑，成敗總表出來。

```bash
dcq add /abs/path/task.md [cwd]   # 入列（先過 deep-lint + wo-verify <task.md> --dry 准入閘）
dcq start -j 4                    # 同 run，但進獨立 tmux（-L dcq）脫離呼叫端；agent session 派工用這個
dcq run -j 4                      # 前景跑到 pending 清空（預設 4，硬上限 8）
dcq status                        # 各狀態計數與失敗清單
dcq cancel <job-id>               # 取消一張（殺整棵程序樹、階梯不重試、移到 failed）
```

它不是 HTTP 客戶端。Go 的 `/zen/go/v1` 給的是推理不是 agent，要改檔案仍得跑 opencode 的 agentic loop —— 所以併發＝開 N 個 `dc` 進程。

四件事由 dcq 負責，其餘全部複用 `dc`：

| | |
|---|---|
| **slot 分配** | `pending/ → running/ → done\|failed/`，搶單靠 `mv` 的 atomic rename，不另加鎖 |
| **per-job cwd 互斥** | 唯一會讓併發出「錯誤結果」而非只是變慢的項目：opencode 對工作目錄做 snapshot、`wo-verify` 斷言又是相對路徑，兩張工單共用 cwd 會互相汙染。鎖本身與 `dc` 共用同一把（見上），dcq 這邊只負責「搶不到就換下一張，不阻塞 worker」 |
| **模型池** | 2026-10-09 起 `DCQ_POOL_ZEN`（手排 nemotron-3-ultra → space-bunny → step-5 → ling-3.1-flash → mimo）在前、`DCQ_POOL_GO`（預設 `longcat-2.5-preview-free`）殿後當兜底，實際順序每次啟動由 autorank 依 `gaps.tsv` 重算（`dcq rank` 印表）：longcat 19 跑 9 次 300s 停滯（471 s/pass，已 demoted），space-bunny 25 跑 21 PASS（85 s/pass），nemotron-3-ultra 16 跑 0 停滯（107 s/pass）。降級有兩道：停滯率 ≥`DCQ_RANK_STALL_PCT`（30%）；以及 2026-10-09 加的短路——樣本 ≥`DCQ_RANK_ZERO_N`（3）而 PASS 為 0 就不等 `DCQ_RANK_MIN` 直接降（nemotron-3.5-lightning 5 跑 0 PASS、1 停滯、曾自稱完成而驗收 FAIL）。降級只是移到免費層最後，仍排在付費層前，過一張就自己回昇。muse-spark／mimo／big-pickle／space-bunny-free／free-tools 2026-10-07 實測 420s 無產出已移出池。依序挑「本單沒試過、沒在冷卻、槽沒滿」的第一隻。`rc=1/124`（上游）換下一個；`rc=2`（工單契約錯）不重試。沒訂 Go 就 `DCQ_POOL_GO=`。`DCQ_MODELS` 有設就整條覆寫 |
| **per-model 冷卻** | 借鏡 LiteLLM Router 的 `allowed_fails`／`cooldown_time`：同一隻連續 `DCQ_ALLOWED_FAILS`（2）次上游失敗或停滯，冷卻 `DCQ_COOLDOWN_S`（120）秒，期間不派給它。只罰那一隻 —— 舊版是全隊熔斷，一隻掛全隊停 |
| **權重：免費優先** | 免費池整輪試過 `DCQ_FREE_ROUNDS`（2）輪都失敗，**或**免費模型全在冷卻，才 fallback 到 `DCQ_POOL_PAID`（預設 7 隻，依實測「寫得對＞反應快」排序：`opencode-go/glm-5.3-flash opencode-go/deepseek-v4.1-flash opencode-go/deepseek-v4-pro opencode-go/minimax-m3 opencode-go/qwen3.8-flash opencode-go/kimi-k2.7-code opencode-go/glm-5.3`。Go 額度 per-model 各自計，多放＝容量相加；與 Zen 免費同底模的 muse／mimo Go 版不收；deepseek-v4-flash 上游退役，2026-10-03 移除）。用過訂閱層的工單在 jobfile 標 `PAID=1`。`DCQ_POOL_PAID=` 設空＝永不動用，免費全冷卻時就等 |
| **per-model 併發槽** | 單一模型同時最多 `DCQ_MODEL_MAX`（3）張，滿了直接分給下一隻，不在忙的模型上排隊 |
| **watchdog** | opencode 的 `chunkTimeout` 有洞（[#43519](https://github.com/anomalyco/opencode/issues/43519) SSE keepalive 會歸零計時、[#48675](https://github.com/anomalyco/opencode/issues/48675) 一個 chunk 都沒送就卡住不報錯），外面再看一層：每 `DCQ_POLL_S`（5）秒看 `.out` 的 mtime，靜默 ≥ `DCQ_STALL_S`（200；2026-10-09 起，依 gaps.tsv 39 張 PASS 最大靜默 162s 留 25% 餘量）秒判停滯 → 殺整棵樹、冷卻計數＋1、換下一隻。單隻模型一次嘗試超過 `DCQ_ATTEMPT_MAX`（600，≈PASS 單次最長 294s×2）秒也一樣換手——一直有輸出的無限迴圈不會觸發停滯。整張工單超過 `DCQ_JOB_MAX`（2700）秒也殺，但**不罰模型、不換**（防 [#52092](https://github.com/anomalyco/opencode/issues/52092) 失控迴圈燒光 Go 額度） |
| **取消** | `dcq cancel <id>`：先寫 `.cancel/<id>` 標記再殺程序樹，順序不能反 —— 反過來 `run_job` 會把 kill 的 rc 當成模型失敗，直接換下一個模型重跑同一張，人工中止永遠停不下來。`dc` 是 bash 殼，殺它不會帶走 opencode，所以殺整棵樹 |

併發上限硬夾 8：社群實測 1–5 穩、10–32 崩，官方只說 "traffic is monitored for abuse" 沒給數字。衝高併發的期望值是被 ban，不是更快。

**2026-09-30 本機實測**（Go 訂閱後，`space-bunny-free`，每張工單自己的 cwd）：4 併發 4/4 PASS、8 併發 8/8 PASS，全部第一個模型就中、沒用到 fallback。`opencode.db` 的 WAL 在 8 個並行 `opencode run` 下 **0 次** `database is locked`／`SQLITE_BUSY`。

**停滯門檻為什麼是 300 秒**：opencode 的輸出（文字或 `--format json`）是 **part 級**不是 token 級，2026-10-02 實測從開始串流到第一個 step 完成之間 10 秒完全沒輸出；長推理的正常 step 本來就會靜默數分鐘。門檻太緊會誤殺正常工作。每次跑完都會把最大靜默間隔記到 `~/.dcq/logs/gaps.tsv`（時間、模型、最大間隔、rc、原因），累積一週再依實際分佈收緊。`dc` 收尾的 `wo-verify` 也算在內，驗收指令很慢的工單要把門檻放寬。

`dcq status` 會列出每隻模型的 `busy=n/max` 與冷卻剩餘秒數。

環境變數：`DCQ_HOME`（預設 `~/.dcq`）、`DCQ_JOBS`、`DCQ_POOL_GO`、`DCQ_POOL_ZEN`、`DCQ_POOL_PAID`、`DCQ_FREE_ROUNDS`、`DCQ_MODELS`、`DCQ_MODEL_MAX`、`DCQ_ALLOWED_FAILS`、`DCQ_COOLDOWN_S`、`DCQ_STALL_S`、`DCQ_JOB_MAX`、`DCQ_ATTEMPT_MAX`、`DCQ_POLL_S`。舊名 `DCQ_BREAK_N`／`DCQ_BREAK_S` 仍可用，對應到 `DCQ_ALLOWED_FAILS`／`DCQ_COOLDOWN_S`。

自檢（都用假的下游，不打上游）：`./test/dcq_test.sh`（佇列、模型池、權重 fallback、冷卻、併發槽、watchdog、cancel）、`./test/dc_lock_test.sh`（cwd 鎖）、`./test/dc_model_test.sh`（模型閘：哪些准派、哪些要拒）

## 已知坑

- 免費端點會突然掛：實測 `ling-3.0-flash-fin-free` 回 `Upstream unavailable`。dc 不做自動 fallback。
- 免費池的帳單是 wall-clock：單一函式小修 17–20 秒，兩個函式加約束約 4 分鐘。長任務不要用 dc。
- 適用範圍：讀 codebase／追依賴／單點小修。跨多檔重構、需要 `GH_TOKEN`、要寫 `~/.claude/**` → 用 deep。
- `504 Upstream idle timeout exceeded` 的根因是**單輪閒置**，不是總時長：殺手是 `uv pip install`／`npm ci` 這種幾分鐘不吐 token 的步驟。這類指令由呼叫端先跑完，別靠重試硬碰。
- **工單裡的「預期：…」不是斷言**，wo-verify 只跑 shell 區塊看 exit code。`echo x | ./foo.sh` 永遠 rc=0，模型輸出錯的東西照樣 PASS。要比對輸出就寫成 `[ "$(...)" = "..." ]`。（實測：8 張同樣的工單，一張產出 `hello-world-foo-` 多一個 dash，仍被判過。）
- shell script 裡 `$var` 後面直接接中文標點會被 bash 吃進變數名（`rc，` → `rc\xef...: unbound variable`），在背景 worker 裡會變成靜默猝死。變數後接非 ASCII 一律寫 `${var}`。
- **`jq` 缺了會報一句誤導的錯**：`dc` 不會說「找不到 jq」，而是死在 `bin/dc:136` 的 `OPENCODE_CONFIG_CONTENT 不是合法 JSON`。真因是 `bin/dc:135` 那行 `jq` 輸出為空，`_cc` 跟著變空。
- **驗收裡的常數要跟組合數自己算一遍，`wo-verify --dry` 抓不到這個矛盾**。`--dry` 只驗 shell 區塊能不能解析，不驗它跟任務描述對不對得上。實測：任務檔寫「864 筆」但組合算出來是 `6×3×6×2×2 = 432`，`deep-lint` 與 `--dry` 都放行，最後是執行人自己讀出矛盾、報 `DC_TASK_DEFECT` 拒派（rc=2，不重試）。派工前把驗收裡的數字算一遍，比事後 debug 便宜。
- **Windows 只能經 git-bash 跑 `dc`，且路徑要用 `/c/...` 形式**：`dc` 要求絕對路徑，但 `C:\Users\...` 傳進 bash 後 `\U`、`\t` 會被當 escape 吃掉。從 PowerShell 呼叫要包一層，`-i` 不能省（`bash -c` 不讀 `.bashrc`，上面的 PATH 注入不生效）：

  ```powershell
  & "C:\Program Files\Git\bin\bash.exe" -i -c "dc /c/path/to/task.md /c/path/to/repo"
  ```

## 每日探測（oc-free-check）

launchd job `dcq-probe`（`launchd/` 內的 plist）每天 06:00 跑 `oc-free-check -p opencode --tsv ~/.dcq/logs/probe.tsv`：起一個 `opencode serve`，對每個免費模型送「Reply with just: ok」，記狀態、秒數、原因（TSV 第 6 欄）。免費額度 00:00 UTC（08:00 本地）才重置，06:00 量到額度用完的記 QUOTA，dcq rank 當沒資料不判 down。最新一批也驅動名單同步：GONE 移出池、新上架 OK 的接進池（`DCQ_POOL_SKIP` 排除）；訂閱層讀 opencode-go-sync state 同步。

狀態分級（`prompt_async` 後輪詢 `/session/status`，opencode 遇限流會自己重試，同步呼叫只會卡到逾時）：

| 狀態 | 意思 | 通知 |
|---|---|---|
| OK | 有回文字 | — |
| QUOTA / RATELIMIT | 免費額度用完（附重置時間）／限流，模型沒壞 | 由 OK 轉入報一句「額度用完」 |
| FAIL | 上游回錯 | 由 OK 轉入立刻報「掛了」 |
| GONE | 快取標 deprecated、官方 Zen 清單已沒有、或上游回 deprecated，不送請求 | 由 OK 轉入報「已下架」 |
| NOCLIENT | 官方 Zen 清單（`opencode.ai/zen/v1/models`，同後台 Models 頁）有、本機模型快取沒有，dc 叫不到 | 第一次出現報一次 |
| TIMEOUT / ERR | 沒回話（附最後重試原因） | 連兩批才報；一批 ≥3 個同時轉入只報共因 |

建 session 時帶 title，否則 opencode 會另叫 small model 產標題，多吃一份免費額度。
（腳本源自 Ether-secrets `oc-free-check.py`，這裡加了計時與 `--tsv`。）

`dcq rank` 合併規則（只用最新一批、≤`DCQ_PROBE_MAX_H`=36 小時）：

- 探測非 OK → 移到免費層最後（明天回 OK 自動回來）
- 樣本不足（manual）的位置依探測秒數排
- 真實工單的「每 PASS 秒數」仍是主排序——探測量得到活著與快慢，量不到寫碼能力

手動跑：`oc-free-check -p opencode`；看排名：`dcq rank`（多一欄 `probe`）。

### 懲罰層（累犯排在免費層之後）

自動排名判成 `zero`（≥3 筆 0 PASS）或 `demoted`（停滯率 ≥30%）的免費模型，不再留在免費層尾巴，改進 `POOL_PEN`：
**免費 → 懲罰層 → 兜底層 → 訂閱（opencode-go，付費，2026-10-13 起墊底）**。免費層會重試 `DCQ_FREE_ROUNDS` 輪，累犯留在裡面等於每張工單白等它卡兩次。
最近一筆樣本超過 `DCQ_RANK_PAROLE_D`（預設 7）天就假釋回免費層重新給機會。`dcq rank` 最後一行列出目前的懲罰層。
