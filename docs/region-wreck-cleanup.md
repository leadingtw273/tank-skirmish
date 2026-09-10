# Task 5 改案：固定區域偵測與殘骸清除

## 狀態與優先順序

產品規則已由 leadi 逐題核可；技術計畫已完成單輪跨模型 review 與 root 證據核對，使用者已於 2026-09-10 回覆「可」核可開工，目前實作、本機自動化與真畫面驗證已通過，leadi 已於 2026-09-10 明確回覆「驗收通過」，Task 5 人類驗收完成；使用者明確同意外傳本次四張截圖後，Gemini 唯讀視覺複審已通過。本案取代 partial-visibility-collision-plan Task 5 中「重生前依新車各 shape 清除相交殘骸」的做法；不推翻 Task 1–4 已驗收結果。

## Context／四問覆核

- 目標使用者仍為 leadi 編輯與試玩 Windows PC 單人坦克遊戲；新增的區域編輯工作仍由同一位使用者操作，沒有多人或外部服務。
- 類比為遊戲編輯器中可擺放的觸發區域，不是新的全域規則引擎。
- Identity 維持產品優先的 Tank Skirmish；保留可重用的區域偵測，但不預先實作尚未需要的規則種類。
- 動機由「新部位碰撞下安全清場」更新為「清楚、可編輯、可重用的持續區域規則」。其餘前提不變。

## ADR

### 背景

原 Task 5 打算在重生時，依新車全部碰撞形狀查詢並清除相交的舊玩家殘骸。leadi 改提固定綠色區塊，並指出未來會常使用區域性規則。

### 決策

1. 區域為固定、可在 Godot 編輯器擺放與調整大小的 3D 盒形偵測體；綠色範圍只在編輯器顯示，遊戲中不可見且不形成實體阻擋。
2. 區域持續生效，不由玩家重生事件觸發。任一殘骸有效碰撞形狀與區域產生重疊，就清除整台殘骸；不是以車身中心或整台車完全進入判定。
3. 活坦克先進區再死亡也須清除；活坦克、建築、地形與砲彈不因這個規則被刪除。清除對象不區分玩家或敵車，但限同一場遊戲既有的坦克殘骸。
4. 「立即」以偵測到的 physics 更新排程安全移除為準，允許引擎一步碰撞同步與 deferred／queue_free，不引入人為等待或等到三秒重生才清除。
5. 重用邊界只做「範圍與偵測」及「清除殘骸用途」的責任分離；優先使用 Godot 原生區域能力，不新增規則資料庫、事件匯流排、插件框架或其他尚未需要的區域效果。
6. 本次在玩家出生位置配置一個清除區。區域外殘骸保留；取消同場舊重生時額外清除機制，避免綠區之外仍被隱性清場。
7. 重生與區域內殘骸清除是兩個獨立流程（使用者追加裁決）：重生不依賴殘骸存在，清除不負責重生或計時。原有三秒同款滿血中央重生、兩秒可操作無敵閃爍、換車、鏡頭與 AI 目標／射擊來源重綁維持。活坦克占出生位置時維持既有行為，不移除、不推開、不新增等待或改點重生。

### 被否決的替代方案

- 每次重生依新車部位形狀查詢：使用者改選固定區域，毋須再以新車幾何決定清場邊界。
- 只在進入區域瞬間判斷死亡：漏掉先進區後死亡的正常情境。
- 遊戲中一直顯示綠區：使用者明確要求只在編輯器顯示。
- 預先建通用規則引擎或活車避讓系統：超出本次核可需求。

### 影響

清除時機與範圍屬明確玩法改變；區域內被擊毀的坦克不再長期保留殘骸。死亡到重生流程不能依賴殘骸節點持續存活；區域只負責清除，不接管玩家重生或 AI 決策。

## 澄清清單

