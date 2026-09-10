# Task 4 調整：水平視野輪廓

## 狀態與優先順序

使用者已核可方向與高度語意（2026-09-10：「可以，以視野為準」）。本文件取代原 partial-visibility-collision-spec 的紅色視界第 9–11 項、P1/P2，以及 plan 的 D／Task 4 實作方式；其他 Task、碰撞、AI、傷害規格不變。新版已通過自動化、獨立驗收及使用者 F6 試玩驗收（2026-09-10：「可以 驗證通過」）；證據見末節。

## Context／四問覆核

- 使用者仍為 leadi 在 Windows Godot 親測單人坦克遊戲，沒有新增角色。
- 類比仍為斜俯視遊戲的即時視野輪廓；不新增迷霧、探索記憶或導航。
- Identity 仍為產品優先的 Tank Skirmish，不建立通用視野引擎。
- 動機更新：紅色提供易讀、快速更新的視野示意，不再預測整台玩家坦克在假想位置能否被發現。實際索敵／射擊仍維持部位精度。

## ADR

### 背景

原預覽逐格搬移玩家姿態並檢查部位遮擋；4m 邊緣呈方格，2m 在 RTX 5090 測得一輪約 1.08–1.27 秒。使用者不接受這項畫面／反應取捨，要求簡化為直接視野。

### 決策

1. 紅色改成觀察者砲塔高度的水平視線，保留近距離全向圓與砲塔朝向遠扇聯集；不代表玩家必定被發現或可被射擊。
2. 以現有 TankVision.capture_visibility_state() 的 view_origin 作射線起點與輪廓中心；同一 Y 高度向各方向查詢，將結果投影到原地面顯示高度。range/fov/forward/collision mask 仍讀觀察者，AI 的範圍與索敵程式不變。
3. 碰到該高度的建築、其他坦克、殘骸或地形就截斷，低於視線的物體可越過。只排除觀察者 RID；目前玩家就是場上的另一台實體，也可擋視線，不再排除或虛擬搬移玩家。
4. 移除玩家 reference_target 依賴與逐部位假想取樣。玩家換車／轉炮管不直接改預覽，但若它在視線上，其真實碰撞外形仍會影響遮擋。
5. 使用排序後的角度射線端點形成單一星形三角扇地面 mesh，不用 2m/4m R8 網格、模糊插值或多層疊色。材質仍為淡紅 alpha 0.15、unshaded，不改美術／地圖。
6. 初始角度步距 0.5 度，整圈約 720 條射線；遠扇兩邊補入精確邊界（含邊界歸遠扇）與邊界外 0.01 度，避免近／遠半徑轉折被大三角斜切。邊界外這個極窄接縫屬有限近似，S1 扇外樣點至少距邊界 0.1 度。牆邊可在命中與未命中或距離相差超過 2m 的相鄰射線間做至多 3 層二分補樣；全輪最多 2048 條射線，先完成基礎方向再在上限內補樣，不新增障礙物幾何抽取系統。仍屬有限角度近似，不保證無限細縫／細杆。
7. 每 physics frame 以當前觀察姿態完成一次輪廓並交換 mesh／位置，不再跨多影格建整張格網；動態遮擋跟隨下一個完整 physics 更新（允許 1 physics frame 同步）。invalid observer／space、editor 無有效物理空間時隱藏；display_enabled=false 停止預覽查詢並隱藏，不影響 AI。
8. 記錄每輪 query 數與 CPU 更新 p95/max；正式訓練場先以每輪工作 p95 ≤4ms、單輪完成更新為驗收目標。超標回報數據與選項，不默默減低 AI 精度、延回一秒批次或擴增預算。

### 被否決的替代方案

- 保留整車假想＋加密格網：已實測邊緣與延遲不能同時滿足此次需求。
- 只模糊原 mask：不解決主要成本，且會將原透明格染紅。
- 直接以建物平面剪影、完全忽略高度：無法表達使用者已核可的低物越過／高殘骸阻擋。
- 簡化 AI 索敵：此次只改提示，不能撤銷 Task 3 已驗收的部位發現與射擊行為。

