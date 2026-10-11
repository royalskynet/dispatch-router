# 派工指令現況（2026-10-11 核對）

`~/.local/bin` 底下 dc／deep／deepclaude 三系指令混在一起，其中一半是 2026-10-05
留下的停用 stub。這份只記「現在跑什麼會發生什麼」，不講歷史。
每一列都當天實跑或讀檔核對過。

## 還在用的

| 指令 | 用法 | 說明 |
|---|---|---|
| `dc` | `dc <絕對路徑/task.md> [cwd] [-- <opencode run 旗標>]` | 單張派工給 opencode。完成的定義＝`wo-verify` 通過，不是模型說完成。task 路徑**必須絕對**，cwd 預設 `$PWD`。預設模型 `space-bunny-free` |
| `dcq` | 見 `dcq --help` | 多張工單併發，自動 cwd 互斥、模型池＋per-model 冷卻、停滯 watchdog |
| `dc-stats` | `dc-stats [session.jsonl]` | 算 round trip／output token／tool batching。**讀的是 `~/.deepclaude/config/projects`**，deepclaude 停用後那裡不再長新資料，所以只能看舊 session |
| `wo-verify` | `wo-verify <WO.md> [--dry\|--dump\|--pinned <script>]` | dc 的機械裁判。`--dump` 抽驗收腳本、`--pinned` 比對防篡改 |
| `deep-lint` | dc 內部呼叫 | 工單靜態檢查。名字有 deep 但沒隨 deep-run 停用 |

`dc` 找 `wo-verify`／`deep-lint` 的順序：先 PATH，再 `$DC_BIN`（預設
`~/.deepclaude/deep-agent/bin`）。

### dc 的三道防假成功閘（2026-10-11 加）

| 環境變數 | 預設 | 作用 |
|---|---|---|
| `DC_VERIFY_K` | 2 | 驗收連過 K 次才算 PASS（pass^k）。任一次失敗即 FAIL 並印第幾次掛 |
| `DC_NEGCTL` | 1 | 派工前跑一次驗收，**預期失敗**。此刻就過 → 中止（exit 2），因為驗收是空包彈或狀態已存在 |
| `DC_NEGCTL_TIMEOUT` | 120 | 負向對照的逾時秒數（不走 `wo-verify` 的 600） |
| `WO_VERIFY_TIMEOUT` | 600 | 正式驗收的逾時秒數 |

驗收腳本在派工前就抽成 pin 檔（執行人拿不到），驗收跑 pin 那份並比對工單當下版本，
不一致 → **exit 3 判篡改**。確認既有狀態型的工單在 task 檔寫一行 `NEG-CONTROL: n/a`
放行負向對照，或用 `DC_NEGCTL=0`。

exit code：`0` 全過｜`2` 工單瑕疵或負向對照失敗（dcq 視為 FATAL，不重試不罰模型）｜
`3` 驗收區塊被改動｜其它＝驗收腳本首個失敗指令的 rc。

## 2026-10-05 停用的（stub 回 exit 3）

| 指令 | 跑下去會怎樣 | 原檔 |
|---|---|---|
| `dc-new` | 印「已停用」，`exit 3` | `~/.local/bin/dc-new.disabled` |
| `deepclaude` | 同上 | `~/.local/bin/deepclaude.disabled` |
| `deep-run` | 同上 | `~/.local/bin/deep-run.disabled` |

停用原因：deep 由 dc 取代，deepclaude 快取命中率 8.6%。
恢復方式就是把 `.disabled` 改回原名。

### 一個繞過停用的漏洞（未修）

`deepclaude-happy` **沒有** stub，內容是：

```sh
exec "$HOME/.deepclaude/bin/deepclaude" --happy "$@"
```

它直接呼叫 `~/.deepclaude/bin/deepclaude`（4.5K，真的 launcher，還活著），
繞過 PATH 上的停用 stub。所以 `deepclaude` 跑不起來，但 `deepclaude-happy` 跑得起來。
要補就是把 `deepclaude-happy` 也 stub 掉，或讓它改走 PATH 上的 `deepclaude`。

## launchd：本機停用、plist 保留

| Label | 狀態 |
|---|---|
| `local.deepclaude.proxy` | `bootout` + `launchctl disable`（`:20133` 的常駐 proxy，原本 KeepAlive） |
| `local.deepclaude.happy` | `bootout` + `launchctl disable` |

plist **留在 `~/.deepclaude/launchd/` 並且被 repo 追蹤**——它們機器無關、公開可見，
停用是本機的事，不該讓 repo 少檔案。停用靠 `launchctl disable`，不靠改檔名
（改檔名會讓 repo 變 dirty，也讓文件裡的 `launchctl bootstrap <path>` 指令失效）。

`~/Library/Logs/deepclaude-proxy.log` 最後寫入 2026-10-05 03:10，與 deep-run 停用同日。

恢復單一 job：

```sh
launchctl enable  "gui/$(id -u)/local.deepclaude.proxy"
launchctl bootstrap "gui/$(id -u)" ~/.deepclaude/launchd/local.deepclaude.proxy.plist
```

`launchctl disable` 的旗標跨重開機持久存在，所以**先 `enable` 再 `bootstrap`**；
還在 disable 狀態下 bootstrap 不會把 job 載起來。

## 已知失效的文件指令

`~/.claude/CLAUDE.md`（machines/51mini.md）的路由表仍有一列叫人跑 `dc-new`，並說
「proxy :20133 不通先 `launchctl bootstrap ~/.deepclaude/launchd/local.deepclaude.proxy.plist`」。
現在 `dc-new` 回 exit 3，而且 plist 已經 `disable`，光 bootstrap 不會起來。
那列是制度檔，要改要經使用者確認。