- [x] 持續清除還是只在重生前清除？回答：「只要偵測到就清除，這種區域性規則在未來可能會很常用到」。影響：改為可重用區域偵測的持續用途。
- [x] 綠區顯示時機？回答：「只在編輯器顯示範圍」。影響：runtime 不顯示區域視覺。
- [x] 活車在出生點占位是否增加處理？回答：「可以」（接受維持既有行為、不額外處理）。影響：不新增活車排除／推離／重生避讓。
- [x] 四問覆核：同一使用者、產品定位與單人場景不變；動機新增可重用區域編輯，不擴成規則框架。

## 固定驗收矩陣（不擴增）

- Z1：區域可在編輯器搬移、調整尺寸，綠色顯示與實際盒形範圍一致；真遊戲畫面不顯示綠區，活車可穿越區域。
- Z2：四車真殘骸的任一部位與區域重疊即移除；至少一案車身中心在外、只有部位碰撞進區。旁邊未重疊殘骸保留。
- Z3：活車先在區內停留，經既有傷害／死亡流程變成殘骸後清除；活車存活期間不刪。另驗已死亡殘骸進區，以及區域啟動時已在區內的殘骸。
- Z4：同區三台殘骸均清除；一台多 shape 仍只清除該台，不擴到區外其他物件。以兩個區域實例確認位置／尺寸與用途不依賴唯一全域節點。
- Z5：玩家在區內死亡且殘骸提早移除，仍於既有三秒後同款滿血中央重生並有兩秒免傷閃爍；等待期鏡頭保留當前位置、無失效引用錯誤。區外殘骸不因重生而清除。換車／AI 目標與射擊來源沿新實例重綁；敵車被清除後既有粉色切換靶仍能產生下一型敵車，不新增自動敵車重生。
- R1：保留受擊側查看、中心→命中點、既有換車／重生與其他 baseline 斷言；只更新被區域規則取代的重生清骸斷言。
- Fresh-context 驗收、相關既有 smoke 與完整 CI。編輯器／runtime 視覺須真畫面證據，不用 headless 代替。

## 邊界

可信單人本地 Godot 場景，有限坦克數；不新增多人、保存／恢復、跨場景全域掃描、任意規則DSL、無限高速穿越保證、實體碰撞精度變更或活車出生避讓。區域使用原生物理重疊語意，不用離地無限柱體、不以AABB中心取代部位碰撞。

## 技術接線與封閉 allowlist

### 現況證據（唯讀 preflight，尚非功能驗收）

- `HealthComponent.apply_damage` 在歸零時同步發出 `depleted`（health_component.gd:25–32）；沒有另一個 destroyed event。
- Encounter `_on_player_depleted` 已在死亡當刻保存 `scene_file_path` 的 PackedScene 並啟動三秒倒數（training_combat_encounter.gd:119–142）。但 Main `_replace_player_tank_at` 要求舊 `Tank` 節點存在（main.gd:34–45）；提早移除死亡車會使目前重生失敗。
- 舊 `player_wreck` group 直到三秒後替換舊車才加入（main.gd:65–76）；不能用這個 group 作為唯一清除資格，否則會違反立即清除。改以真 Tank 腳本身分＋HealthComponent.current_health ≤0 判斷，不新增死亡資料模型。
- PlayerRuntime 不接受 null 且失去車會 error（player_runtime.gd:33–36、65–68）；Camera 跟隨更新對失效 target 會 return，但 setter 會解參考 null（camera_controller.gd:48–55）。需要合法的暫時空綁。
- Encounter `_bind_player` 不接受 null、`_cycle_enemy` 不接受舊 enemy 已移除；需補上述新規則直接導致的正常狀態。CombatRuntime 已以 tree_exiting 自動移除射擊來源（combat_runtime.gd:79–94），沿用此機制，不新增 registry。

### 鎖定的最小方案

