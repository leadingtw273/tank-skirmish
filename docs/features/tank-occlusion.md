# 玩家建築遮蔽淡出與敵車視野內透視輪廓

日期：2026-10-06（原輪 2026-10-05 的親測續修）；產品決策／人員產品驗收人：leadi。授權見 [ITERATION.md](../agent-collab/ITERATION.md)，接手見 [HANDOFF.md](../agent-collab/HANDOFF.md)。本次 Base 為 [`main f97581214e713627fce93a6a00ad8aae7206c5fc`](https://github.com/leadingtw273/tank-skirmish/commit/f97581214e713627fce93a6a00ad8aae7206c5fc)（已合併 [PR #126](https://github.com/leadingtw273/tank-skirmish/pull/126)），來源樹 `2074e262610c426efadd605bd80b17769ca318a3`。

狀態：本次視覺 AC 已裁決，人員產品驗收 `needs_changes`。上一版工程交付與本次候選分開：2026-10-05 已交付版有完整品質 73／73 命令、136 測試、84 項圖形工程檢查與兩次 CI success；本次候選仍整合／驗證中，不能套用歷史 PASS。細節見 [已交付歷史](../agent-collab/ITERATION.md#本次續修與已交付歷史)。本文不宣稱新版 source 已正式套用、source review 成功或 leadi 已 accepted。

目前工單與依賴以 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194)、[LEA-195](https://linear.app/leadingtw273/issue/LEA-195) 為準，版本／PR／CI／review／merge 以 GitHub 實際紀錄為準。兩單 2026-10-06 已重開為進行中，原依賴保留；精確新計畫文字審查已明確核准，2026-10-06 Claude（`claude-opus-5-5`）單次有效 result 為 approve／0 blocker，只讀該計畫且 SHA／mtime 不變；六項 advisory 按原有限 AC 觀察，不新增 scope。作者自檢不代替 fresh-context 驗收、完整品質或 Windows 親測。核准不包含 code、材質、PNG 或私素材外送。

## 使用者裁決與產品前提

leadi 於 2026-10-05 指定「先修玩家遮蔽透視在修敵人遮蔽透視」，玩家選擇「遮擋建築局部淡出」。敵車資格為「在玩家視野範圍內，這視野取決於選擇坦克的設定，如同AI的視野偵測機制一樣」；外觀為「敵人坦克用紅色線條透視於建築上」，範圍補充為「那個透視範圍或是圈圈半徑就跟玩家的一樣」。同次裁決另確認滑鼠指向透視輪廓可瞄準敵車。

2026-10-06 親測回饋摘要：玩家中心越接近車體越透明且沒有顆粒，僅外緣可有霧狀平滑過渡；範圍更小且常駐，進入掩體自然。敵車紅線除外框亦有真實車體細節，方便瞄準砲塔或履帶。舊「僅外框／interior_red==0」視覺判準由本次明示稀疏部件界線取代，不填滿車體、不畫三角 wireframe。

既有前提維持 Windows 單人 PvE、正交斜俯視與四款 catalog 坦克。元前提四問覆核：目標使用者是既有單人 PvE 玩家；同類遊戲只借鏡構圖；Identity 維持 Tank Skirmish 遊戲；動機是受控車／視野內敵車辨識與操作可讀性。沒有新目標使用者、工具平台或玩法方向裁決。

## ADR：顯示資格與瞄準規則

先玩家局部建築淡出，再整合敵車紅線部件輪廓。玩家由 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194) 承接，玩家工程驗證後接依賴它的 [LEA-195](https://linear.app/leadingtw273/issue/LEA-195)；最終依固定 P1–P3／E1–E3 獨立驗收。工程交付與 leadi 親測分開，人驗保持 needs_changes。

玩家圓窗持續跟隨受控車，前景建築投影 bounds 與窗相交即處理，不等車體遮擋 ray 首次命中；沒有建築不畫額外 UI 圈。單一可調世界半徑預設縮為 5m，沿用原單一 export 與投影函式，隨縮放維持世界尺度；玩家／敵方各以原車體中心投影為圓心，共用半徑。8m 是上一版預設，原共同範圍裁決沒有將它鎖成不可調數值。

玩家中心連續 alpha 為 0 或近 0、無顆粒與 noise／hash／dither；越靠近車體越透明，外緣平滑收回原外觀。圈外保留 opaque base 原 PBR、深度與完整陰影；不將整棟透明，不淡出路面或其他車體。

敵車只有存活、畫面內、被相機建築遮住且玩家 `TankVision.can_see` 為真才啟用輪廓。視野重用所選車型 near 全向半徑、far 砲塔水平視角及逐部位實體 LOS；相機建築遮蔽和玩家砲塔 LOS 分開判斷。全部部位玩家 LOS 被建築阻擋不啟用透視；視野外敵車沿用原顯示，不新增全域隱藏或發現記憶。

敵方在建築前畫約 2px 紅色外框，加真實 gun／turret（存在時）／hull／左右履帶稀疏界線。共同窗外紅線 0，建築不因敵方淡出；沿用有限部位相機射線資格，不新增逐像素場景深度裁切。命中區仍是原 alpha silhouette 實體車體投影及線寬鄰域，不使用 RGB 部件編碼或紅線作新命中面，不改為 AABB。

滑鼠命中啟用輪廓時解析該敵車真實世界點，驅動既有 Aim 砲塔／砲管；未啟用、窗外或視野不符走正常首撞 picking。非目標 RID 略過，不能回牆或其他車的點；空白像素不命中。砲口命中線、Projectile 首撞、建築遮彈與傷害分類保持，沒有穿牆傷害。

被否決方案沿用：整棟永久透明、所有畫面敵人揭秘、敵方局部建築淡出、只畫輪廓不接瞄準及穿牆傷害。本次新增部件界線不改上述 gameplay 邊界。

## 有限工程接點與回滾

遮蔽控制器沿用 `PlayerRuntime.controlled_tank_changed` 與 `CameraController.camera`。敵方 camera 遮擋 gate 沿用既有有限部位射線。玩家改用 scene 內快取的有限 building mesh 投影 bounds 交窗候選，不每幀掃全圖；建築識別仍限 Buildings 容器或既有來源 metadata，不動 collision layer。

玩家前景深度以 root 的 `stable_world_center` 加原 `part_surface_points` 包絡為準，取最遠的 camera-local Z 最小值；缺部位採 fallback centre。Opaque／透明 shader 使用同一 foreground gate，避免淡出車體後方建築；shadow pass 不使用該 gate，保留完整陰影。

每個受影響 mesh 的 surface override 複製原 PBR 屬性與 `cull_disabled`，不改 shared resource。Opaque base 在非 shadow pass 的窗內 discard，移除 hash／dither；相同 geometry 的透明 next_pass 只補窗內平滑 alpha，中心無 noise，圈外不額外混色，也不重複投影陰影。離開交窗範圍還原；受控車 null、離開樹、換車、死亡／重生、退出時清理舊 instance overrides／next_pass。

同一共同 5m 投影窗內保留 1 個 render pixel 的完整 opaque 外緣；base 挖孔與 soft next_pass 漸層採相同內縮支援域。Render pixel 寬度以 `SCREEN_UV * viewport_size` 的 `fwidth` 在分支前計算，對應 logical／render 比例。這只將透明支援域收在原圈內，共同半徑、候選、敵方顯示與拾取圈維持原值；P1 仍以原半徑取圈外，要求差量 0，不新增 radius tolerance 或取樣排除帶，完整陰影保持。縮放驗證、整合 fresh-context 驗收及完整品質尚未完成，不由此實作語意推定 PASS。

沿用透明 SubViewport／World3D、主相機及 mesh transform，同步原四車 skin／bone pose 與 alpha silhouette。Mask RGB 編碼有限真實部件類別；Canvas 在 true mask 內取相鄰部件界線與原約 2px 外緣，只輸出稀疏紅線，不填紅、不畫三角 wireframe、不用 experimental stencil。

部件按四車現有精確名稱分類，如左右 `TrackMesh`、`Tank_Gun`、`Tank_Turret`、`Tank_body`。Tank4 固定上車體即使屬 HullVisual，仍以真實 `Tank_Turret` 本體分類；Tank1 無獨立 turret mesh，只呈現真實 gun／hull／左右履帶界線，不虛構砲塔。原模型、joint、skin 與物理部件不改。

既有 45 joints 履帶 pose／skin 同步保持，不新增動畫框架。正式 Godot 4.7.1 Forward+，Windows 親測；Linux Vulkan 僅作工程圖形驗證，不擴 GL 或跨 renderer 相容性義務。直接技術前提失效、需超出四車拓撲或新增玩法／平台承諾時停碼升回決策，不默默改寫 AC。

拾取仍檢查原 alpha silhouette 與約 2px 線寬鄰域；邊緣可用鄰域 ray。無對應部位實體 hit 時沿用該車表面點中投影最接近命中像素者，仍回真目標世界點。回滾移除本次呈現調整可恢復 PR #126 基線，沒有資料 migration。

## 固定驗收矩陣

| AC | 可客觀驗收的結果 |
| --- | --- |
| P1 | 真主圖四車：中心透明且無顆粒，中心比中段更透明、外緣連續；圈外及同材質他棟保持原外觀，陰影 ROI 與 baseline 不變，碰撞保留。 |
| P2 | 固定移動入／離建築：在車體第一個遮擋 ray 之前，窗與前景建築交界已沿零→低→高透明度連續變化，沒有突然整圈啟動；平移／轉動／縮放跟隨穩定，玩家／敵方共同半徑 5m。 |
| P3 | 四車換車、死亡／重生、null、退出：清理舊 instance overrides／next_pass，原材質還原，沒有殘留。 |
| E1 | 真訓練場四車：窗口內外框與真實 gun／turret（存在時）／hull／左右履帶部件界線可辨識；不填紅、不畫三角網格，圈外紅線 0；alpha silhouette 與原 actor 投影 0 差異。 |
| E2 | 指向 turret／gun 與履帶真像素能解析真目標世界點並經既有 Aim 瞄準；空白像素不命中，砲口實體首撞仍牆，Projectile 遮彈不回歸。 |
| E3 | 原車型 near／far／角度或逐部位 LOS 不符、全 LOS 堵塞、死亡／換車／退出：無紅線／舊拾取；既有 45 joints 履帶 pose 同步保留。 |

玩家工程驗證後整合敵方，再由新 fresh-context 代理依固定矩陣獨立實跑並讀回；最終最新 Head 完整品質與獨立 source review。只依 AC、成品及實跑證據，不沿用作者敘事；作者不自稱驗收，無 fresh context 能力時揭露限制。人驗維持 needs_changes，直到 leadi 親測確認。

## 有限測試入口

本機具備既有私素材與 pinned Godot 後，依 [PROJECT.md](../agent-collab/PROJECT.md) 設定 `GODOT_BIN`，完整入口為 `bash scripts/ci.sh`。以下為既有有限回歸入口；連結存在不等於本次已執行。

| 固定回歸 | 既有檔案 |
| --- | --- |
| 玩家建立與受控車 | [player_spawn_group_smoke.gd](../../tests/player_spawn_group_smoke.gd) |
| 玩家 rigid 整合 | [player_rigid_integration_smoke.gd](../../tests/player_rigid_integration_smoke.gd) |
| 四車執行期 | [player_rigid_variants_runtime_smoke.gd](../../tests/player_rigid_variants_runtime_smoke.gd) |
| 現役訓練場 | [training_ground_smoke.gd](../../tests/training_ground_smoke.gd) |
| 玩家局部窗（必跑） | [tank_occlusion_smoke.gd](../../tests/tank_occlusion_smoke.gd) |
| 敵方輪廓（必跑） | [enemy_occlusion_smoke.gd](../../tests/enemy_occlusion_smoke.gd) |
| 滑鼠瞄準（必跑） | [aim_cursor_smoke.gd](../../tests/aim_cursor_smoke.gd) |
| 部位可見性（必跑） | [partial_visibility_smoke.gd](../../tests/partial_visibility_smoke.gd) |
| 部位可見性戰鬥（必跑） | [partial_visibility_combat_smoke.gd](../../tests/partial_visibility_combat_smoke.gd) |
| 敵方戰鬥（必跑） | [enemy_combat_smoke.gd](../../tests/enemy_combat_smoke.gd) |

六個直接 smoke 與完整品質均須對本次候選實跑。圖形 harness 複製到新輸出目錄，不覆寫上一版圖／報告。單一 smoke 範例：`"$GODOT_BIN" --headless --path . --script res://tests/tank_occlusion_smoke.gd`；按表替換其餘檔名。Headless shader 建立成功不代替視覺驗收，畫面在本機檢查，不外送。正式主圖沒有敵方 Encounter，敵方固定案例限現役訓練場與有限測試場景。

## 術語

沿用既有三個術語，依本次已裁決呈現調整定義；不依賴個人記憶或私有路徑。

| 術語 | 定義 | 專案／首次確認 |
| --- | --- | --- |
| 玩家建築遮蔽淡出 | 持續跟隨受控車的圓窗與前景建築投影相交時，窗口內平滑透明、中心無顆粒；窗口外外觀、完整陰影、實體碰撞與射擊阻擋保留。 | tank-skirmish／2026-10-05；2026-10-06 親測續修 |
| 敵車視野內透視輪廓 | 依受控車型 TankVision 距離、砲塔水平視角及實體 LOS，對符合資格且被相機建築遮住的敵車顯示建築前紅色外框與真實稀疏部件界線；窗口半徑共用玩家設定。 | tank-skirmish／2026-10-05；2026-10-06 親測續修 |
| 透視輪廓瞄準 | 滑鼠命中啟用敵車透視輪廓的原 alpha silhouette 或線寬鄰域時，解析真目標世界點並驅動既有砲塔／砲管；砲彈仍受實體建築阻擋。 | tank-skirmish／2026-10-05 |

## 保持條件、排除與安全

只調整執行期顯示與既有瞄準接點；碰撞、砲彈、AI、尋路、TankVision 實體 LOS、AI 發現／開火守門與傷害分類保持。不改私有來源素材／貼圖、地圖布局、光照、天氣、鏡頭構圖或取消的 demo；不新增迷霧、發現記憶、全域敵人隱藏、穿牆傷害、addon、背景 registration 或舊 Team Job。可信邊界維持本機單人遊戲與原四車，不擴惡意插件、多人競態、崩潰恢復、來源格式遷移或跨 renderer 義務。

已核可範圍內普通開發、修正、驗證、獨立 review 與真實 gate 後正常 merge 可自主續行；對外發布、產品方向、平台受控設定及素材外送邊界不擴大。`quality`、required `agent-team/review` 與全部平台條件保持，reviewed Head／必要 CI 須對應最新 Head，不能用歷史 PASS 或文件代替。Review advisory 依 [WORKFLOW.md](../agent-collab/WORKFLOW.md) 分本單 blocker／後續 backlog／忽略，不自動擴 AC。

私素材僅供本機開發且保持 ignored，不提交或外送私素材、含素材截圖、憑證或個人私有路徑。上一版 PR #126 與同版 main 私素材 CI 的兩次 grant 已耗用，本輪不能延用。新網路私素材 CI 依 [local-private-ci.md](../local-private-ci.md)，封存後另列 exact PR／Head／run／attempt 授權包；缺權限只暫停該段，不跳過完整品質或平台 gate。計畫文字 review 已核准不代表新版工程或人員驗收通過。
