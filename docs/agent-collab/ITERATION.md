# 2026-10-05 玩家遮蔽淡出與敵車透視輪廓

狀態：`approved`（本輪產品範圍已核可）。工程狀態：玩家 phase1 實作中；Claude plan review 已執行（提醒已裁決採納）；正式 Forward+ probe／新功能驗收／PR／CI 待完成。 人員產品驗收：`pending`，未宣稱 accepted。

自包含產品決策、ADR、術語與有限測試入口見 [tank-occlusion.md](../features/tank-occlusion.md)。專案設定沿用 [PROJECT.md](PROJECT.md)，協作與真實合併條件沿用 [WORKFLOW.md](WORKFLOW.md)；PROJECT 原管理輪分支／基線快照保留為歷史，本輪以本檔為準。

| 本輪定義 | 內容 |
| --- | --- |
| 目標／動機 | 建築遮住車體時，讓玩家辨識受控車體及符合玩家視野的敵車，並可指向敵車輪廓瞄準。 |
| 執行順序／工單 | 先 [LEA-194：玩家局部建築淡出](https://linear.app/leadingtw273/issue/LEA-194)，P1–P3 本機驗證與 fresh-context 驗收後，再 [LEA-195：敵車紅線輪廓與透視瞄準](https://linear.app/leadingtw273/issue/LEA-195)。LEA-195 依賴 LEA-194；不把兩單互相擴 scope。 |
| 範圍 | 執行期玩家建築局部淡出、同一世界半徑設定、視野內被相機建築遮住的敵車紅色外輪廓，以及輪廓指向的敵車世界瞄準點。 |
| Base／交付 | 既有 `main`，基線 `b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7`（管理輪 PR #125 合併結果）。隔離開發分支實作，最新 Head 獨立 review、同 Head 必要 CI／status 與平台 read-back 後普通 merge 至 `main`；尚無本輪交付 commit。 |
| 核可人／日期 | leadi，2026-10-05；下方保存自包含實際裁決摘錄。 |
| 責任／人驗 | 工單負責人與最新進度以 Linear 為準；建立後 read-back 兩單均為待執行、未指定責任人。leadi 為產品決策與人員產品驗收人，親測結果尚待取得。 |
| 術語 | 三個產品術語已記入共通術語，產品未實作完成；定義在產品文件，接手不需個人記憶。 |

## 本輪自包含裁決引用

2026-10-05，leadi 決定順序與玩家呈現：

> 先修玩家遮蔽透視在修敵人遮蔽透視
>
> 遮擋建築局部淡出

敵車資格、外觀與共同範圍的原句：

> 在玩家視野範圍內，這視野取決於選擇坦克的設定，如同AI的視野偵測機制一樣
>
> 敵人坦克用紅色線條透視於建築上
>
> 那個透視範圍或是圈圈半徑就跟玩家的一樣

同次裁決另確認滑鼠指向透視輪廓可以瞄準敵車。上述摘錄授權本輪顯示與瞄準接點，不授權穿牆傷害、對外發布或私素材外送。

## 固定驗收矩陣

| AC | 可客觀驗收的結果 |
| --- | --- |
| P1 | 主圖實際建築遮住玩家時，窗口內淡出可讀車體／朝向，範圍外與相同素材其他棟不變。 |
| P2 | 離開遮擋還原材質，沒有永久殘留；陰影與實體碰撞保留。 |
| P3 | 四車、換車、死亡殘骸、重生、場景退出都正確綁定；相機縮放下半徑採同一世界值。 |
| E1 | 訓練場敵車被 camera 建築遮住但玩家 `TankVision.can_see` 為真，窗口內只有紅色外輪廓、沒有實心填色，窗口外沒有透視；範圍與玩家共同設定。 |
| E2 | 車型 near／far／角度與逐部位 LOS 的既有判定保留；視野不符、玩家 LOS 全堵、敵車死亡／換車後不留舊輪廓。 |
| E3 | 滑鼠指向啟用輪廓回傳敵車世界點並驅動既有砲塔／砲管瞄準，離開輪廓回到正常首撞；砲彈仍撞建築。 |

本機固定案例、有限回歸與完整 `scripts/ci.sh` 實跑、實際渲染畫面及最新 Head 獨立 review 才能作工程證據；headless shader 建立成功不能代替視覺驗收。工程交付與 leadi 親測分開記錄，人驗維持 `pending`，直到取得真實結果。

## 保持條件與明確排除

視野沿用所選車型的 `TankVision.can_see`：near 全向半徑、far 砲塔水平視角及逐部位實體 LOS。相機建築遮蔽和玩家砲塔 LOS 分開判斷；玩家 LOS 全被堵住不啟用敵車透視。視野外敵車沿用原顯示。建築實體碰撞、砲彈首撞、AI、尋路與傷害管線保留。正式 `main` 主圖沒有敵方 Encounter，本輪不植入敵方戰鬥布局；敵方用現役訓練場與有限測試場景驗證。

不修改私有來源素材／貼圖、地圖布局、光照、天氣、鏡頭構圖或取消的 demo；不新增全圖迷霧、發現記憶、全域敵人隱藏、穿牆傷害、addon、背景 registration／舊 Team Job。可信邊界為本機正版素材、現役 pinned Godot 與普通單人遊戲狀態；不新增多人競態、惡意插件、崩潰恢復、來源格式遷移或跨渲染器相容性義務。Review advisory 分為本單 blocker／後續 backlog／忽略，不自動擴成本輪 AC。

## 工程與安全邊界

已核可輪次內普通開發、修正、驗證、獨立 review 與滿足真實 gate 後正常 merge 可自主續行，不逐 Task 重問。保留 `quality`、required `agent-team/review`、protected settings 及全部平台條件；最新 Head 改動後重審，不能以舊 PASS、文件或評論代替必要 status，不用 bypass。

本輪不外送私素材、含私素材的截圖、憑證或個人私有路徑。私素材保持 ignored；新網路私素材 CI grant 依 [既有 runbook](../local-private-ci.md) 在封存 Head 後列具體 PR／Head／run／attempt 授權包，不沿用或泛延長舊 grant；權限缺口只暫停依賴部分，不能跳過必要 CI。對外發布與產品方向變更仍需相應授權。

## 上一管理輪的已完成歷史

2026-10-05 管理切換已透過 [PR #125](https://github.com/leadingtw273/tank-skirmish/pull/125) 普通合併至 `main`，合併 commit 為 [`b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7`](https://github.com/leadingtw273/tank-skirmish/commit/b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7)。上一輪目標是「將當前開發管理方式全面導向 Agent Collab 而不是 agent team」，使用者選擇「互動代理主導，退役舊自動派工」，並保留 Linear／GitHub 工單、PR 與 CI。該輪候選快照的 PR／review／CI／merge 待辦已由實際交付取代，不重開為本輪工作；管理文件合併本身不代表遊戲 QA 或人員 accepted。
