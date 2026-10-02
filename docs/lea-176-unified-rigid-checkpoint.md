# LEA-176 敵我共用剛體檢查點 — 2026-09-23

## 目前狀態：建築旁可見交戰掉幀待修復

候選剪枝續作仍未達標：Linux 134/240、Windows 154/240 次 budget。局部測試通過不可當效能完成；詳見 [候選剪枝結果](lea-176-candidate-pruning-result.md)。待重新裁決計算安排，不再追加特殊碰撞快判。

最新人工回報後的兩組真實姿態測試，部位空隙排除修正仍未達效能門檻：問題位置 140/240 次超時、平均 15.30ms、p95 20.05ms。局部 flat 正負例通過不等於效能修好；詳見開發狀態入口與 `/tmp/lea176-visible-after.log`。以下為前次有限場景通過紀錄。

最新 [平地轉向結果](lea-176-rigid-flat-result.md)：Linux／Windows真追擊240幀零budget，四車24地形案例與玩家原操作曲線通過，fresh-context驗收PASS。整單未結案，仍待人工確認。

## 前次人工實測失敗紀錄

真訓練場看到玩家後預測持續超時，局部支撐點快取不足以解決；Linux／Windows追擊測試仍FAIL。詳見 [轉向超時檢查點](lea-176-turn-budget-checkpoint.md)。下列24案通過為直線地形範圍，不可當整體追擊已驗收。

## 前次自動地形驗收紀錄

2026-09-23：已依使用者裁決改為可跨地形分類，撤除上一版完整淨空抬升 fallback。四車共 24 個 AI 地形案例通過，既有 720-frame／穿透門檻未放寬；整單尚未結案，隱蔽受擊查看仍另待處理。

- 使用者明確核可 1cm 建模容差：辨識上限為既有 50cm 加 1cm。實際 Road 碰撞最高點為 50.53cm，不以視覺網格代替碰撞量測；不改真實碰撞、推力或爬階能力。
- 新增 `rigid_terrain_classifier.gd`：僅靜態、非移動物件；檢查整個 body 所有啟用碰撞形狀的世界座標高度。未知形狀、無支撐、查詢超額等不放行；同 RID 地板加高牆仍阻擋。
- 放行僅限車身與低地形接觸；砲塔／砲管維持完整查詢，原生接觸紀錄與無進展脫困保留。快取僅存活於同一預測 snapshot。
- AI 支撐射線向下查詢包含一個既有階差高度，避免預測姿態跨路肩後漏掉低處支撐；僅純預測，不寫實體位置、速度或懸吊參數。
- 完整矩陣 `/tmp/lea176-classification-final.log`：24 PASS、`RIGID_AI_TERRAIN failures=0`、exit 0，無 SCRIPT ERROR。
- 玩家矩陣 `/tmp/lea176-classification-player.log`：failures=0；四款 `/tmp/lea176-classification-curve-tank{1,2,3,4}.log` 的 CURVE／CURVE_PARAMS 與先前已驗基線逐筆一致。
- catalog、training_ground、training_rigid_player、rigid_ai_driving smoke 通過，證據 `/tmp/lea176-classification-*-smoke.log`（實際檔名使用底線，如 `tank_catalog_smoke`）；原 AI smoke 覆蓋限制仍見下方歷史紀錄，不宣稱完整戰鬥回歸。
- fresh-context 最終獨立驗收 PASS：`/tmp/lea176-classification-acceptance-final.md`；獨立重跑分類、負例與 Tank2 六案皆 exit 0、無 SCRIPT ERROR。
- Windows `/tmp/lea176-classification-windows-boundary.log`：高牆、gun-only、同 RID 地板加牆皆阻擋，failures=0、exit 0。
- Claude Opus 唯讀方案複審已完成：採納完整碰撞形狀與高度邊界檢查；既有無進展偵測可接回脫困，未新增重複計時機制。計畫與裁決分別為 `/tmp/lea176-terrain-classification-plan.md`、`/tmp/lea176-terrain-classification-decisions.md`。

## 以下為修正前歷史紀錄，不代表目前狀態

### 2026-09-23 路肩接觸方案：已獲核可並完成一次有界實作，仍未交付

使用者核可「高牆與砲管維持預防、可跨路肩允許實際剛體接觸嘗試」後，新增 hull-only 完整形狀淨空 fallback。正常預測受阻時，必須確認阻擋部位屬車身、有合法支撐、查詢未超額，才檢查最多 0.5m 上抬／前進／落地的完整形狀候選。候選不寫回實體，實際施力核心未改，未排除地形 RID。

封閉範圍 `/tmp/lea176-curb-contact-packet.md`；本輪產品變更僅 `src/actors/rigid_tank/rigid_ground_prediction.gd`。

- Tank2 原六案由 failures=6 改為 **failures=4**，exit 1：21cm 前進 206/720 frames、倒車 346/720 frames 通過；50cm 前後及 Road 兩側仍失敗。證據 `/tmp/lea176-curb-attempt-tank2.log`。不可把兩案改善稱為 AI 地形整合完成。
- 玩家四款原接觸矩陣 `RIGID_VARIANTS_CONTACT failures=0`，證據 `/tmp/lea176-curb-player-regression.log`。
- 剛體 AI 基本駕駛／戰鬥 smoke `RIGID_AI failures=0`，證據 `/tmp/lea176-curb-driving-regression.log`；覆蓋限制仍同下文。
- 四款固定輸入曲線各 36 筆及參數列，與上輪 live／封存基線逐筆一致：`/tmp/lea176-curb-curve-tank{1,2,3,4}.log`。四次 exit 0、沒有 SCRIPT ERROR。
- fresh-context 唯讀驗收 `/tmp/lea176-curb-checkpoint-verify.md`：安全程式路徑保留，但四個地形 blocker 使總判定 FAIL。
- 新增 `tests/rigid_ai_curb_boundary_smoke.gd` 並經 fresh-context 獨立實跑：高牆、側向 gun-only、同 RID 地板＋牆三負例皆 blocked／零指令／at_cap=false，exit 0、failures=0；gun-only 先證明有砲管命中且無車身命中，不以超時取巧。
- 單案唯讀追加診斷 `/tmp/lea176-curb-50-diagnostic.md`：50cm 前進在開始移動後 frame 7 首次 blocked，原因為預測未來 1.9 秒的 left_track 完整 hull cast（fraction 0.2578125），不是當前接觸恢復策略：initial_contacts 空、contact=false、at_cap=false。cast 未提供 collider RID，不猜命中哪一個 collider。這證實仍是未來幾何路徑拒絕，尚非已完成的路肩接觸辨識。

