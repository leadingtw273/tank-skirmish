# 一次接手入口

現役輪次為 [LEA-134 發射手感續調](ITERATION.md#2026-10-07-lea-134-發射手感續調)，自包含 F1–F5／ADR／參數與試玩入口見 [tank-firing-feel.md](../features/tank-firing-feel.md)。視覺加強、保留移動／瞄準，shake 0.5m→0.2m／原0.2s；正常合併／第二模型複審與做到Windows可實測已明示授權。手感人驗pending。

查 [LEA-134](https://linear.app/leadingtw273/issue/LEA-134)、現有PR與最新同HEAD證據。基線是 [PR #128](https://github.com/leadingtw273/tank-skirmish/pull/128) 已合併的 main `679decd21d6d3a2b38e237330cd995ebe320a8cb`，tree `c912a8afe76ade1d0551335614b82bdf6b7384ec`；原透視source／真CI／cleanup／本機交付／accepted與194／195 Done閉包。新分支 `feat/lea134-firing-feel-adjustment`，正式目錄和舊工作樹由root guarded FF正常同步。

候選新core、既有直接checks均作者actual exit0／ERROR0，diff-check通過；接手由非作者做同HEAD四車真viewport A/B與來源review、完整quality，不以作者證據代驗。之後root交Windows主圖F5／訓練場F6試玩；網路私CI不作preview前置。Short影格未取得，不稱精確復刻；235原UID／586 ignored素材保持，不外送，新Head私CI另需exacttuple，PR #128 grant不重用。

以下原透視交接保留為歷史；舊「main dc885899／尚未upload」已由PR #128閉包取代。現況以頂部與ITERATION新輪為準。

---

目前原透視範圍已本機交付並人驗 `accepted`：leadi 2026-10-07 明示可以收尾，產品版為 `0d7b523922d8cc9654b4f4447006792e5e901b68`。最新同版證據與裁決見 [ITERATION 最新引用](ITERATION.md#2026-10-07-原透視範圍人驗-accepted-與交付邊界)，原產品 AC／ADR／術語見 [tank-occlusion.md](../features/tank-occlusion.md)。本機 accepted 與 GitHub 交付分開；下方 2026-10-06 舊候選／needs_changes 是歷史，不能當作目前待驗狀態。

工單、負責人、依賴、工作範圍與共享進度查 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194) 與 [LEA-195](https://linear.app/leadingtw273/issue/LEA-195) 的現役紀錄；2026-10-07 最新兩票均 Done，原透視範圍人驗 accepted，195 仍依賴 194；owner、AC 與原範圍不改。本入口不另建中央 journal 或進度狀態表。

版本、PR、CI、獨立 review 與 merge 以 GitHub 為準。[PR #126](https://github.com/leadingtw273/tank-skirmish/pull/126) 是已合併的歷史工程交付；[PR #127](https://github.com/leadingtw273/tank-skirmish/pull/127) 亦已合併，本次基線為 [`main dc8858991316fa3207e9b6d5765e1e8cc3df89e1`](https://github.com/leadingtw273/tank-skirmish/commit/dc8858991316fa3207e9b6d5765e1e8cc3df89e1)，來源樹 `f0b14b98396f87bfbe71513252dbbdda2c830336`。GitHub main 目前仍 dc885899、open PR 0；本輪 0d7 來源尚未 upload／merge，待取得 exact source／新私素材 CI 授權並滿足真實 gate 後處理。2026-10-05 的完整品質、84 項圖形檢查及兩次 CI success 僅覆蓋該歷史版本，摘要見 [已交付歷史](ITERATION.md#本次續修與已交付歷史)，不能據此推定新 Head gate 通過。

歷史 PR #127 的需求與精確計畫文字審查已明確核准；2026-10-06 Claude（`claude-opus-5-5`）單次有效 result 為 approve／0 blocker，只讀該計畫且 SHA／mtime 不變。本機產品 0d7 已正常 FF 至 Windows，有限 fresh-context 驗收與 leadi 親測 accepted 均有讀回；後續接手核對這些精確證據，不能以作者自檢取代獨立驗收或未執行的完整 CI。計畫審查不擴為 code、材質、PNG 或私素材外送授權。

將下列 prompt 貼給接手成員自己的 agent；不需中央 Controller、原實作者對話或個人記憶。

```text
請依這個 repo 的真實共享檔案與平台紀錄接手我的工作：
1. 讀根 AGENTS.md、docs/agent-collab/PROJECT.md、ITERATION.md、WORKFLOW.md，
   再讀 docs/features/tank-occlusion.md 的本次親測回饋與有限 AC。
2. 查 Linear LEA-194／LEA-195、現有 PR、目前 branch／工作樹與版本；
   本次基線及目標分支以 ITERATION 為準，PROJECT 管理輪快照保留為歷史。
   PR #126／#127 已合併；GitHub main 仍 dc885899、open PR 0。
   Windows 產品版 0d7 已交付且原透視範圍人驗 accepted，194／195 均 Done，
   原依賴與 owner／AC 保留；本輪 source 尚未 upload／merge。
   後續 GitHub 交付先核 exact source／私素材 CI 授權，不重用 plan-only grant。
   對帳授權、我的工單、責任人、重複／重疊／依賴與真實交付現況。
3. 第一次讀完先回報授權與範圍、相關工單／PR、依賴、
   未知資訊與下一個可執行動作，不將歷史 PASS 當新版證據。
4. 已核可範圍內自主續行正常修正、驗證、獨立 review、
   符合真實平台條件的開發分支普通合併與可重現交付；
   不為日常動作重複請核可，不接管他人工單或覆寫未提交內容。
5. 產品方向、超出授權或無法協調的衝突才找對應的人；
   未知資訊只暫停依賴部分，繼續其他可獨立進行的核可工作。
```

身份／本人負責工單由接手成員設定；未設定時先唯讀對帳，不推定所有權。同步正式 source 前重查正式目錄 dirty 與使用者 Windows 編輯器工作，只精準套用，不 reset／stash；新 Head、PR 與試玩版本須實際讀回才記錄。

## 接手順序與保留邊界（2026-10-06 原輪紀錄）

以下原輪方向與 AC 保留為歷史；目前產品與人驗狀態以頂部及 ITERATION 的 2026-10-07 accepted 記錄為準，GitHub source／CI／merge 仍依原授權和 gate。

本次玩家視覺觀察與驗收優先使用主場景 `res://src/main.tscn`；leadi 確認問題發生於主場景，訓練場不是本次新增的玩家視覺 AC。原 P1–P3／E1–E3 與既有回歸入口保留，敵方範圍不擴張。

本次修正方向是讓 faded buildings 的 soft pass 依同相機原始最近表面深度只混合最近面，避免前後表面疊色；共同 5m、1 個 render pixel 外緣、圈外 PBR／深度、完整陰影與原 foreground／Tank4 包絡保持。實作及新 Head 驗證尚待讀回，不將此方向寫成 PASS。

本次玩家共同半徑預設 5m，原單一設定與投影函式沿用；8m 為歷史預設，原裁決未將它鎖定。玩家圓窗常駐跟隨受控車，前景 building 投影 bounds 交窗即選取，不等首個車體遮擋 ray。中心連續 alpha 為 0 或近 0、無 noise／hash／dither，外緣平滑過渡；圈外 opaque 外觀與完整陰影保持，透明 next_pass 僅補窗內且不重複投影陰影。

前景深度以 root 的 `stable_world_center` 加原 `part_surface_points` 包絡決定，取最遠的 camera-local Z 最小值，缺部位時 fallback centre；opaque／透明 shader 使用同一 foreground gate，shadow pass 不 gate。原 shared material 不改，換車／null／死亡／退出還原 instance overrides 與 next_pass。

敵方 mask RGB 編碼真實部件類別，alpha silhouette 與既有 picking 保持；只加約 2px 外框與稀疏部件界線，不填紅、不畫三角 wireframe。Tank4 固定上車體照真名 `Tank_Turret` 分類，Tank1 沒有獨立 turret mesh，不虛構砲塔。舊 interior_red==0／外框限定已被本次明示細節線取代。

原 SubViewport／World3D、45 joints 履帶 skin／bone pose 同步、車型 near／far／角度、逐部位 LOS、camera 建築遮擋 gate、真目標世界點拾取與 Aim 接點保持。圈外紅線 0；空白像素不命中；砲口首撞、Projectile 實體遮彈、傷害分類、AI 與物理不改。

只將既定 AC 反例、正常路徑實際失敗或具體資安／資料破壞證據列本單 blocker；其他 advisory 列後續 backlog／忽略，不改寫完成定義。既有三個產品術語沿用，不新增框架。

正式主圖沒有敵方 Encounter，本次不植入敵方戰鬥布局；敵方固定案例限現役訓練場與有限測試場景。Windows 單人 PvE、正交斜俯視、四車與 Forward+ 前提保持，不擴跨渲染器義務。

工單參考 [ISSUE.md](ISSUE.md)，獨立 review 參考 [REVIEW.md](REVIEW.md)，PR 使用 [PR 範本](../../.github/PULL_REQUEST_TEMPLATE.md)。驗收依本次 P1–P3／E1–E3，必跑六個直接 smoke 與完整 `scripts/ci.sh`，新的圖形輸出不覆寫歷史。最新 Head 的 fresh-context 獨立實跑、source review、平台 gate 與 leadi 親測分開記錄；工程作者不可自稱驗收，人驗維持 needs_changes，直到 leadi 真實確認。

保留 [PROJECT.md](PROJECT.md) 環境／平台設定、[WORKFLOW.md](WORKFLOW.md) 的同 Head 獨立 review／必要 CI／普通 merge 規則、required `quality` 與 `agent-team/review` 及 protected settings。不跳過 gate、不降低 checks、不用 bypass；舊 Team registration／Job 只作歷史相容資料，不啟動舊派工。

安全與 CI 權威仍為 [host-managed-settings.md](../host-managed-settings.md) 及 [local-private-ci.md](../local-private-ci.md)。私素材只作本機開發輸入，保持 ignored，不提交或外送。歷史 PR #126、PR #127 及各自同版 main 私素材 CI 的 grant 均已耗用；本次來源／Claude 外送與新私素材 CI 尚未核准，不能重用舊 grant；本次新 run／attempt 仍須封存後列 exact PR／Head／run／attempt 另取核准。缺權限只暫停該段驗證；本次計畫文字 review 授權不涵蓋 source、PNG、私素材、公開發布、商店發行或破壞性操作。


## 本機敵車細節與真煙候選（2026-10-06）

最新增強候選沿 LEA-195，權威與固定 G1–G3／S1–S2／L1／R1 見 [本輪紀錄](ITERATION.md#2026-10-06-敵車幾何細節與真受損煙續修) 與 [feature](../features/tank-occlusion.md#2026-10-06-敵車真幾何細節與受損煙候選)。writer 已完成有限 Forward+ 真渲染自驗，含自然訓練場入口 PNG；alpha／pick 保持，首輪嚴格 RGB 少量 body／履帶 depth tie 差異保留待 root 裁定。這不是 fresh-context PASS 或人驗 accepted。

產品可寫位置只在隔離 worktree；正式 Windows 預覽尚維持既有 `4a49059a279c0786d42a2f286905dd8fa6ac8640`。接手先核對 root 封存的新 Head／tree／同版 fresh 驗證，不沿用作者敘事代驗收。指定 spec 外送 grant 已耗用，不含 source／PNG／私素材、新 CI、遠端推送或 main；原素材 ignored 與 UID metadata 必須保持。


## 殘骸灰線與訓練場玩家淡出候選（2026-10-06）

本輪產品裁決與授權見 [ITERATION](ITERATION.md#2026-10-06-殘骸灰線與訓練場玩家遮蔽修正)，固定 W1–R1 與作者實跑見 [feature](../features/tank-occlusion.md#2026-10-06-殘骸灰色透視與訓練場玩家淡出候選)。來源候選已完成作者六直接 checks 與有限真渲染；原 B／D 及 corrected log 保留，不是 fresh-context PASS 或 accepted。接手須核對 root 封存的新 Head／同版 fresh，而不是沿作者敘事代驗。

writer 沒有 stage／commit、修改正式 Windows 預覽／235 UID／素材、外送 source／PNG 或推送 main。正式 M 仍維持既有 `7d9b61f3e40ad7933ae6b285d0c384b4845a2b88`，之後只由 root 按已核可 guarded fast-forward 同步。計畫外送 grant 已耗用，無本輪新 CI／素材 runner 授權，人驗仍待 leadi F8→F6 重啟訓練場確認。


## 灰殘骸矩形 FX 板本機回歸（2026-10-07）

本輪僅修已有 AC「實體模型＋真煙、排除 FX 面片」漏收的 `effect_mesh`，共用 collector 按既有群組略過 Mesh、仍遞迴 child；真模型 Quad／原世界 FX 與 Smoke 不動。根因及有限 Q1–Q3 作者證據見 [feature](../features/tank-occlusion.md#2026-10-07-灰殘骸煙上方矩形板回歸修正)，本機 `agent-team/tmp/tank-smoke-quad-20261007/writer/` 保存原紅燈 17 failures（16 實際反例＋1 測試 D）、最終兩關聯 checks exit 0，以及單台 tank2 真受損／死亡渲染。

作者 GPU 原 raw exit 2 的唯一 D 為跨 stage 比較原煙啟動的 local_coords／seed，16 項產品量測 true，不稱 overall PASS；source 原 local_coords 設定與 restart 已讀回，沒有修改 FX／粒子。接手在本輪 `fresh/` 核對固定同 stage 的 source/base／穩定參數及 Q1–Q3；不能把作者畫面或量測敘事當 fresh 驗收。235 UID／586 素材 metadata 保持；writer 不 stage／commit／同步 M／外送或 CI，人驗 needs_changes，待 leadi 確認。


## 訓練場建築淡出啟動候選（2026-10-07）

當前沿 LEA-194、分支 `fix/lea194-training-occlusion-activation`，base `40c632f79dc4261a6d9d106608f03ae1368f27ff`；該版開砲已人驗 accepted，195 保持 Done。本輪 user 選接近真車體遮擋才淡出，共同5m核心＋2m外圈保留，替代舊預先淡出 P2。有限 A1–A4、完整玩家 sample gate、原 .18s amount 混合與九直接入口作者實跑 RC 0／ERROR 0 見 [feature](../features/tank-occlusion.md#2026-10-07-訓練場建築淡出啟動修正)；invalid/offscreen/behind-camera window 保持立即還原。原紅燈及 fixture D 均留存，不以作者結果代 fresh 驗收。

接手核對 root 封存的同 HEAD／tree／來源 hash，再獨立來源、真圖形、完整品質與 guarded 正常 FF 試玩；本輪人驗 pending。僅改 controller、既有 tank occlusion smoke 及三份文件，無 shader／素材／模型／camera／fire／physics／UID 修改。236 UID 與 586 ignored 素材 metadata 保全；原 M／上一開砲工作樹／舊透視工作樹及 main/origin 不由作者更動，來源及私素材不外送，GitHub CI／merge 另按實際平台紀錄。


## 2026-10-08 首發 FX 預初始化候選

現役沿 LEA-134、`fix/lea134-firing-fx-prewarm`，base `acdedad63df538256b18d79e799aa43fd48e5117`；leadi 回覆「可」核可進場初始化與首發／後三發量測。固定 A1–A7、真授權、有限作者入口與 Windows F5／F6 在 [feature](../features/tank-firing-feel.md#2026-10-08-首發-fx-同步預初始化)，輪次在 [ITERATION](ITERATION.md#2026-10-08-lea-134-首發-fx-預初始化)。原開砲手感、建築過渡 accepted 與195 Done保留；本輪人驗 pending。

只在共用 CombatRuntime ready 同步隱藏初始化四個純 FX wrapper 並 immediate free，source registration／換車／正式每發保持；不能稱 GPU pipeline 全暖或首發全面修復。作者四有限相關 checks actual exit 0／ERROR 0，既有 invalid ShotEvent fixture WARN 1 留存；原 baseline 紅燈與首輪 mapping／import raw errors 不隱去，本機 writer 保存 commands／logs／guards。原四樹／cache／userdata、236原UID／586素材metadata保持，沒有新UID。非作者最新 HEAD fresh／Windows Native startup＋一首發三暖發量測仍 pending，後續同版封存 artifact 與 Linear 是結果權威；未跑完整 CI，不預填 PASS。root 在無 blocker後 guarded 正常 FF 同步 M，作者不直接碰正式 source／original caches／236 UID／586 ignored素材 metadata，不 push／CI／merge main或外送素材。跨模型計畫外送被平台拒絕，已使用原生隔離 approve／0 blocker 替代並保留限制。


## LEA-208：訓練場敵車選向 CPU 候選

使用者已明確接受首發卡頓，原話及「訓練場」回覆見 [ITERATION](ITERATION.md#lea-208訓練場敵車轉角脫困選向成本修正)。新 `fix/lea208-ai-recovery-selection-cost` 基於 `b9a03acaa1c6e109b3a360f4fe5fbb94a56f87aa`；只作 typed radius、query-local 私有 ray parameters 與同 query driving preview 三項同義修正，保持原 AI collision／cap／horizon／微步／候選／terrain-first／drift 與已驗收首發、相機及透明過渡。

接手查看本輪同 source 的作者四有限入口 logs／original algorithm oracle、Windows 原生 before／after 短窗與最新封存 HEAD fresh 審查，勿將作者自驗／20ms 上限／歷史完整 CI 當性能改善或新 gate PASS；原 fixture D 與失敗原文保留。Windows 有限 before／after 已由 root 讀回支持採用，數字與同 source tuple 保留於本機 receipt；ray parameters 重用沒有獨立量測收益宣稱。新增同義 smoke／terrain／continuation 均 exit 0／ERROR 0／WARN 0；escape handoff exit 1／ERROR 2，exact b9 baseline 同兩個 Mirror gun／hull fixture 失敗，按 root 裁決保留既有 backlog，不改 expected。fresh、正式本機 guarded FF 與 AI 人驗仍 pending，完整 CI 未跑。新的功能入口 `res://tests/ai_recovery_selection_cost_smoke.gd`；本機交付後開 `res://src/maps/training_ground/training_ground_playtest.tscn` F6，沿既有訓練場敵車轉角位置與移動測法驗證。來源／私素材不外送，不操作原 Windows editors／games，原 236 UID／586素材／工作樹／refs／cache／userdata 守衛保持。