### 影響

紅色不再保證與實際玩家被發現結果一致；矮車可能藏在低殘骸後但位置仍在紅區。低物後方紅區代表此水平視線可越過，並不保證炮彈也可越過。既有 4m／2m 預览的 GPU／CI 證據保留為歷史，不套用到本版本。

## 澄清清單

- [x] 是否可將紅色從整車可發現預測改為直接視野？回答：可以；僅預覽簡化，AI 不變。
- [x] 是否採觀察者砲塔高度，低牆可越過？回答：詢問殘骸後同意「以視野為準」。
- [x] 殘骸遮擋如何判定？回答：接受碰到視線高度才擋、低於視線可越過，紅色與精確索敵可能不同。
- [x] 四問覆核：目標使用者／類比／Identity 不變；動機改為即時易讀的提示，已反映於上述 Context。

## 封閉實作與驗收

- Threat model：既有單人 Godot 4.7.1、可信場景物件、平坦訓練場；不新增網路、併發、crash recovery、通用地形可走性或完整三角形可見性承諾。
- Allowlist：vision_range_preview.gd／gdshader、training_combat_encounter.gd（僅移除預覽 reference 接線）、vision_preview_smoke.gd、training_ground_smoke.gd（僅相容新預覽斷言）、本文件及原 spec／plan 指向本決策的文字。既有 uid 保留。
- 不改：TankVision、CombatAI、四車幾何、controller、傷害、GLB、訓練場 tscn／擺位、project.godot、Task 5/6、CI 接線、PR／merge／Linear。
- 先行有限 red：舊 2m 預覽依賴玩家 reference，且低於視線的整車假想判斷不等於水平射線；至少一個明確高度 fixture 以真水平 ray oracle 證明差異，不能只用缺新 API 當紅測。
- S1：開放近圈、遠扇、扇外近圈與扇外遠處；讀輪廓端點對照獨立水平 ray oracle，驗 finite mesh、範圍、單層 alpha。
- S2：同一有限牆體分別低於／高於視線；高牆同時裁切近圈與遠扇、低牆可越過。用真車殘骸的有限高度位置驗相同行為。
- S3：observer 本體排除、其他實車（含玩家）及殘骸保留遮擋；移動 blocker／observer／轉砲塔後在下一完整 physics 更新採新輪廓；invalid 清除、display 不影響 AI。
- S4：RTX 5090 真 render 的開放／建物遮擋／低高障礙畫面與每輪 CPU p95/max/query；不以純 headless 或 uniform 替代。新圖若需外部 Gemini，再依明確授權處理。
- Regression：Task 3 V1/V2（38/7）、A1/A2、training、enemy 與既有 CI；只替換被新語意取代的預覽測試，不削弱其他斷言。
- Fresh-context 獨立驗收後交 leadi F6；有原 S1–S4／Regression 的有限反例才 Blocking，其餘建議轉 backlog，不擴張本單。

## 單輪跨模型 review 與 root 裁決

- Claude 認為單一 observer RID 可能漏排自體部位：不採納其多 RID 假設；本專案為一台 CharacterBody3D 持有多個 CollisionShape3D，Task 1/3 已驗證單一 owner/RID。實作沿用 state.exclude，不新建多 body 掃描機制。
- 採納邊界 epsilon 必須明確的意見，已鎖 0.01 度、含邊界及固定扇外樣點；此為有限近似的可驗收界線，不改使用者視野定義。
- 原範圍內數值封閉：near_radius/far_radius 均直接取 observer state；總 query 上限 2048、disabled 不查詢、同步容忍一個 physics frame，已寫入決策。沒有新增產品義務。
- 「近圈可能不查 LOS」、「V1/V2 可能依賴 preview reference」與多 RID 同屬不符合目前程式的假設，忽略，不擴大回歸或變更 AI。殘骸碰撞沿用現有 owner/body，S2 以實例驗證。
- 正式先行 probe：720 水平 rays／輪、10 輪 p95/max 1.084ms（不含新 mesh）；Tank3 view Y=2.264、Tank2 最高取樣 Y=2.073、低牆高 2.168，水平 ray clear 而真 Vision 0/60 可見，證明新舊預覽語意確實不同。