按照本輪一次有界嘗試條件，已停止追加產品修補，保留失敗案例，不再提高幾何門檻或推力。不對外宣稱可驗收，不重開編輯器冒充成品。

四款玩家人工驗收已通過；本輪依核可實作敵我共用剛體與車型 ID 清單。**不是完整交付，AI 越階/道路預判仍失敗，沒有開啟遊戲宣稱可驗收。**

## 本輪已落地

- `src/actors/tank/tank_catalog.gd`：四款 ID、donor 與已核可推力/後座唯一入口；variant 僅指定 ID。
- 主圖與訓練場選初始玩家 ID；選車靶、敵車循環、玩家同款重生從 ID 取得車型。舊 PackedScene API 保留給既有相容測試，不由正式地圖選新舊。
- 訓練靶為 frozen rigid，敵車/玩家使用同款 dynamic rigid；模型/損傷 donor 的 CharacterBody 子樹不具物理碰撞或獨立移動權。
- 共用 actor 提供 AI 真實速度、接觸、車型數值、幾何/砲塔與視野介面；AI 不直接寫實體速度/姿態。
- 近似候選預測與 live 施力分離；玩家既有 force core 未改。新增側滑近似、完整形狀碰撞/支撐候選查詢。

## 驗證證據與限制

Linux 通過：catalog、training_ground、training_rigid_player、training_range、player_spawn_group；玩家四款 contact/aim/recoil/runtime；原 native budget/passive friction/feel/tread；新 rigid_ai_driving_smoke。
Windows：rigid_ai_driving_smoke exit 0，failures=0。
主代理紀錄 `/tmp/lea176-unified-*.log`；接線測試 `/tmp/lea177-training-{ground,rigid-player}-smoke.log`。

Fresh-context 四個指定 smoke 通過且無 SCRIPT ERROR：`/tmp/lea176-checkpoint-fresh.md`。
**覆蓋缺口**：新 AI smoke 四款只驗生成/介面，實際駕駛主要用 Tank1；倒車缺有方向的位移斷言；砲管只驗 snapshot 非零 range，尚未驗真正砲管接觸 index。不可將此 smoke 宣稱為四車 AI 全驗收，後續需補齊既有 AC（不是新增 scope）。

四款玩家各兩次修改前封存曲線、各一次本輪 live 曲線逐位元相同。`/tmp/lea176-unified-baseline/README.md` 與 `commands.md` 保存來源/命令；非核心 scaffold 經核可使用未變動檔案，前後 48 項 SHA 一致。證據僅覆蓋本次 capture 時點。

## 直接 blocker

`tests/rigid_ai_terrain_smoke.gd -- Tank2` 在原指定 720 frames / penetration 門檻下 6 案失敗：21cm 前後、50cm 前後、Road 兩側。最新 `/tmp/lea176-unified-ai-terrain-sweep.log`：21cm 與道路 blocked720；50cm前向 clear177/blocked543，停 x=3.455；反向 clear218/blocked502，停 x=3.434。非超時、非提高推力可解的證據。

三次實作為：四點支撐姿態估算；取樣移至低處完整幾何前後緣；水平/下降掃掠拆分。皆仍被幾何拒絕。依停止規則不做第四次微調。
隱蔽受擊查看原紅燈另存 `/tmp/lea176-unified-baseline/enemy_combat_smoke-known-red.log`，本輪未處理也未宣稱整套 enemy_combat 綠燈。

## scope review 與下一個裁決

用戶已核可本工作後續第二模型 review。Opus 有效結果見 `/tmp/lea176-rigid-terrain-scope-review.jsonl`，摘要输入 `/tmp/lea176-rigid-terrain-scope-review.md`。
Reviewer 建議 B：把地形幾何查詢當近似可行性，爬階所需接觸不能一律等同禁行；只一次有界嘗試，不過則拆後續。其根因是摘要推論，未直接讀碼，不當作已證實。
主代理不採納「所有幾何 blocked 都不能阻止命令」的全面放行說法：牆與砲管預警是既有使用者需求；更不採納以簡單法線或高度門檻跳過障礙。若調整，須明確區分可跨路肩接觸嘗試與牆/砲管風險，保留缺 safe 停車與實際完整碰撞。
待使用者裁決此行為邊界後才能建立新的封閉實作 packet；禁止把 reviewer advisory 當作自動核可擴充。

## 保存

修改前 archive `/tmp/lea176-before-unified-rigid-20260923.tar.gz`，SHA256 `6bb19fe7c2b0ef28a3c05bdbd1855df4b2cc6d78a673c4b20b331f7ba87589e6`。
工作樹原本大量未提交變更皆保留；未 commit、未推送、未改素材或地圖布局。Windows Editor 56240 已正常關閉，未強制終止或丟棄未儲存內容；因尚未完成，不自動開啟成品驗收。