1. `RegionVolume` 為可實例化的 Area3D 場景：一個 BoxShape3D、編輯器綠色半透明提示與 `@tool` 尺寸同步。`size: Vector3` 為尺寸單一來源；位置／旋轉使用原生 Node3D transform，不用縮放變形。碰撞 layer=0、mask=1、monitoring=true；只有 runtime 執行偵測，editor 絕不刪物件。提示 mesh 預設隱藏，只在 `Engine.is_editor_hint()` 時顯示，runtime 不顯示綠色。使用 Area3D 原生 body 重疊 API，不自建進出事件系統。
2. 獨立 `WreckCleanupRule` 子節點：明確引用所屬 Area3D 與當場根節點，每 physics update 讀取區內 body；只對當場根後代、有效 Tank 腳本實例、Health 歸零者收集去重後 queue_free。跳過 queued-for-deletion 的物件；不在傷害 callback 中直接 free，不掃全場殘骸、不維護另一份永久名單。
3. 組合為 `wreck_cleanup_zone.tscn`，在訓練場 PlayerSpawnPoint 下放一個實例。初始盒形 24×8×24m，底部與重生點 Y 對齊（local center Y=4），跟隨 marker 的編輯器位置／朝向；驗四車在預設重生姿態可容納，不搬移既有建築／靶位。
4. PlayerRuntime 的 `set_controlled_tank(null)` 成為正常暫時空綁：停止控制、解除舊 shot 與 tree_exiting 接線、清空 Controller／Aim／Presentation／Camera 引用、隱藏瞄準呈現，再發出 `controlled_tank_changed(null)`。綁新車仍走既有入口並可恢復；以當前受控車的 tree_exiting 偵測提前移除，不讓區域元件認識玩家流程。
5. Camera setter 接受 null 時停止跟隨但不改鏡頭位置／初始構圖資料；AimPresentation 空綁隱藏既有線條與框，不留死車的繪製結果。Encounter 收到 null 只清目標／暫停，保留已保存車型、三秒倒數與既有無敵時間語意；不在空綁時再次觸發死亡。
6. Main 重生入口允許舊車已不存在，仍可實例化新車、綁 PlayerRuntime／CombatRuntime／履帶效果並重設鏡頭；位置／朝向沿用 Encounter 呼叫時傳入的 `player_spawn_point.global_transform`，不保存死亡位置、不查舊車姿態；有效舊車的原換車分支保持。移除舊 `_clear_spawn_wrecks` 及呼叫，不留下區外第二套清骸規則。Encounter 切換敵車時只在舊敵車仍有效才解註冊／remove／queue_free，既有車型索引與重置點不變。

### Allowlist

- 新增 `src/world/regions/region_volume.gd`、`region_volume.tscn`、`wreck_cleanup_rule.gd`、`wreck_cleanup_zone.tscn` 與必要 uid：範圍、editor 視覺與獨立用途。
- 修改 `src/main.gd`：移除舊清骸與支援無舊車重生。
- 修改 `src/player/player_runtime.gd`、`src/camera/camera_controller.gd`、`src/player/aim_presentation.gd`：僅上述暫時空綁與重綁，不調操控、瞄準或相機手感。
- 修改 `src/world/training_ground/training_combat_encounter.gd`：空玩家綁定／舊敵車已移除的正常處理，保留 timer／無敵／目標切換語意。
- 整合必要相容修正 `src/world/training_ground/vision_range_preview.gd`：敵車提前清除的實跑揭露先轉型 freed observer 的錯誤；僅先檢查 raw Variant 有效性再轉 Node3D，不改輪廓、Vision 或 AI 決策。
- 修改 `src/world/training_ground/training_ground_playtest.tscn`：只加區域實例與引用，不改其他擺位。
- 新增 `tests/region_wreck_cleanup_smoke.gd`／uid；修改 `tests/enemy_combat_smoke.gd` 中原重生清除與「死亡車必留三秒」的被取代斷言，其餘 baseline 不弱化。
- 更新本文件與原 spec／plan 的 Task 5／R1 指向。Task 1–4 既有 dirty 修改保留；不改 Vision／AI 決策、Health／傷害、四車幾何、GLB、project.godot、CI 接線、PR／merge／Linear。

### 執行與驗證順序（需使用者核可後才開始）