## 新水平視野版本的驗證結果（2026-09-10）

- 實作範圍為預覽 gd／shader、Encounter 移除三行玩家 reference 接線，以及兩支 preview 相容 smoke。既有 TankVision／CombatAI、地圖、車體幾何、project.godot 與 CI 接線未因本次調整而變更。
- 720 基礎方向、0.5° 角距與邊界補樣／三層二分不變；每次更新只解析一次排除 RID、mask、範圍與 FOV，減少重複配置。每 physics frame 仍產出完整的單一三角扇，不使用格網或跨影格批次。
- S1–S3：vision_preview_smoke、training_ground_smoke 均由 fresh-context 驗收者獨立實跑 exit 0；包含水平範圍、低／高牆、真車死亡殘骸、self 排除、其他實車遮擋、動態更新及 invalid／disabled。測試以相鄰 physics 訊號驗每步完整發布一次，移動碰撞體允許原規格的一步同步；不把 process frame 當 physics frame。
- 回歸：V1=38／V2=7；A2 blocked ticks=90、queries=90、shots=0，解除後真 alternate pipeline shots=1；enemy smoke 通過。完整既有 CI 由主代理在允許寫 artifacts 的環境執行，exit 0，末行為 `Tank Skirmish quality gate passed.`；獨立驗收者的首次 CI 因唯讀 worktree EROFS 未開始，不能當產品失敗或 PASS。
- S4 為 Windows Godot 4.7.1、Forward+／Vulkan、RTX 5090 真渲染；每案例 131 次完整更新：

| 案例 | 最後一輪 rays | CPU p95（ms） | CPU max（ms） | 像素不符 |
|---|---:|---:|---:|---:|
| 開放視野 | 748 | 3.529 | 3.676 | 0 |
| 朝向建物 | 742 | 3.546 | 3.707 | 0 |
| 低障礙 0.8m | 748 | 3.539 | 3.667 | 0 |
| 高障礙 3.5m | 748 | 3.577 | 3.886 | 0 |

- 上表視線 Y 約 1.710m：低物後方仍紅、高物後方裁切。像素檢查以 on/off 實際渲染比對輪廓內外，明列排除抗鋸齒邊界、被物件遮住與飽和白線的點；不把排除點當 PASS。初版 normal p95 4.034ms 的 log 保留為效能修正前證據，不混入上表。
- 使用者同意本次及後續第二模型複審。Gemini 確實讀取四張圖並確認低／高障礙差異符合、可供試玩；它聲稱的雙層疊色／方格階梯未獲程式證據支持。root 與 fresh-context 驗收核對排序角度、唯一中心的單 surface 三角扇及單 tint shader，駁回多層／格網判斷，不擴增地圖美術修改。
- 證據目錄：`/tmp/lea173-radial-preview.6y18ze/`；`v1.log`、`accept-vision-preview.log`、`accept-training-ground.log`、`accept-partial-visibility-combat.log`、`accept-enemy-combat.log`、`full-ci.log`、`gpu/{open,cover,low,high}.log` 與各 on/off PNG、`gemini-review.jsonl`／`gemini-review.err`、`fresh-acceptance.md`。
- 狀態：新版已通過自動化與獨立驗收；leadi 於 2026-09-10 回覆「可以 驗證通過」，Task 4 人類驗收通過。紅色只代表水平視野示意，不承諾整車被發現或可被炮彈擊中。後續 Task 與交件進度以 `partial-visibility-collision-plan.md` 頂部「目前狀態」為準。
