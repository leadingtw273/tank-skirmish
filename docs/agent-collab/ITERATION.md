# 2026-10-07 LEA-134 發射手感續調

狀態：已核可開發；作者有限 core 與既有直接 checks 已 actual exit 0／ERROR 0，diff-check 通過。候選待同 HEAD 非作者 fresh-context 圖形驗收、來源 review、完整 quality 與人的手感驗收（pending）。自包含 ADR、參數、固定 F1–F5 與試玩入口見 [tank-firing-feel.md](../features/tank-firing-feel.md)。

leadi 2026-10-07 授權收尾後即刻射擊手感、正常合併／複審，選只加強視覺並保留移動／瞄準，以及鏡頭 0.5m→0.2m／原 0.2s。最新明示「提前核可第二模型相關複審操作，直接做到讓我可以實測手感」。範圍內自主續行，優先交付本機 Windows 候選；原平台／私素材／外送邊界保持。

沿 [LEA-134](https://linear.app/leadingtw273/issue/LEA-134) 新輪（In Progress），關聯已完成的 [LEA-148](https://linear.app/leadingtw273/issue/LEA-148)，不復活取消的151。保留134舊正文／歷史，新輪明示砲管動畫與鏡頭降低。

基線為已合併 [PR #128](https://github.com/leadingtw273/tank-skirmish/pull/128) 的 `main 679decd21d6d3a2b38e237330cd995ebe320a8cb`／tree `c912a8afe76ade1d0551335614b82bdf6b7384ec`；原真 CI、cleanup、來源 fresh、本機 FF、194／195 Done 與原透視人驗 accepted 已閉包。新分支 `feat/lea134-firing-feel-adjustment`，只寫新隔離產品工作樹。

三可見根共同反作用、GunVisual 另退縮，原機械 pivots／MuzzlePoint／impulse 不動。參考 Short 26–28 秒因429／bot gate未取得影格，不稱看過或精確復刻；Gemini影片第二意見缺席。人的手感驗收保持pending，不將作者證據當fresh／完整quality／GitHubpass。

235 原 UID、586 ignored 本機素材與正式來源 metadata 保持。新 Head 私 CI 需 exact tuple，PR #128 grant 不重用，網路私 CI 不作本機 preview 前置。最新 HEAD、Windows候選及真實平台 gate 交付時讀回。

以下原透視記錄為歷史；舊「尚未交付／main dc885899」已由上方PR #128閉包取代。

---

# 2026-10-06 玩家遮蔽淡出與敵車透視輪廓續修

狀態：原透視範圍已本機交付，人員產品驗收 `accepted`（leadi 2026-10-07 明確確認）；LEA-194／LEA-195 均為 Done。Windows 人驗產品版為 `0d7b523922d8cc9654b4f4447006792e5e901b68`，同版有限獨立實跑與來源讀回見下方最新引用。GitHub main 仍為 `dc8858991316fa3207e9b6d5765e1e8cc3df89e1`、open PR 0；本輪來源尚未 upload／merge，GitHub 交付不視為完成。以下有日期的舊 needs_changes、PR #126／#127 與失敗證據均保留為歷史。

自包含產品決策、既有 ADR、術語與有限測試入口見 [tank-occlusion.md](../features/tank-occlusion.md)。專案設定沿用 [PROJECT.md](PROJECT.md)，協作與真實合併條件沿用 [WORKFLOW.md](WORKFLOW.md)；PROJECT 原管理輪分支／基線快照保留為歷史，本輪以本檔為準。

| 本輪定義 | 內容 |
| --- | --- |
| 目標／動機 | 玩家中心透明且無顆粒、邊緣平滑、小範圍常駐跟隨；敵車紅線包含真實車體／砲塔／砲管／履帶部件界線，方便部位瞄準。 |
| 執行順序／工單 | 沿用 [LEA-194：玩家局部建築淡出](https://linear.app/leadingtw273/issue/LEA-194) 與 [LEA-195：敵車紅線輪廓與透視瞄準](https://linear.app/leadingtw273/issue/LEA-195)。2026-10-07 最新人驗 accepted，兩單工程狀態均 Done；195 依賴 194 的原關係、owner 與原 scope 保留。2026-10-06 的 194 重開進行中／195 已完成是歷史讀回。 |
| 範圍 | 玩家前景建築局部透明窗、同一世界半徑設定、視野內被相機建築遮住的敵車稀疏紅色外框與部件界線、既有真目標世界點瞄準接點。 |
| Base／交付 | 既有 `main`，本次基線 [`dc8858991316fa3207e9b6d5765e1e8cc3df89e1`](https://github.com/leadingtw273/tank-skirmish/commit/dc8858991316fa3207e9b6d5765e1e8cc3df89e1)，來源樹 `f0b14b98396f87bfbe71513252dbbdda2c830336`（已合併 [PR #127](https://github.com/leadingtw273/tank-skirmish/pull/127)）。本機產品版 `0d7b523922d8cc9654b4f4447006792e5e901b68` 已交付 Windows 並人驗 accepted；GitHub main 尚無本輪修正，來源 upload／PR／CI／merge 待另依真實授權與 gate 處理。原視覺調整基線 f975812／PR #126 保留為歷史。 |
| 核可人／日期 | leadi，原輪 2026-10-05；2026-10-06 親測回饋決定本次視覺 AC，見下方摘要。 |
| 責任／人驗 | 工單負責人與共享進度以 Linear 實際紀錄為準；leadi 為產品決策及人員產品驗收人，2026-10-07 對本機產品版 0d7 的原透視範圍裁定 accepted；舊 needs_changes 保留為歷史。 |
| 術語 | 沿用既有三個產品術語；定義在產品文件，接手不需個人記憶。 |

## 本次續修與已交付歷史

目前工作與範圍查 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194) 與 [LEA-195](https://linear.app/leadingtw273/issue/LEA-195)；版本／PR／CI／review／merge 以 GitHub 實際紀錄為準。以下是有日期的證據摘要，不是中央進度表，也不代替新版同 Head gate。

- **2026-10-05 歷史工程交付**：[PR #126](https://github.com/leadingtw273/tank-skirmish/pull/126) 已正常合併至 `main` 的 `f97581214e713627fce93a6a00ad8aae7206c5fc`。同版本機完整品質 73／73 命令、136 個 unit／contract 測試及四車主圖／訓練場 84 項圖形工程檢查通過；同 Head source review PASS／0 blocker。PR CI `37293523655`／attempt 1 與同版 main CI `37299277721`／attempt 1 均實際 success，兩次一次性 runner、container 與素材 gate 已清理。這些結果僅涵蓋已交付版本，當時人驗 pending。
- **2026-10-06 人員親測**：leadi 回報 needs_changes，沿用兩單續修，不撤銷歷史工程證據，也不將它們當作新版 PASS。
- **本次計畫與候選**：精確新計畫文字外送已明確核准；2026-10-06 Claude（`claude-opus-5-5`）單次有效 result 為 approve／0 blocker，只讀核准計畫且 SHA／mtime 不變。六項 advisory 按原有限 AC 觀察，不新增 scope。候選仍整合／驗證中，作者自檢不代替 fresh-context 驗收、完整品質或 Windows 親測。核准不包含 code、材質、PNG 或私素材外送。
- **2026-10-06 PR #127 工程交付後續修**：正式 main 已為 `dc8858991316fa3207e9b6d5765e1e8cc3df89e1`；交付與 CI／review 證據查 GitHub 與 Linear 原紀錄。leadi 新回報主場景玩家雙層透明邊緣與角度閃爍，沿原 LEA-194／P1–P3 續修，未撤銷歷史工程結果，也未代填人驗 accepted。
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

本次主場景親測完整原文（保留原字）：

> 1. 玩家坦克的視角透視邊緣過度效果很奇怪，甚至在不同角度下其還有閃爍狀況發生，請你觀察檢修一下，我這邊形容一下很像是有兩層透視，一層最外圈直接把玩家視角街出的第一個障礙變透明，像是建築屋頂然後第二圈是比較近的的內圈透明漸層，讓牆面有淡出的效果，兩者疊加在一起變得很奇怪，半徑不一致的樣子

本次「請你觀察檢修一下」授權原 LEA-194／P1–P3 範圍內缺陷修正，沿用原核可目標與產品定位，不另填新的 approved 時間。本次玩家視覺觀察與驗收優先使用主場景 `res://src/main.tscn`；leadi 確認問題發生於主場景，訓練場不是本次新增的玩家視覺 AC。原 P1–P3／E1–E3 與既有回歸入口保留，敵方範圍不擴張。

本次玩家邊緣續修待驗：既有 opaque／soft 雙 pass 使用同一半徑，但透明 pass 的前後多個表面可能疊加混色；只關閉背面或 foreground gate 的對照不足以排除此問題。修正正針對當下淡出的建築建立同相機的原始最近表面深度資料，讓 soft pass 僅混合最近表面。保留共同 5m、1 個 render pixel 的 opaque 外緣、圈外原 PBR／深度與完整陰影，以及後方建築／Tank4 包絡判斷；敵方、碰撞與實體遮彈不改。此處記錄修正方向，不代表實作、圖形驗收或 source review 已通過。

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

必跑直接 smoke：`tank_occlusion`、`enemy_occlusion`、`aim_cursor`、`partial_visibility`、`partial_visibility_combat`、`enemy_combat`；完整入口為 `scripts/ci.sh`。圖形 harness 使用新的輸出目錄，不覆寫歷史圖／報告。Headless shader 建立成功不能代替視覺驗收；新 fresh-context 代理依固定矩陣獨立實跑並讀回，作者不自稱驗收。工程交付與 leadi 親測分開；最新本機產品版 0d7 的原透視範圍人驗已 accepted，依下方 2026-10-07 記錄，不能據此宣稱未執行的新 GitHub／完整 CI gate 通過。

## 保持條件與明確排除

Windows 單人 PvE、正交斜俯視、四款 catalog 坦克與既有動機不變。敵方資格仍同時要求 camera 建築遮擋與所選車型 `TankVision.can_see`；near 全向半徑、far 砲塔水平視角及逐部位實體 LOS 保持。相機建築遮蔽與玩家砲塔 LOS 分開，玩家 LOS 全堵不啟用敵車透視。拾取依原 alpha silhouette 與線寬鄰域，解析真實目標世界點；RGB 部件線不成為新命中面。

建築實體碰撞、砲口／砲彈首撞、AI、尋路與傷害管線保持。正式主圖沒有敵方 Encounter，本輪不植入敵方戰鬥布局，敵方固定案例限現役訓練場與有限測試場景。Tank4 固定上車體依真實 `Tank_Turret` 名稱分類；Tank1 無獨立 turret mesh，不能虛構。

不修改私有來源素材／貼圖、地圖布局、光照、天氣、鏡頭構圖或取消的 demo；不新增迷霧、發現記憶、全域敵人隱藏、穿牆傷害、addon、來源格式遷移、跨渲染器義務或崩潰 recovery，不啟動舊 Team registration／Job。Review advisory 分本單 blocker／後續 backlog／忽略，不自動改寫 AC。

## 工程與安全邊界

已核可範圍內普通開發、修正、驗證、獨立 review 與滿足真實 gate 後正常 merge 可自主續行。保留 `quality`、required `agent-team/review`、protected settings 及全部平台條件；最新 Head 改動後重審，不以歷史 PASS、文件或評論代替必要 status，不用 bypass。

素材僅供既有本機開發輸入，保持 ignored，不提交或外送私素材、含素材截圖、憑證或個人私有路徑。歷史 PR #126、PR #127 及各自同來源樹 main CI 的私素材讀取 grant 均已耗用，本次新 Head 不能沿用。此次來源／Claude 外送與新私素材 CI 尚未核准，舊計畫文字核准不涵蓋本次修正來源。新網路私素材 CI 依 [既有 runbook](../local-private-ci.md)，在封存 Head 後另列 exact PR／Head／run／attempt 授權包；缺權限只暫停該段，不跳過必要 CI。

## 上一管理輪的已完成歷史

2026-10-05 管理切換已透過 PR #125 普通合併至 `main`，commit `b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7`。目標是「將當前開發管理方式全面導向 Agent Collab 而不是 agent team」，使用者選擇「互動代理主導，退役舊自動派工」，保留 Linear／GitHub 工單、PR 與 CI。該輪待辦已由實際交付取代，不重開；管理合併不代表遊戲 QA 或人員 accepted。


## 2026-10-06 敵車幾何細節與真受損煙續修

本機基線 `4a49059a279c0786d42a2f286905dd8fa6ac8640`。leadi 已要求增加可辨識車型的真車身／砲塔裝飾線，並選定紅色煙霧線條；沿原 LEA-195／既有視野、瞄準與實體遮彈，本輪精確凍結 spec SHA256 `5f2077632819261d881dac708520513df0c008dd9c466b41ac80311efe9810d6`，一次 `claude-opus-5-5` 計畫審查 approve／0 blocker。僅指定 spec 外送的核准已耗用，沒有來源／PNG／素材外送、新 CI／遠端 push／main 授權。

候選已實作同敵幾何資料與真 Smoke shared-base viewport，原 part／alpha／pick、模型、damage source、玩家淡出與訓練場來源保持。有限真渲染矩陣、RGB 嚴格 1／3／2 像素深度 tie 差異及原 D harness 紀錄詳見 [feature](../features/tank-occlusion.md#2026-10-06-敵車真幾何細節與受損煙候選)。作者證據只在本機 writer artifacts；尚待 root 精確 commit 封存與 fresh-context 最終驗收，未 stage／commit、未更新正式 Windows 預覽，人驗仍 needs_changes。


## 2026-10-06 殘骸灰線與訓練場玩家遮蔽修正

leadi 要求死敵保留透視、含真煙改淡灰，並回報訓練場玩家透視缺失；本輪沿既有 LEA-194／195，基線 `7d9b61f3e40ad7933ae6b285d0c384b4845a2b88`，鎖定 plan SHA256 `2807778365f2957ac71812a83c7e28a432912c3ea09a9d4418dcdb66badcbf4a`。指定 plan 單次外送授權 `call_6qkat1kJCLrQK0y28leVGmYG` 的實際 Claude 結果 approve／0 blocker，root 已處理五項 advisory、不新增 AC；外送 grant 已耗用，不涵蓋來源／PNG／素材、新 CI、push／main。

候選只改七個產品檔、既有 enemy_occlusion_smoke 的原死亡語意與三文件。W1–W3／P1–P2／R1 的作者有限證據、原 B／D、真相機尺寸和 PNG 見 [feature](../features/tank-occlusion.md#2026-10-06-殘骸灰色透視與訓練場玩家淡出候選)。最終 code 六直接 smoke exit 0／runtime errors 0，最後限定 W1／P2 GPU exit 0；作者自驗不代替 fresh。235 UID 保持，未改 Windows／main／素材或外送，尚待 root 精確提交與 fresh-context 同版驗收，人驗 needs_changes。


## 2026-10-07 原透視範圍人驗 accepted 與交付邊界

leadi 明確裁決：「可以，透視相關驗收通過，這張單可以收尾」。目前 Windows 可見產品版 `0d7b523922d8cc9654b4f4447006792e5e901b68`（tree `9c847ff1f2fa4bccf262b3178f3a8d47b8fcc4a4`，source SHA-256 `54082c9485679759d35f36244ea0d22bf45af781de12277d01f62346dace76d9`）的玩家／敵人透視、玩家外側 2m 漸變、灰色殘骸及真煙已 accepted。[LEA-194](https://linear.app/leadingtw273/issue/LEA-194)／[LEA-195](https://linear.app/leadingtw273/issue/LEA-195) 最新權威讀回皆 Done，owner、原 AC、194 blocks 195、歷史 needs_changes 與失敗紀錄原樣保留。

本機證據根目錄為 `agent-team/tmp/tank-player-wreck-occlusion-20261007/`：`fresh/report-final.json` 的同版 W1–W5 有限驗收成立，完整 tank／enemy smoke 各 exit 0、script／runtime frame errors 0；正常訓練死亡→三秒重生 GPU exit 0，已知兩條 shutdown D 與 RID warning 保留，不稱乾淨 error log 或新完整 quality PASS。`preview/ff-sync-readback.json` 核對 Windows 本機正常 FF 與 235 UID／586 素材 metadata；`closure/human-acceptance-readback.json` 為此次 leadi 裁決與兩票讀回 PASS。b876 exit 0／兩條 SCRIPT ERROR 的 A/W3 原始假綠及其他 D 未刪除。

本機產品已交付，人驗與兩票可收尾；GitHub main 仍 dc885899、open PR 0，本輪 source 尚未 upload／merge。後續來源對外 upload／review 須取得 exact source 範圍授權，新私素材 CI 須另列 exact PR／Head／run／attempt；舊 plan-only grant 已耗用，不能涵蓋 source／PNG／私素材。原 required quality／review 與正常 merge gate 保留，不以本機 accepted 宣稱 GitHub 交付完成。


## 2026-10-07 訓練場建築淡出啟動續修

leadi 對基線 `40c632f79dc4261a6d9d106608f03ae1368f27ff` 的開砲動效已 accepted，另選「接近實際車體遮擋時才平滑淡出（建議）」；LEA-194 重開、LEA-195 Done，R5＋outer2 保留。分支 `fix/lea194-training-occlusion-activation` 僅玩家啟動 gate／原 .18s amount 混合及必要測試、文件；本輪取代歷史預先淡出 P2，其他原 AC 不降低。鎖定 plan SHA-256 `c9c38f12ce7e989608ed90bf503e54d7a97f3316c9629adda23df875370229ab` 已原生 fresh 計畫審查 approve／0 blocker；外部計畫審查被平台拒絕，沒有有效 result，不重試外送。

實作、有限 A1–A4 和作者九直接 smoke RC 0／ERROR 0 見 [feature](../features/tank-occlusion.md#2026-10-07-訓練場建築淡出啟動修正)。原紅燈與訓練 fixture D 保留，修正停用方式後十二點涵蓋實際外露／遮擋。invalid window 沿原立即還原；.18s 只用於有效窗內正常進出資格。保持 236 UID、586 ignored 私素材與既有開砲／敵方／physics。本輪來源待同 HEAD fresh 來源／圖形及完整品質讀回，leadi 人驗 pending；沒有新的 GitHub CI PASS 或公開交付宣稱。


## 2026-10-08 LEA-134 首發 FX 預初始化

leadi 2026-10-08 回覆「可」，核可進場特效初始化與真首發／後三發對照。root 已查共享 LEA-134 未指派、In Progress，同目標無新 owner 工作、open PR 0；沿原 134、保留已 accepted 的開砲手感與建築過渡、LEA-195 Done。固定 A1–A7／CPU 預初始化限制與本機入口見 [feature](../features/tank-firing-feel.md#2026-10-08-首發-fx-同步預初始化)。

基線 `acdedad63df538256b18d79e799aa43fd48e5117`／tree `f971f91b16edc28d256b3e9ff5d202cdb29cba92`，新自有分支 `fix/lea134-firing-fx-prewarm`。sealed plan SHA-256 `8a65f598397faebbb0cd50d45bcba38c79c13e66925638db78229096109c2a27` 原生隔離審查 approve／0 blocker；外部計畫審查被平台拒絕，未重試，沒有跨模型有效結果或 source／素材外送。只改 CombatRuntime、既有 combat boundary smoke 與三份文件；不改 controller／scene／素材／cache／input／AI，不增 pool／await gate／viewport。作者四相關入口 actual exit 0／ERROR 0（既有 invalid ShotEvent fixture WARN 1 保留），新 combat assertions exact baseline 紅燈 exit 1／ERROR 1；首次 mapping ERROR 297 與一次候選 import 的 TCP ERROR 4 raw logs 留本機 writer，未冒稱完整 CI PASS。原四樹／cache／userdata 與候選236原UID／586素材metadata真guard保持，無新增UID。Windows 原生收益、最新 HEAD fresh、正式 M 交付及本輪人驗 pending；歷史 PASS 不代本輪證據。236 原 UID／586 ignored 素材 metadata、四個原工作樹／refs／Windows userdata 保全；新網路私 CI 與對外 source 操作不沿用舊 grant。