1. 保存本次 allowlist 基線；以既有死亡／重生案例確認現狀，新增 Z2/Z3/Z5 有限行為紅測，不以缺新 API 冒充行為差異。
2. 實作區域本體與清除用途，跑 Z1–Z4；再接正常空綁與無舊車重生，跑 Z5／R1。若發現需擴其他系統，改碼前回 root 裁決。
3. 串行跑新 zone smoke、enemy／training／combat boundary、Task 3/4 回歸及完整既有 CI；新增 CI hook 仍留 Task 6，不提前集中交付。
4. 真編輯器截圖確認綠區尺寸／位置，真遊戲畫面確認不可見且死亡清除；按使用者已給的後續複審授權送必要畫面作第二意見。
5. Fresh-context 依固定 Z1–Z5／R1 驗收，通過後交 leadi F6；不自動開始 Task 6。

### 整合分類與收束（2026-09-10）

- A1／Z3、Z5：場景根引用原本用根屬性斜線寫法，真 Godot 載入讀回為 null；已改顯式覆写實例內的 WreckCleanupRule 節點，讀回與 playtest root 相同。
- A2／Z5：敵車清除後粉靶切換實跑揭露視野預覽對 freed observer 轉型；以上最小有效性 guard 修正後，同一真投射物案例 exit 0 且無錯。兩項皆原固定矩陣直接相容義務，未增加功能或新驗收種類。
- D／harness：新測試 cleanup coroutine 缺 await、以已釋放物件查 typed overlap、傳已釋放前車到 typed helper，均修正測試時序／參數，不弱化斷言。
- D／harness：原 baseline 瞬移至區外後只等一次 physics 訊號，實測位置 X=210 仍在原生 Area overlap 快取內；改為死亡前有限四次 physics/process 確認脫離。倒數中粉靶切換案例同樣明確使用區外殘骸，保留原切換／計時／來源註冊斷言；區內提前清除另由 Z5 驗證。
- 收束：達第二項 A finding 後只處理以上原 AC；不新增通用重入、恢復、幾何判定或跨系統框架。新增範圍僅 preview 的三行 guard，其餘 Task 1–4 dirty 修改保留。

只以已核可正常流程與上述有限矩陣的直接反例阻擋；未來其他區域用途、任意形狀、多人／當機恢復、全域規則編輯器、活車避讓都屬 scope expansion，不把 advisory 自動升格為驗收條件。

## 單輪 Claude review 與 root 裁決

Claude 已完成一次唯讀 review（exit 0、有效 result；證據 `/tmp/lea173-zone-cleanup.KdZ0B1/claude-review.jsonl`）。其四項 Blocking 標籤經現碼核對，沒有留下新的產品 blocker；另一本來已要求的視覺條件補明做法，不擴驗收。

1. **重生位置可能依賴已刪舊車：駁回風險假設、採納補明文件。** 現行 Encounter:140–142 直接傳入出生 marker 的 global_transform，與舊車無關；上面方案 6 已寫明沿用此來源，不新增死亡位置快照。
2. **Health 尚未滿血可能誤刪新車：駁回時序假設、補證據。** HealthComponent:20–21 的 `_ready()` 同步 `reset_to_maximum()`（:37–38）；未進樹實例不會是區域 overlap body，正常場景先完成 ready 才由 physics 規則處理。保留 Z3／Z5 驗證活車與新車不刪，不新增第二死亡旗標或延遲保護。
3. **mask=1／死亡仍保留碰撞缺證據：採納查證，已關閉。** 四車場景未覆寫層，tank_base.tscn:11–12 為 CharacterBody3D、碰撞屬同根 body，採預設 layer 1；Main:65–76 的死亡保留只停動作／速度／履帶，不改 layer 或 disabled。唯一清零層是待移除的舊清骸函式 Main:96–99；新規則不沿用此函式。
4. **兩個 tree_exiting 消費者可能互相解註冊：駁回。** PlayerRuntime 完全沒有 CombatRuntime 註冊呼叫；新空綁也只管自己的輸入／呈現／shot 訂閱。CombatRuntime:79–94 已對 null／未登記來源早退並只拆自己的 callback。沿既有職責處理，不增加通用重入／恢復機制。
5. **綠色 runtime 隱藏做法未明：採納文字明確化。** Z1 原本已要求不顯示，方案 1 現明寫 editor hint 控制提示 mesh；仍須真 editor／遊戲畫面驗證，不靠文字宣告通過。

