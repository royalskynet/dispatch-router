# oc-probe（dr 選配）

偵測 opencode 模型清單的變化，自動改 dr 的 OC 模型清冊（`../catalog/models.tsv`）。不碰 OmniRoute。

## 指令

- `oc-probe daily`（launchd `local.opencode-probe`，每天 06:00）
  1. 週探測：距上次滿 `PROBE_EVERY_D`（預設 7）天，且 `zen-gate check` 在閘外，才跑 `oc-free-check -p opencode`。它起 `opencode serve`，對每個 Zen 免費模型送一句話，結果寫 `~/.dcq/logs/probe.tsv`。閘內不探測、不寫 stamp，隔天再試。
  2. `go-sync`：距上次滿 7 天才抓 `https://opencode.ai/zen/go/v1/models`，寫 `~/.dcq/logs/go-models.json`。零 token，不實打。
  3. 選配 hook：`OC_PROBE_HOOK`（預設 `~/.config/oc-probe/hook`），存在且可執行才跑。
- `oc-probe x`（launchd `local.opencode-probe.x`，每 4 小時）：讀 @opencode 新推文。第一行讀得出改名／上下架就記 `x-pool.tsv`（上架只信 3 天內）。需要 PATH 上有 `twitter`（twitter-cli），沒有就略過。
- `oc-probe probe`：強制探測一次。`oc-probe sync`：強制 go-sync 掃一次。

探測或推文偵測到變化後跑 `dcq sync-catalog`：增刪寫回清冊，沒變動不改檔，清冊原本乾淨才自動 commit。

## 規則

- 只用 `opencode run`／`opencode serve` 探測。Zen 免費層 API 直打不回應，不代表模型壞了。不要重試探測，會被判濫用鎖 IP。
- 先單打 1 隻當探針，回濫用 403 就 trip `zen-gate` 停手，不打其餘模型。
- 通知走 PATH 上的 `hpush`，沒有就只寫 log。

## 為什麼不用 models.dev

models.dev 有 `opencode`、`opencode-go` 兩個 provider 的清單和價格，但會落後上游。2026-10-21 實測：Go `/models` 已移除 `cat-jam-free`，models.dev 仍列著。所以清單直接讀上游 `/models`，可用性用實打確認。

## 安裝與測試

```bash
../install.sh && ./install.sh     # dr 本體（dcq、zen-gate）＋ 兩個 launchd job
for t in test/*.sh; do bash "$t"; done; python3 test/x_pool_test.py; bin/go-sync --selftest
```
