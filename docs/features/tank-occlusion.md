# 玩家建築遮蔽淡出與敵車視野內透視輪廓

日期：2026-10-05；產品決策／人員產品驗收人：leadi。授權見 [ITERATION.md](../agent-collab/ITERATION.md)，接手見 [HANDOFF.md](../agent-collab/HANDOFF.md)。Base 為 `main` 的 `b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7`（[PR #125](https://github.com/leadingtw273/tank-skirmish/pull/125)）。

狀態：產品決策已採用。工程狀態：玩家 phase1 實作中；Claude plan review 已執行（提醒已裁決採納）；正式 Forward+ probe／新功能驗收／PR／CI 待完成。 人員產品驗收：`pending`，未宣稱 accepted。本文保存裁決與有限驗收依據，不是功能交付或測試通過證據。

## 使用者裁決與產品前提

leadi 於 2026-10-05 指定「先修玩家遮蔽透視在修敵人遮蔽透視」，玩家選擇「遮擋建築局部淡出」。敵車資格為「在玩家視野範圍內，這視野取決於選擇坦克的設定，如同AI的視野偵測機制一樣」；外觀為「敵人坦克用紅色線條透視於建築上」，範圍補充為「那個透視範圍或是圈圈半徑就跟玩家的一樣」。同次裁決另確認滑鼠指向透視輪廓可瞄準敵車。

既有前提維持 Windows 單人 PvE、正交斜俯視與四款 catalog 坦克。元前提四問覆核：目標使用者是既有單人 PvE 玩家；同類遊戲只借鏡構圖；Identity 維持 Tank Skirmish 遊戲；動機是受控車／視野內敵車辨識與操作可讀性。沒有新目標使用者、工具平台或玩法方向裁決。

## ADR：顯示資格與瞄準規則

決策先玩家局部建築淡出，再敵車紅色外輪廓。玩家由 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194) 承接，P1–P3 本機驗證與 fresh-context 驗收後接依賴它的 [LEA-195](https://linear.app/leadingtw273/issue/LEA-195)，完成 E1–E3。工程獨立驗收與 leadi 親測分開，不推定人員 accepted。

玩家窗口只淡出相機與受控車體之間實際造成遮擋的建築，保留窗口外外觀。單一可調世界半徑初值 8 公尺，投影到螢幕並隨縮放維持世界尺度；玩家／敵方窗口各自以車體中心投影為圓心，共用半徑設定。局部軟邊及短進出淡化降低突變。

敵車只有存活、畫面內、被相機建築遮住且玩家 `TankVision.can_see` 為真才啟用輪廓。視野重用所選車型 near 全向半徑、far 砲塔水平視角及逐部位實體 LOS；相機建築遮蔽和玩家砲塔 LOS 分開判斷。全部部位玩家 LOS 被建築阻擋不啟用透視；視野外敵車沿用原顯示，不新增全域隱藏或發現記憶。

敵方在建築前畫約 2 像素紅色外緣線條，共同窗口外不透視，建築不因敵方淡出。資格以有限部位相機射線判斷，啟用後顯示窗口內完整外輪廓，不另要求逐像素場景深度裁切。命中區包含紅線圍住的實體車體投影 silhouette shape 及線寬鄰域，不能只用 AABB；窗口與視野資格仍相同。

滑鼠命中啟用輪廓時優先解析該敵車實體世界點，驅動既有砲塔／砲管瞄準；未啟用、窗口外或視野不符走正常首撞 picking。輪廓拾取只對目標敵車：非目標 RID 略過，不能回傳牆或其他車的點。砲口命中線、Projectile 首撞與建築遮彈保持，沒有穿牆傷害。

被否決方案：整棟永久透明不能保留建築外觀；所有畫面敵人揭秘不符合車型視野；敵方局部建築淡出被紅線輪廓裁決取代；只畫輪廓不接瞄準無法滿足操作需求；穿牆傷害不在本輪範圍。

## 有限工程接點與回滾

遮蔽控制器接既有 `PlayerRuntime.controlled_tank_changed` 與 `CameraController.camera`；用 `stable_world_center` 和有限均勻取樣的 `part_world_surface_points` 作相機實體射線。建築識別限 Buildings 容器或既有來源 metadata，不動 collision layer。受控車 null、離開樹、換車、死亡／重生時還原舊呈現並重綁。

玩家淡出用受影響 mesh 各自的 surface override ShaderMaterial 複製原 PBR 屬性與 `cull_disabled`，不改原 shared resource；opaque shader 在窗口內 dither discard，影子 pass 排除淡出，解除遮蔽還原原 override。Claude review 的 culling 提醒與 4.7 實測前提已裁決採納；正式 Forward+ probe 仍待完成。若直接技術前提實測失效，回報證據與有限選項，不默默改寫產品裁決。

現役訓練 Encounter 將實際敵車加入 `enemy_tank` 群組。每個啟用敵車以獨立 SubViewport／World3D 同步主相機與 mesh transform，產生白色 silhouette mask，Canvas shader 用外緣膨脹減內部 mask 畫線與窗口裁切；不使用整片填紅、三角 wireframe 或 experimental stencil。

拾取檢查 silhouette 車體原像素與約 2 像素線寬鄰域，回傳目標敵車實體交點；線寬邊緣可用鄰域 ray。若對應部位無實體 hit，取該車表面點中投影最接近命中像素者，仍是敵車世界點。回滾移除顯示節點／aim resolver 接線即恢復基線，沒有資料 migration。

## 固定驗收矩陣

| AC | 可客觀驗收的結果 |
| --- | --- |
| P1 | 主圖實際建築遮住玩家時，窗口內淡出可讀車體／朝向，範圍外與相同素材其他棟不變。 |
| P2 | 離開遮擋還原材質，沒有永久殘留；陰影與實體碰撞保留。 |
| P3 | 四車、換車、死亡殘骸、重生、場景退出都正確綁定；相機縮放下半徑採同一世界值。 |
| E1 | 訓練場敵車被 camera 建築遮住但玩家 `TankVision.can_see` 為真，窗口內只有紅色外輪廓、沒有實心填色，窗口外沒有透視；範圍與玩家共同設定。 |
| E2 | 車型 near／far／角度與逐部位 LOS 的既有判定保留；視野不符、玩家 LOS 全堵、敵車死亡／換車後不留舊輪廓。 |
| E3 | 滑鼠指向啟用輪廓回傳敵車世界點並驅動既有砲塔／砲管瞄準，離開輪廓回到正常首撞；砲彈仍撞建築。 |

玩家 P1–P3 驗證後獨立驗收，再接敵方 E1–E3；最終同一最新 Head 完整品質與獨立 source review。驗收只依 AC、成品與實跑證據，不沿用作者敘事；無 fresh context 能力時揭露限制，不假造獨立 PASS。

## 有限測試入口

本機具備正版私素材與現役 pinned Godot 後，依 [PROJECT.md](../agent-collab/PROJECT.md) 設定 `GODOT_BIN`，完整入口為 `bash scripts/ci.sh`。下列既有回歸入口目前僅確認檔案存在，本文未執行或宣稱通過。

| 固定回歸 | 既有檔案 |
| --- | --- |
| 玩家建立與受控車 | [player_spawn_group_smoke.gd](../../tests/player_spawn_group_smoke.gd) |
| 玩家 rigid 整合 | [player_rigid_integration_smoke.gd](../../tests/player_rigid_integration_smoke.gd) |
| 四車執行期 | [player_rigid_variants_runtime_smoke.gd](../../tests/player_rigid_variants_runtime_smoke.gd) |
| 現役訓練場 | [training_ground_smoke.gd](../../tests/training_ground_smoke.gd) |
| 滑鼠瞄準 | [aim_cursor_smoke.gd](../../tests/aim_cursor_smoke.gd) |
| 部位可見性 | [partial_visibility_smoke.gd](../../tests/partial_visibility_smoke.gd) |
| 部位可見性戰鬥 | [partial_visibility_combat_smoke.gd](../../tests/partial_visibility_combat_smoke.gd) |
| 敵方戰鬥 | [enemy_combat_smoke.gd](../../tests/enemy_combat_smoke.gd) |

單一 smoke 範例：`"$GODOT_BIN" --headless --path . --script res://tests/player_spawn_group_smoke.gd`；其餘按上表替換檔名。新功能新增有限 occlusion smoke 與實際渲染截圖，其交付／結果待實跑。Headless shader 建立成功不作視覺驗證；畫面在本機檢查，不外送。正式主圖沒有敵方 Encounter，本輪不植入敵方戰鬥布局，敵方固定案例限現役訓練場與有限測試場景。

## 術語

三個術語已記入共通術語，產品未實作完成。以下定義可直接供接手，不依賴個人記憶或私有路徑。

| 術語 | 定義 | 專案／首次確認 |
| --- | --- | --- |
| 玩家建築遮蔽淡出 | 建築從相機遮住受控玩家車體時，只在玩家附近圓形窗口淡出遮擋建築；窗口外外觀、實體碰撞與射擊阻擋保留。 | tank-skirmish／2026-10-05 |
| 敵車視野內透視輪廓 | 依受控車型的 TankVision 距離、砲塔水平視角及實體 LOS，對符合資格且被相機建築遮住的敵車顯示建築前的紅色線條輪廓；窗口半徑共用玩家設定。 | tank-skirmish／2026-10-05 |
| 透視輪廓瞄準 | 滑鼠指向啟用敵車透視輪廓時解析該敵車的世界瞄準點並驅動既有砲塔／砲管；不授予穿牆傷害，砲彈仍受實體建築阻擋。 | tank-skirmish／2026-10-05 |

## 保持條件、排除與安全

只新增執行期顯示與瞄準接點；碰撞、砲彈、AI、尋路、TankVision 實體 LOS、AI 發現／開火守門與傷害管線保留。不修改私有來源素材／貼圖、地圖布局、光照、天氣、鏡頭構圖或取消的 demo；不新增迷霧、發現記憶、全域敵人隱藏、穿牆傷害、addon、背景 registration 或舊 Team Job。普通本機單人遊戲是可信邊界，不額外承諾惡意插件、多人競態、崩潰恢復、來源格式遷移或跨渲染器相容性。

已核可範圍內普通開發、修正、驗證、獨立 review 與真實 gate 後正常 merge 可自主續行；對外發布、產品方向、平台受控設定與私素材外送邊界不擴大。`quality`、required `agent-team/review` 與全部平台條件保持，reviewed Head／必要 CI 須對應最新 Head，不用舊 PASS 或文件代替。Review advisory 依 [WORKFLOW.md](../agent-collab/WORKFLOW.md) 分為本單 blocker／後續 backlog／忽略，不自動擴 AC。

私素材保持 ignored，新增 source 可提交；不外送私素材、含私素材的截圖、憑證或個人私有路徑。新網路私素材 CI grant 依 [local-private-ci.md](../local-private-ci.md) 於封存 Head 後列具體 PR／Head／run／attempt 授權包；不泛延長舊 grant，缺權限只暫停該段，不跳過完整品質或平台 gate。人驗維持 `pending`，待 leadi 親測才記真實結果。