最終四問覆核：上述查證未新增使用者或產品義務；可重用區域、即時清除、僅編輯器顯示與活車不處理的使用者裁決維持。ADR、共通 glossary 與逐題澄清清單均已落地；使用者已核可技術方案並再次強調兩流程獨立；開工前四問覆核維持上述產品定位，不新增框架。


## Task 5 本機交付證據（2026-09-10）

### 試玩追加：綠色出生點地板與轉正

- 人類驗收：leadi 於 2026-09-10 回覆「驗收通過」，涵蓋此追加與 Task 5 清骸／重生流程；後續進度見主計畫頂部「目前狀態」。

- leadi 追加要求訓練場重生點地板顯示綠色並對正；新增 24×24m 半透明綠色平面標示，位於既有 PlayerSpawnPoint，略高於地面 0.025m，無碰撞。
- PlayerSpawnPoint 保留原位置 (0, 0, 8) 與引擎讀回的 -0.35 rad Y 旋轉；地板與清骸區子節點以 +0.35 rad 抵銷，使地板與清骸盒對齊世界 XZ 格線，不改坦克重生朝向。
- 綠色地板是訓練場的可見標示；原 RegionVolume 立體盒形仍只在編輯器顯示，兩者不混用。未改三秒重生、兩秒保護或清骸規則。
- Windows Godot 真實執行 green-floor-aligned-runtime.log：全部 assertions_complete、exit 0；三階段截圖位於 visual-stage/captures/green-floor-aligned/。green-floor-alignment.log 另實測地板與清骸區 global basis 均為 identity；fresh-context 驗收通過。此追加未外傳新圖片，先前 Gemini 四圖判定只適用當時畫面。

### 原始 Task 5 驗證

- 新區域：`regression-region_wreck_cleanup_smoke.log`，Z1–Z4 通過。
- 玩家流程：完整既有 CI 內 enemy smoke 通過；縮小案例 `r8-pass.log` 另驗區內早清、空綁、同型滿血重生、兩秒保護、區外保留與外部移除後獨立重生。
- 敵方流程：`enemy-early-clear-fixed.log`，真殘骸清除後以 CombatRuntime 真投射物命中粉色靶，正確切換下一型敵車，無 SCRIPT ERROR。
- 既有回歸：`regression-partial_visibility_smoke.log`、`regression-partial_visibility_combat_smoke.log`、`regression-vision_preview_smoke.log` 通過；`full-ci.log` 最後為 Tank Skirmish quality gate passed，exit 0。
- 真 Windows Godot 4.7.1：`editor-visual-third.log` 的 editor_hint=true 與綠色盒形 PNG；`runtime-visual.log` Vulkan 實跑三階段截圖及全部 assert 通過，exit 0。原相機／地圖沒有保存測試性調整。
- 上述證據均位於 /tmp/lea173-zone-impl.5K4Wpx/。獨立 fresh-context 代理已讀回程式／測試、log 及四張實圖；不是由實作者單獨自驗。Gemini 四圖外傳首次被平台權限審查拒絕；使用者後續明確回覆「同意」後才重新執行，沒有繞過限制。四次 read_file 均 success，result=success、CLI exit 0；gemini-visual.jsonl 與 gemini-visual.err 留存證據，stderr 無讀圖失敗。Gemini 確認 editor 綠盒可見、三張 runtime 均隱藏、玩家初始／清除（僅留爆炸特效）／重生差異明確，無視覺 blocker。採納此範圍判定，不從靜圖推論計時或生命值，不新增修改項目。
- 人類驗收：重新開啟 `src/world/training_ground/training_ground_playtest.tscn` 後 F6。區域位於 `PlayerSpawnPoint/WreckCleanupZone/RegionVolume`；需要編輯實例子節點時，對 WreckCleanupZone 啟用 Editable Children，再調整 RegionVolume 的 Size。綠色只在編輯器顯示。
- 本節保存 Task 5 當時的驗證證據；Task 6 與提交／PR／merge／Linear 進度以 `partial-visibility-collision-plan.md` 頂部「目前狀態」為準。
