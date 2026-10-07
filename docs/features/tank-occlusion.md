# 玩家建築遮蔽淡出與敵車視野內透視輪廓

日期：2026-10-06（原輪 2026-10-05 的親測續修）；產品決策／人員產品驗收人：leadi。授權見 [ITERATION.md](../agent-collab/ITERATION.md)，接手見 [HANDOFF.md](../agent-collab/HANDOFF.md)。本次 Base 為 [`main dc8858991316fa3207e9b6d5765e1e8cc3df89e1`](https://github.com/leadingtw273/tank-skirmish/commit/dc8858991316fa3207e9b6d5765e1e8cc3df89e1)（已合併 [PR #127](https://github.com/leadingtw273/tank-skirmish/pull/127)），來源樹 `f0b14b98396f87bfbe71513252dbbdda2c830336`。

狀態：PR #127 已工程交付；LEA-194 因玩家透視邊緣與角度閃爍回饋重開續修，LEA-195 已完成、原依賴保留，人員產品驗收 `needs_changes`。上一版工程交付與本次候選分開：2026-10-05 已交付版有完整品質 73／73 命令、136 測試、84 項圖形工程檢查與兩次 CI success；本次候選仍整合／驗證中，不能套用歷史 PASS。細節見 [已交付歷史](../agent-collab/ITERATION.md#本次續修與已交付歷史)。本文不宣稱新版 source 已正式套用、source review 成功或 leadi 已 accepted。

目前工單與依賴以 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194)、[LEA-195](https://linear.app/leadingtw273/issue/LEA-195) 為準，版本／PR／CI／review／merge 以 GitHub 實際紀錄為準。歷史視覺調整曾於 2026-10-06 重開兩單，原依賴保留；該次精確計畫文字審查已明確核准，2026-10-06 Claude（`claude-opus-5-5`）單次有效 result 為 approve／0 blocker，只讀該計畫且 SHA／mtime 不變；六項 advisory 按原有限 AC 觀察，不新增 scope。作者自檢不代替 fresh-context 驗收、完整品質或 Windows 親測。核准不包含 code、材質、PNG 或私素材外送。

本次玩家視覺觀察與驗收優先使用主場景 `res://src/main.tscn`；leadi 確認問題發生於主場景，訓練場不是本次新增的玩家視覺 AC。原 P1–P3／E1–E3 與既有回歸入口保留，敵方範圍不擴張。

本次完整原文回饋與範圍內續修授權見 [ITERATION.md](../agent-collab/ITERATION.md#本輪自包含裁決引用)。本機分支 `fix/lea194-player-fade-boundary` 正修正、待驗，尚未交付新版 main。

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

本次玩家邊緣續修待驗：既有 opaque／soft 雙 pass 使用同一半徑，但透明 pass 的前後多個表面可能疊加混色；只關閉背面或 foreground gate 的對照不足以排除此問題。修正正針對當下淡出的建築建立同相機的原始最近表面深度資料，讓 soft pass 僅混合最近表面。保留共同 5m、1 個 render pixel 的 opaque 外緣、圈外原 PBR／深度與完整陰影，以及後方建築／Tank4 包絡判斷；敵方、碰撞與實體遮彈不改。此處記錄修正方向，不代表實作、圖形驗收或 source review 已通過。

沿用透明 SubViewport／World3D、主相機及 mesh transform，同步原四車 skin／bone pose 與 alpha silhouette。Mask RGB 編碼有限真實部件類別；Canvas 在 true mask 內取相鄰部件界線與原約 2px 外緣，只輸出稀疏紅線，不填紅、不畫三角 wireframe、不用 experimental stencil。

部件按四車現有精確名稱分類，如左右 `TrackMesh`、`Tank_Gun`、`Tank_Turret`、`Tank_body`。Tank4 固定上車體即使屬 HullVisual，仍以真實 `Tank_Turret` 本體分類；Tank1 無獨立 turret mesh，只呈現真實 gun／hull／左右履帶界線，不虛構砲塔。原模型、joint、skin 與物理部件不改。

既有 45 joints 履帶 pose／skin 同步保持，不新增動畫框架。正式 Godot 4.7.1 Forward+，Windows 親測；Linux Vulkan 僅作工程圖形驗證，不擴 GL 或跨 renderer 相容性義務。直接技術前提失效、需超出四車拓撲或新增玩法／平台承諾時停碼升回決策，不默默改寫 AC。

拾取仍檢查原 alpha silhouette 與約 2px 線寬鄰域；邊緣可用鄰域 ray。無對應部位實體 hit 時沿用該車表面點中投影最接近命中像素者，仍回真目標世界點。本次玩家邊緣修正可回滾至 PR #127 已交付基線；較早整輪呈現調整的回滾基線為 PR #126，沒有資料 migration。

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

私素材僅供本機開發且保持 ignored，不提交或外送私素材、含素材截圖、憑證或個人私有路徑。歷史 PR #126、PR #127 及各自同版 main 私素材 CI 的 grant 均已耗用，本次新 Head 不能延用；本次來源／Claude 外送與新私素材 CI 尚未核准。新網路私素材 CI 依 [local-private-ci.md](../local-private-ci.md)，封存後另列 exact PR／Head／run／attempt 授權包；缺權限只暫停該段，不跳過完整品質或平台 gate。計畫文字 review 已核准不代表新版工程或人員驗收通過。


## 2026-10-06 敵車真幾何細節與受損煙候選

leadi 要求增加真車身／砲塔裝飾線以辨識車型，並選定「紅色煙霧線條輪廓」。本輪沿 LEA-195，精確基線為 `4a49059a279c0786d42a2f286905dd8fa6ac8640`／tree `3dab4c2892039fea754de23b80f0944f6aa7fc57`；凍結規格 `enemy-outline-detail-spec-plan-v1.md` SHA256 `5f2077632819261d881dac708520513df0c008dd9c466b41ac80311efe9810d6`。一次已核准計畫外送由實際 `claude-opus-5-5` 審查 approve／0 blocker；只外送指定 spec 的核准已耗用，不涵蓋來源、PNG、素材、CI、遠端推送或 main。

同一 Outline 附屬幾何 viewport 採線性 HDR oct view-normal RG、有界相對線性 depth B、opaque occupancy；深度 bounds 依來源幾何和相機更新，加 0.5m margin。原 part／alpha viewport、mask_image 與 picking 程式保持。內線比較法線折角或扣除平面斜率的 depth discontinuity，約 1px、alpha 0.75；外框約 2px、alpha 1.0。Tank1 沒有獨立砲塔，Tank4 固定上車體沿真部件名稱，不創配件或三角 wireframe。

每敵獨立煙 viewport 借原可見 Smoke 的 `get_base()`、建立自己的 RenderingServer instance，沿同尺寸／投影／camera transform；含仍可見的 retired stage。來源粒子、材質及 seed 完全只讀，不複製 emitter、不 restart、不釋放來源 base。煙 alpha 差抽線最高 0.35，原 actor alpha interior 優先；煙不進瞄準 mask。沿原整敵 can_see／camera building gate 與各敵 window，不新增全場／屋頂逐 pixel 深度系統。

作者本機 Forward+ Vulkan／llvmpipe 真渲染證據保存於 `agent-team/tmp/tank-enemy-outline-detail-20261006/writer/`，未外送。自然訓練場 `startup-training.png` 沒有移動玩家／相機；其他案例使用隔離 catalog 真車、固定相機／姿態及原 Health／DamageReceiver。

| 有限 AC | 作者證據與限制 |
| --- | --- |
| G1／G2 | 四車各兩處真來源 ROI 出現新內線；砲管 CPU ray／triangle 對照共 706 samples，max normal 0.252°、depth 0.00555m。四車可見平面 ROI 新紅 0；Tank1 真 posed body surface 1 triangle 174 的 5×5 ROI 共 25 可見 pixels、新紅 0。原選面 harness 過嚴 normal 篩選未找到 Tank1 的紀錄保留，補正只讀回既有真渲染資料，沒有改 shader。 |
| G3 | 四車 aiming alpha 逐像素相同、所有可見五部件（Tank1 無 upper）／空白有限 pick 結果相同。首輪完整 RGBA 嚴格比對仍記 FAIL：Tank1／3／4 各 1／3／2 個 body／left_track 交界 RGB 差，alpha 同 1；CPU 真 posed 深度差 0.000002–0.000267m。額外一輪原 mask 重複及三實例配置無差量；未改原材料／排序或弱化 raw 比較，root 已依 alpha／pick 產品義務暫列 renderer advisory，仍由 fresh 獨立核對。 |
| S1／S2 | 未受損煙 0；真 75／50／25% 煙 alpha 非方框、source 參數同值。雙敵來源與各自窗口保持；2781 smoke-only pixels 中有限 12 picks 為 0 命中，最大煙線 alpha 0.349；原 actor interior 的新增煙線 0。原資格 gate 由相關既有 smoke 覆蓋，沒有逐像素屋頂義務。 |
| L1／R1 | 真 retired stage 2／2 可見煙代理、換車／姿態／resize／active death／敵移除／場景退出有限案例通過，自有 RID 清理後來源存活。原玩家淡出、AI／LOS／物理、模型、道路與訓練場配置無來源變更。退出 Texture RID／RenderingServer 噪音保留原始 log，未宣稱根因已修復。 |

以上為作者自驗，非 fresh-context 最終驗收或 leadi accepted。來源尚待 root 封存提交及 fresh-context 同版驗證，正式 Windows 預覽未改；人驗維持 needs_changes。未跑全量品質／Windows／跨渲染器效能。

本次七個直接 headless checks（tank_occlusion、enemy_occlusion、aim_cursor、partial_visibility、partial_visibility_combat、enemy_combat、training_ground）皆 exit 0，結果及原 log 見 writer 的 `headless-result.json`。`git diff --check` exit 0；11 檔變更皆在准許範圍，原 232 個 UID 的內容／owner／mode 保持，新增 3 個 UID 唯一、owner 1000／group 1000／0644。尚未 stage／commit，沒有全量品質與 Windows 人驗。


## 2026-10-06 殘骸灰色透視與訓練場玩家淡出候選

leadi 要求「摧毀後該敵方坦克透視照常顯示，線條包含煙霧線條都改成淡灰色」，並回報訓練場玩家被建築遮住後缺少透視。本輪基線 `7d9b61f3e40ad7933ae6b285d0c384b4845a2b88`／tree `23e2d04273f8ea6031aefb0db7b39ede37405860`；鎖定 `tank-wreck-player-occlusion-20261006/plan-v1.md` SHA256 `2807778365f2957ac71812a83c7e28a432912c3ea09a9d4418dcdb66badcbf4a`（7650 bytes）。使用者單次指定 plan 外送核准 `call_6qkat1kJCLrQK0y28leVGmYG` 已取得實際 Claude approve／0 blocker，root 將五項 advisory 留在原 W1–R1 範圍；grant 已耗用，不涵蓋來源／PNG／素材外送、新 CI、push 或 main。

敵車呈現資格只要求 target 仍存在，保留原 TankVision／LOS／camera building gate／共用 5m；死亡只讀原 Health，私有 `line_color` 從原紅色改中性 RGB 0.72。車體、裝飾、真 Smoke 共用色，原 detail 0.75／smoke 0.35／mask shape 不動；depleted 不再當成 tree exit。透視 `pick` 與 resolver 分別維持 live gate，殘骸不能成為透視瞄準 target，普通世界物理射線與碰撞沿原行為。真移除仍清理自有 pass，沒有改 Health、AI、damage、geometry／smoke helper 或粒子。

玩家問題的兩個來源是訓練 atlas 被原 untextured adapter 拒絕，以及九棟 SightBlockers 缺少既有建築群組。本次只支援已確認 opaque albedo atlas 的 UV0／Linear Mipmap／repeat／identity UV，放行 `_gltf_primary_texture_coord=0`，未知 metadata／UV2／normal 等額外 feature 仍拒絕。opaque／soft shader 同採 `source_color` texture RGB 乘原 albedo color，不使用 texture alpha；無貼圖公式、nearest raw HDR／foreground／radial alpha／shadow／5m 保持。場景九個 body 只加既有 `occlusion_building`，位置、模型、碰撞與玩家／相機配置不動。

作者證據只留本機 `agent-team/tmp/tank-wreck-player-occlusion-20261006/writer/`；以下不是 fresh-context 最終驗收。

| 有限 AC | 作者實跑／讀回 |
| --- | --- |
| W1 | 自然入口敵車真受損為紅，Health 歸零後 body/detail／真煙中性灰；旁邊活敵仍紅；`training-dead-gray-smoke.png` 是灰殘骸＋活敵紅線重疊的混合自然場景，不能當作 solo 灰殘骸圖。分離證據為 `dead-gray-lines.png`／`dead-real-smoke.png`。2287 中性／0 非中性線 pixels，真煙 alpha 2192 pixels；真正離開 body 外框鄰域的 smoke-only 線 601 pixels、最高 alpha 0.349。真 Smoke source 模擬參數與 RID 同值，source null 材質以合法 null 讀回。 |
| W2／W3 | 同殘骸一次 range off／recover 與 camera building off／recover 正常回灰；dead 自身 pick 空，重疊旁活敵的合法 resolver 命中不算 dead hit。真 remove、effect exit 自有 callback 清理及其他來源粒子存活通過。無新回滿／並發承諾。 |
| P1 | 原相機 size 100，在入口 (29,0,-12) 與 SouthTwoStory (43,0,-29) 原 ray 命中並識別真建築；surface／nearest proxy 各 1／1、5／5，圈內像素變化 1432／1465。logical viewport 1920×1080、PNG 1280×720，原 camera transform 與世界 5m／logical 54px 保持。PNG 為 `entry-fade.png`、`south-fade.png`。 |
| P2 | 固定同 enemy-overlay 狀態後，兩 atlas amount 0 對原材質的大差異像素均 0；circle 外 entry 的 311 差異皆為合法新增紅輪廓、source surface 剩餘大差異 0，South 圈外大差異 0。CPU 讀回三 atlas＋main 七材質共 10 表面皆接受，兩 shader 保留同 source texture／color，未知 metadata／UV2／normal 拒絕。main 無貼圖 amount 0 大差異 0；原 nearest 與透明梯度程式保持。 |
| R1 | 最終 code 的六直接 headless smoke 均 exit 0、runtime errors 0：tank_occlusion、enemy_occlusion、partial_visibility、partial_visibility_combat、aim_cursor、enemy_combat；只取代舊 dead leaves no outline，其他斷言保留。235 UID 內容／owner／mode 保持，素材無來源變更。 |

原錯誤完整保存：新增 W3 測試曾暴露作者省去 valid short-circuit 的 freed-target TypedArray 回歸（B），已恢復 guard，六 checks 以最終 code 重跑成功。首 GPU 的全畫面 atlas 差異混入 839 個合法紅輪廓 pixels、smoke-only 誤含原 2px 外框、resolver 合法命中旁活敵、null snapshot getter 都是 D 測量錯誤；raw exit 2／log 保留，最多一輪限定 W1／P2 修正後 exit 0，沒有重跑已通過 W2／W3／main 或改產品追假紅。

工程來源待 root 提交封存、fresh-context 同版核對及本機預覽同步；正式 Windows 專案尚未由 writer 修改，人驗仍 needs_changes。未 stage／commit、未跑 full quality／Windows、未外送 source／PNG／私素材。


## 2026-10-07 灰殘骸煙上方矩形板回歸修正

leadi 回報的垂直板來自原火焰 `Flame_Core`：collector 未排除既有 `effect_mesh`，原透明特效材質被車體代理材質蓋成實體 mask／幾何。此次只在共用 `_collect_meshes` 略過已標記的 Mesh，仍遞迴 children；真模型 Quad／裝飾、原世界 FX、獨立真 Smoke、紅／灰色、picking、5m 與玩家淡出不改。既有分類權威是 training_target_controller／training_combat_encounter 的 `effect_mesh` 用法，不新增素材群組或面片型別白名單。

本機作者證據在 `agent-team/tmp/tank-smoke-quad-20261007/writer/`。既有 enemy_occlusion smoke 加入回歸後，舊 collector 真紅 exit 1：16 項 FX mask／geometry 反例；另 1 項量測 D 是死亡後才生成的 `/root/Tank/TankDepletedExplosion/Core` 被誤當初始化模型（原 damage visuals 的死亡一次性爆炸），raw 17 failures 保留。固定初始化模型 identity 後，最終 enemy_occlusion 與 aim_cursor 兩直接 checks 均 exit 0、runtime error 0，真模型及未標記 Quad 子節點控制保留。

固定一台自然入口 training tank2（僅測試 player pose 設為 (0,0,8)，相機不移動）真 Health 100→50→0，Forward+／Vulkan 的 17 項作者量測有 16 項 true：各階段只收 5 個模型／0 effect_mesh；來源定位先鎖定的 Flame_Core 356 像素區域，候選 opaque 為 0；健康真煙 0、受損 760、死亡 1314 像素，死亡中性線 2317／非中性 0；live 本敵命中、dead 空與 smoke-only 0 命中，原 camera size 100／5m 保持。圖片為 `dead-training.png`、`dead-lines.png`、`dead-real-smoke.png`、`dead-part-mask.png`。

該 GPU raw exit 2／log 完整保留，不能稱作者 overall PASS：唯一 D 是把健康前全部 Smoke 的參數跨受損／死亡啟動比較。原 `tank_damage_visuals.gd:90–100` 明確設 local_coords=true 並 restart；同 source/base 的 6 個 Smoke 只在 local_coords／seed 出現差異，seed 與 restart 的因果屬推論。FX mesh／material／layer 及其餘 Smoke 基本參數同值，來源腳本、SmokePass 與全部 235 UID／586 素材 metadata 保持。fresh 入口為本輪 `tank-smoke-quad-20261007/fresh/`，依 Q1–Q3 在固定同 stage 核對原粒子身份／base／穩定參數，不用跨 stage 快照代替驗收。作者不代替 fresh-context 驗收；人驗 needs_changes，待 leadi 親測。
