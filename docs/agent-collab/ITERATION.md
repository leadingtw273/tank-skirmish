# 2026-10-06 玩家遮蔽淡出與敵車透視輪廓續修

狀態：`approved`（原核可產品範圍內，依本次親測回饋續修）。人員產品驗收：`needs_changes`。2026-10-05 的 PR #126 已工程交付；本輪是其視覺調整，本次候選仍整合／驗證中，沒有新版 PASS、交付 commit 或 accepted。

自包含產品決策、既有 ADR、術語與有限測試入口見 [tank-occlusion.md](../features/tank-occlusion.md)。專案設定沿用 [PROJECT.md](PROJECT.md)，協作與真實合併條件沿用 [WORKFLOW.md](WORKFLOW.md)；PROJECT 原管理輪分支／基線快照保留為歷史，本輪以本檔為準。

| 本輪定義 | 內容 |
| --- | --- |
| 目標／動機 | 玩家中心透明且無顆粒、邊緣平滑、小範圍常駐跟隨；敵車紅線包含真實車體／砲塔／砲管／履帶部件界線，方便部位瞄準。 |
| 執行順序／工單 | 沿用 [LEA-194：玩家局部建築淡出](https://linear.app/leadingtw273/issue/LEA-194) 與 [LEA-195：敵車紅線輪廓與透視瞄準](https://linear.app/leadingtw273/issue/LEA-195)。2026-10-06 兩單已讀回為進行中，原依賴保留：先玩家工程驗證，再整合敵方；不把兩單互相擴 scope。 |
| 範圍 | 玩家前景建築局部透明窗、同一世界半徑設定、視野內被相機建築遮住的敵車稀疏紅色外框與部件界線、既有真目標世界點瞄準接點。 |
| Base／交付 | 既有 `main`，本次基線 [`f97581214e713627fce93a6a00ad8aae7206c5fc`](https://github.com/leadingtw273/tank-skirmish/commit/f97581214e713627fce93a6a00ad8aae7206c5fc)，來源樹 `2074e262610c426efadd605bd80b17769ca318a3`（已合併 [PR #126](https://github.com/leadingtw273/tank-skirmish/pull/126)）。新版在隔離工作樹準備；尚未正式套用 source 或宣稱新版已在 main。 |
| 核可人／日期 | leadi，原輪 2026-10-05；2026-10-06 親測回饋決定本次視覺 AC，見下方摘要。 |
| 責任／人驗 | 工單負責人與共享進度以 Linear 實際紀錄為準；leadi 為產品決策及人員產品驗收人，本次結果為 needs_changes。 |
| 術語 | 沿用既有三個產品術語；定義在產品文件，接手不需個人記憶。 |

## 本次續修與已交付歷史

目前工作與範圍查 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194) 與 [LEA-195](https://linear.app/leadingtw273/issue/LEA-195)；版本／PR／CI／review／merge 以 GitHub 實際紀錄為準。以下是有日期的證據摘要，不是中央進度表，也不代替新版同 Head gate。

- **2026-10-05 歷史工程交付**：[PR #126](https://github.com/leadingtw273/tank-skirmish/pull/126) 已正常合併至 `main` 的 `f97581214e713627fce93a6a00ad8aae7206c5fc`。同版本機完整品質 73／73 命令、136 個 unit／contract 測試及四車主圖／訓練場 84 項圖形工程檢查通過；同 Head source review PASS／0 blocker。PR CI `37293523655`／attempt 1 與同版 main CI `37299277721`／attempt 1 均實際 success，兩次一次性 runner、container 與素材 gate 已清理。這些結果僅涵蓋已交付版本，當時人驗 pending。
- **2026-10-06 人員親測**：leadi 回報 needs_changes，沿用兩單續修，不撤銷歷史工程證據，也不將它們當作新版 PASS。
- **本次計畫與候選**：精確新計畫文字外送已明確核准；2026-10-06 Claude（`claude-opus-5-5`）單次有效 result 為 approve／0 blocker，只讀核准計畫且 SHA／mtime 不變。六項 advisory 按原有限 AC 觀察，不新增 scope。候選仍整合／驗證中，作者自檢不代替 fresh-context 驗收、完整品質或 Windows 親測。核准不包含 code、材質、PNG 或私素材外送。
- 新版須對最新候選 Head 留下固定矩陣、完整品質及獨立 review 證據後，才處理符合真實平台條件的交付；正式 source 同步前仍須重查工作樹並保留使用者未提交內容。

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

同次裁決另確認滑鼠指向透視輪廓可以瞄準敵車。

2026-10-06 親測回饋摘要：玩家中心越靠近車體越透明、沒有顆粒，僅邊緣可有霧狀平滑過渡；範圍縮小且常駐，使進入掩體自然。敵車紅線除外框亦需真實車體細節，以便瞄準砲塔或履帶。本次共同世界半徑預設為 5m；8m 是上一版預設，原裁決只要求共同設定，未鎖成不可調數值。常駐指窗持續跟隨受控車，前景建築投影交窗即處理，不等車體遮擋 ray 首次命中；沒有建築不畫額外 UI 圈。

原「僅外框／interior_red==0」視覺判準由本次明示部件細節線取代；仍禁止實心填紅及三角 wireframe。授權沒有擴為穿牆傷害、對外發布或私素材外送。

## 固定驗收矩陣

| AC | 可客觀驗收的結果 |
| --- | --- |
| P1 | 真主圖四車：中心透明且無顆粒，中心比中段更透明、外緣連續；圈外及同材質他棟保持原外觀，陰影 ROI 與 baseline 不變，碰撞保留。 |
| P2 | 固定移動入／離建築：在車體第一個遮擋 ray 之前，窗與前景建築交界已沿零→低→高透明度連續變化，沒有突然整圈啟動；平移／轉動／縮放跟隨穩定，玩家／敵方共同半徑 5m。 |
| P3 | 四車換車、死亡／重生、null、退出：清理舊 instance overrides／next_pass，原材質還原，沒有殘留。 |
| E1 | 真訓練場四車：窗口內外框與真實 gun／turret（存在時）／hull／左右履帶部件界線可辨識；不填紅、不畫三角網格，圈外紅線 0；alpha silhouette 與原 actor 投影 0 差異。 |
| E2 | 指向 turret／gun 與履帶真像素能解析真目標世界點並經既有 Aim 瞄準；空白像素不命中，砲口實體首撞仍牆，Projectile 遮彈不回歸。 |
| E3 | 原車型 near／far／角度或逐部位 LOS 不符、全 LOS 堵塞、死亡／換車／退出：無紅線／舊拾取；既有 45 joints 履帶 pose 同步保留。 |

必跑直接 smoke：`tank_occlusion`、`enemy_occlusion`、`aim_cursor`、`partial_visibility`、`partial_visibility_combat`、`enemy_combat`；完整入口為 `scripts/ci.sh`。圖形 harness 使用新的輸出目錄，不覆寫歷史圖／報告。Headless shader 建立成功不能代替視覺驗收；新 fresh-context 代理依固定矩陣獨立實跑並讀回，作者不自稱驗收。新版工程交付與 leadi 親測分開，人驗維持 needs_changes，直到取得真實確認。

## 保持條件與明確排除

Windows 單人 PvE、正交斜俯視、四款 catalog 坦克與既有動機不變。敵方資格仍同時要求 camera 建築遮擋與所選車型 `TankVision.can_see`；near 全向半徑、far 砲塔水平視角及逐部位實體 LOS 保持。相機建築遮蔽與玩家砲塔 LOS 分開，玩家 LOS 全堵不啟用敵車透視。拾取依原 alpha silhouette 與線寬鄰域，解析真實目標世界點；RGB 部件線不成為新命中面。

建築實體碰撞、砲口／砲彈首撞、AI、尋路與傷害管線保持。正式主圖沒有敵方 Encounter，本輪不植入敵方戰鬥布局，敵方固定案例限現役訓練場與有限測試場景。Tank4 固定上車體依真實 `Tank_Turret` 名稱分類；Tank1 無獨立 turret mesh，不能虛構。

不修改私有來源素材／貼圖、地圖布局、光照、天氣、鏡頭構圖或取消的 demo；不新增迷霧、發現記憶、全域敵人隱藏、穿牆傷害、addon、來源格式遷移、跨渲染器義務或崩潰 recovery，不啟動舊 Team registration／Job。Review advisory 分本單 blocker／後續 backlog／忽略，不自動改寫 AC。

## 工程與安全邊界

已核可範圍內普通開發、修正、驗證、獨立 review 與滿足真實 gate 後正常 merge 可自主續行。保留 `quality`、required `agent-team/review`、protected settings 及全部平台條件；最新 Head 改動後重審，不以歷史 PASS、文件或評論代替必要 status，不用 bypass。

素材僅供既有本機開發輸入，保持 ignored，不提交或外送私素材、含素材截圖、憑證或個人私有路徑。上一版 PR #126 與同來源樹 main CI 的兩次私素材讀取 grant 已耗用，本輪不能沿用。新網路私素材 CI 依 [既有 runbook](../local-private-ci.md)，在封存 Head 後另列 exact PR／Head／run／attempt 授權包；缺權限只暫停該段，不跳過必要 CI。

## 上一管理輪的已完成歷史

2026-10-05 管理切換已透過 PR #125 普通合併至 `main`，commit `b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7`。目標是「將當前開發管理方式全面導向 Agent Collab 而不是 agent team」，使用者選擇「互動代理主導，退役舊自動派工」，保留 Linear／GitHub 工單、PR 與 CI。該輪待辦已由實際交付取代，不重開；管理合併不代表遊戲 QA 或人員 accepted。
