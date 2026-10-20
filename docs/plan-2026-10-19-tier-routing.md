# dcq 依難度、依清冊編排（2026-10-19）

## 目標
1. 模型池從 `catalog/models.tsv` 產生，順序固定為 免費 → 訂閱 → API（API 預設關，`DCQ_ALLOW_API=1` 才開）。
2. 每張工單在入列時判難度（easy／mid／hard），依難度選池、依難度分開排名。
3. 併發控制除了 per-model，再加 per-provider（Zen 共用 IP 閘最容易被判濫用）。

## 輪子裁決（/wheel 2026-10-19）
- 不換框架。LiteLLM、Portkey、plano 都是第二個閘道，跟 OmniRoute 重疊；RouteLLM、NotDiamond 已停更或封存。
- 借鏡 LiteLLM `complexity_router`（按難度分層）與 oh-my-opencode 的 `providerConcurrency`／`modelConcurrency`（併發 schema）。
- 難度判定直接用本機 Laya（jev-gate `triage()`，`JEV_PROVIDER=laya`）：本機 ONNX、零 token、約 2～3 秒。
- 只在入列時判一次，同一張工單中途不換難度（manifest.build 2026-07 停用路由器一文：中途換模型會降品質）。
- Thompson sampling 延後：gaps.tsv 118 筆分散在 18 個模型，只有 3 個滿 10 筆，拆三個難度後幾乎每格都不到 10 筆。
  觸發條件：任一難度有 ≥5 個模型各 ≥20 筆。在那之前沿用 s/pass 排名＋假釋。

## 改動
- `catalog/models.tsv`：加 `dc_id`（dc -m 吃的名字，空＝dcq 不用）與 `fit`（any／easy；easy＝hard 工單不派）兩欄。
  Agnes 0/801 成功，`dc_id` 留空，移出兜底層。
- `catalog/providers.tsv`：per-provider 併發上限。zen 2、opencode-go 4、omniroute 3。
- `bin/triage <task.md>`：印 easy／mid／hard。jev-gate 不在、逾時、Laya 判不出時一律印 mid（fail-open）。
- `bin/dcq`
  - 沒設 `DCQ_POOL_*` 時從清冊組池；有設的照舊覆寫，舊介面相容。
  - `dcq add <task> [cwd] [tier]`：沒給 tier 就跑 triage，job 檔記 `TIER=`。
  - hard 工單從每一層濾掉 `fit=easy`。
  - gaps.tsv 第 7 欄記 tier；`rank_free` 依 tier 算，舊紀錄（沒有 tier）算進每個 tier。
  - `take_slot` 先搶 provider 槽，再搶 model 槽，兩個都拿到才派。

## 驗收（test/dcq_tier_test.sh，假 dc，不打上游）
1. 清冊組出的池：免費層、兜底層、訂閱層內容與順序正確；API 層預設為空，開旗標後才出現。
2. hard 工單不派 `fit=easy` 的模型；easy 工單會派。
3. provider 上限 1 時，同 provider 兩個不同模型的工單不會同時跑。
4. gaps.tsv 新列帶 tier；某模型只在 hard 失敗，easy 的排名不受影響。
5. `JEV_GATE_DIR` 指到不存在的路徑時，triage 印 mid。
另外要重跑既有 test/*.sh 全部通過。
