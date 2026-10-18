# 2026-10-16 LEA-212 收尾步驟 B：PR #130 私素材閉包修正

本輪沿 [PR #130](https://github.com/leadingtw273/tank-skirmish/pull/130)，基線 `1e5c0683a6e6730dd0bc1b7cf2ea4b3b5d2097e8`。企劃依本機 `.git/codex-task-lea212-closeout.md`「步驟 B」及「企劃裁決：B2–B4 續行」核可方案 a：只補缺少的兩個路燈 GLB 與草 atlas、另建 repo 外 0600 素材封存檔、更新 lock／來源紀錄，完成乾淨本機 quality 及新 Head 的 PR 私有 CI 後停止。**不合併、不發 `agent-team/review` status、不改 Linear。**此續行授權取代下方歷史步驟 A 的停止點，但不擴張產品範圍。

原 586 筆 lock 與 `quarter.tar` 還原至乾淨 checkout 後，`bash scripts/ci.sh` 實測 exit 1，首個失敗為 import 載入 `grass_basic_atlas.png`；獨立盤點確認缺檔全集為 `assets/AtomicRealmModularRoads/lighting/lamp_1.glb`、`lamp_2.glb` 與 `assets/BinbunGrass/texture/grass_basic_atlas.png`。本機證據在 `artifacts-local/lea212-20261015/pr130-b1-fix/`，不隨 PR 上傳。

新版 lock 共 589 筆，原 586 筆路徑、bytes、SHA 與 payload 保持；原 archive 不覆蓋、不刪除。新增三檔的 `.import`／匯入快取由 Godot 重建，兩 GLB 無外部 buffer／圖像 URI，不另加入 PNG。來源與封存操作見 [AtomicRealm 路燈](../assets/atomicrealm-lamps-provenance.md)、[Binbun 草 atlas](../assets/binbun-godot-grass-provenance.md#2026-10-16-lea-212-本機-ci-封存輸入)、[本機私有 CI](../local-private-ci.md)。AtomicRealm 授權狀態仍「未查證」；企劃裁決同 ZIP 的路燈沿既有 base 輸入狀態，不套用 Quaternius CC0，也不寫成已查證。

驗證要求為 `python3 tests/local_ci_assets_test.py --archive <新版 archive>`、乾淨 checkout 只還原新 archive 後完整 `bash scripts/ci.sh` exit 0／ERROR 0，以及新 Head 的 PR `quality` 真 run／job success、三項清理旗標皆 true。實際結果與精確 Head／run 以完成回報、GitHub 及本機收據為準；此處不預填成功。launcher 從當前 lock 取得 archive SHA；workflow 的 `quarter.tar` 是 gate 傳遞名稱，不是 host 封存版本，不需變更。

## LEA-212 backlog 補記（本單不實作）

PR #130 獨立 review 的 reviewed Head 為 `1e5c068`，判定 `changes_requested`；本單只修素材閉包 blocker B1。報告為本機 `artifacts-local/lea212-20261015/pr130-review/REVIEW.md`，advisory 1–13 全部保留 backlog，不改寫為本單 AC：

1. 預繪不可見性自動斷言與 omni 陰影。
2. `frame_pre_draw` 首幀座標／RenderingServer 同步。
3. 停止繪製與離場再入場的預繪生命週期。
4. `preprocess` 設定與 restart／play 順序。
5. 相機移動時重算 117 燈、重送 shadow 與陣列配置成本。
6. 8192² shadow atlas 的 VRAM 成本。
7. 畫邊燈光 pop 與遮擋更新延遲。
8. 雨碰撞與 lifetime、6.6 硬編碼及 TIME rollover。
9. 正俯視 NaN、退化凸包與草地兄弟節點依賴。
10. variant2 雙燈頭與固定光源位置；主圖仍只用 variant1。
11. 落點重用斷言精度及無效程式碼。
12. 本次 review 未重跑兩支原生 GPU smoke 的證據限制。
13. 下方原七項 backlog 全部保留。

另列 **AtomicRealm 整包正式授權查證**，屬既有 base／道路包問題，不是本單引入。leadi 對產品 ce49e89 的人驗 accepted 保持；收尾只改 CI 素材 metadata／驗證筆數與文件，玩法及視覺產品 bytes 不變。

---

# 2026-10-16 LEA-212 雨夜多輪人驗 accepted 與收尾步驟 A

現役狀態：LEA-212 產品人驗 **accepted**，待草稿 PR、平台核對、合併與交付；下方有日期的舊 pending 記錄保留為歷史。本輪功能與可重現入口見 [雨夜路燈](../features/rain-dusk-lamps.md)、[第三輪首發](../features/rain-first-shot-round3.md) 與 [T1b 首發預繪](../features/rain-first-shot-t1b.md)。

## 核可來源與本步邊界

leadi 於 2026-10-16 實測主工作目錄 `playtest/lea212-round4`、產品 Head `ce49e89e1603f120aa581cd9b7b3408360d54e5c` 後表示：「當前狀況我驗收通過，可以做收尾合併了，並且去做關單。」企劃在本機 `.git/codex-task-lea212-closeout.md` 記錄人驗 accepted 與 push／PR／合併／關 LEA-212 的整體授權。

本次明示只執行收尾步驟 **A1–A4**：只改本 ITERATION 與 HANDOFF 文件、繁中 commit；在帶齊私素材及生成資源的額外 `/tmp` 副本對最終文件 Head 跑一次完整 `bash scripts/ci.sh`；push `feat/lea212-rain-atmosphere`，開至 `main` 的草稿 PR；用 Linear MCP 只讀目前狀態、負責人與關聯／子單。**草稿 PR 開立後停下，不合併，不更改 Linear 狀態。**這個停止點優先於整體合併／關單授權。

產品 bytes 維持已 accepted 的 ce49e89；只在 `/tmp/tank-skirmish-lea212-atmosphere` 修改文件，不切換主工作目錄分支，不在主目錄或該工作樹啟動引擎。原有未提交 `override.cfg` 保留，不提交；`.godot`、私素材、生成資源及 `artifacts-local` 不進 Git。私素材網路 CI 仍須依原 runbook 的 exact tuple 授權，不由這次 push／草稿 PR 授權推定可啟動。

## 需求與逐輪範圍

1. **滑鼠造成路燈閃爍**：leadi 回報滑鼠移向某盞燈就暗、移開又亮。修正路燈自遮光，保留後續恢復的月光柱影，不改坦克瞄準與相機。
2. **第一輪雨夜氛圍**：雨本身「算不錯」，但只是單純下雨，需提升雨夜感；以「接近入夜，路燈主導」為方向，增加暖光暈、燈下雨絲、貼地薄霧與濕地反光，恢復柱影並將燈放到街邊，保留玩家車可讀性。
3. **第二輪三點**：坦克不要無來源自發光，改為車頭兩盞燈且四車型各有錨點；路燈／車燈及自繪光效不能穿牆；全圖沿路配置路燈。最後為 117 盞、最小間距 12m、最大沿路空隙 36m，畫內候選全亮並有 Spot 陰影；效能使用逐幀繪製間隔與 CPU／GPU 分項，不沿用 TIME_PROCESS 偽分位數。
4. **第三輪五點**：第一次開砲嚴重卡頓；草與砲煙疊合異常；車燈應由車身而非履帶前端發出；光暈只在燈罩下方；濕柏油倒影不應像鏡面。T1b 以正式 viewport 三幀實際預繪處理首發，保留原玩法、物理、相機、瞄準、遮蔽及輪廓。
5. **第四輪雨**：避免螢幕前雨幕、加上縱深與隨時間變化的風、將粗白線改為細軟雨絲。v1 被指出像固定位置的屋頂漏水；改用分散的整數雜湊落點，保留 F5 短斜拖影、真受光暖雨與細小落地漣漪，修正槽位回收與碰撞後外插。

## 跨模型工程驗收紀錄

以下為各輪獨立 Claude Opus 5.5 驗收，不是作者自驗或方向 checkpoint；完整 Head 及 VERDICT 已讀回。本機證據根為 `/home/markchou/project/tank-skirmish/artifacts-local/lea212-20261015/`，報告保持 ignored，不隨 PR 上傳；這些本機判定不是 GitHub approval、required status 或平台 CI。

| 輪次 | Reviewed Head | VERDICT | 本機報告（相對證據根） |
| --- | --- | --- | --- |
| round2 | `ae09baa3632ba57cb288d32f1f45e55e2a207e0e` | PASS | `cross-model-round2/report.md`，總結第 204 行 |
| round3 | `8cb90ab038e1a8f35677241672b44ef7b5a69a17` | PASS | `cross-model-round3/REPORT.md`，總結第 81 行 |
| round4 | `ce49e89e1603f120aa581cd9b7b3408360d54e5c` | PASS | `cross-model-round4/REPORT.md`，總結第 172 行 |

round2 的 87 支全量 smoke 中有 13 支在 baseline 同樣失敗；PASS 的解讀是無本輪回歸、直接相關 smoke 通過，不能寫成 87 支全綠。round3 為 18 項候選 headless 檢查通過；round4 的雨量、F5 靜幀斜度與長時間轉換風險保留 advisory。leadi 對 ce49e89 的人驗 accepted 與這些工程判定分開記錄，未要求藉收尾消除全部 advisory。

## 後續 backlog（本步不實作、不新開單）

- 鄰燈互投影：共用 caster 排除層也排除了鄰燈燈柱，需後續評估分離自遮光與鄰燈遮光。
- 清理 13 支既有失敗 smoke：保留 baseline 同失敗與工具／fixture 分類，不放寬既有測試換綠燈。
- 相機 size25 草地 alpha hash 細點。
- 燈下濕斑的方塊感。
- F5 靜幀雨絲斜度偏弱；動態與靜圖需求分開評估。
- `uint(TIME*65536)` 的長時間越界風險。
- Windows 原生結束時 RID／Texture 洩漏與清理訊息。

## 交付與平台核對

收尾基準：功能分支 `feat/lea212-rain-atmosphere` 的 ce49e89；2026-10-16 開始 A 步驟時遠端 `main` 為祖先 `590c80177125bd8f86acc273954d5f3d4b1d9d2d`、open PR 0。草稿 PR 及最終文件 Head 以完成回報與 GitHub 讀回為準，不以這個歷史快照推定後續平台狀態。

A2 的最終 Head 本機完整 CI 實際命令、exit code 與 raw log 記入收尾證據及草稿 PR；不沿用 ce49e89 的舊 CI 冒稱新 Head 已跑。GitHub review、CI Head／結果與真實合併條件目前為「待設定／未查核」，後續必須依同 Head 真實結果處理。人驗 accepted 不代表已合併、已交付或 Linear 已關單。

本步 Linear 僅只讀查核，不新增關聯、不接管負責人、不評論或改狀態；LEA-209 與其他 related／子單是否另行收尾交企劃判斷，不能因相關就自動一併關閉。

---

# 2026-10-12 草地人驗 accepted；雨天近夜晚續輪

leadi 明示接受本機草地版本 `d5d7ef69`；LEA-209 已讀回人驗 accepted 評論，原工程驗收與本機交付證據保留於 `/home/markchou/evidence/retained-project-data-20261012/tank-grass-wall-20261012/`。GitHub main 尚未包含本機草地續修，不以人驗代替 CI／merge。

本輪 [LEA-212](https://linear.app/leadingtw273/issue/LEA-212/主地圖雨天近夜晚與可推倒路燈) 主地圖雨天近夜晚暖路燈已形成隔離候選：六燈可由原 Tank2 真實撞倒即熄、再推動，5 秒後開始 2 秒淡出並完整釋放。有限作者原生同 F5 畫面、完整生命週期及 baseline／candidate 四原 smoke 已留證；詳見 [雨夜路燈 feature](../features/rain-dusk-lamps.md)。獨立同 Head 驗收、本機正式交付及本功能產品人驗均 pending，不沿用原草地 accepted；既有證據路徑搬遷修改正常保存。

---

# 2026-10-12 LEA-209 牆邊草留白修正

leadi 確認牆邊只見建築與地面、分界太明確；本輪沿既有自然銜接 AC 修正。建築 XZ 凸包排除距離由 1m 改為 0.15m，道路保留 1m；草型、密度／seed、材質受光／深度／風動與玩法保持。

作者同版 WinGodot4.7.1／Forward+，同 F4 相機實拍：出生 11820→12494 株，庭院樣本最近草根至低層外緣 1.0208→0.1551m；60m 方框檢查 24301→29244 根，道路 1m／建築原凸包內／樣本建築 0.15m 排除反例均 0。兩原 smoke actual exit0、ERROR／WARNING0；圖形退出兩版同有既有 RID 清理訊息。證據在本機 `/home/markchou/evidence/retained-project-data-20261012/tank-grass-wall-20261012/{baseline,candidate}`，不是完整 benchmark 或新版人驗。

候選 `fix/lea209-grass-wall-gap` 待 fresh-context 同 Head 驗收與 root 正常本機 FF；沒有 push／PR／CI／關票或來源／私圖外送。以下為前輪紀錄。

---

# 2026-10-12 LEA-209 相機範圍草地續輪

leadi 先確認出生草效果很好，核可按相機可見地面＋外圍緩衝分塊生成／跨chunk更新／固定位置／有限快取；沿LEA-209，不改認可出生樣式。最新閉包計畫與原生隔離plan review approve／0 blocker由root GO，本輪基線 `0fde8832717d3639567d430e9d1a407ffbe85cae`、分支 `feat/lea209-camera-grass-stream`。

16m chunk、48→64m近區密度過渡、0.2／0.4／0.8m固定嵌套格、dense80m／mid外24m／base32m預載；草與原Ground連續共用palette／noise受光，玩法及原素材保持。750,000株總cap涵蓋出生／active／cache／pending，active400／cache64、2ms候選deadline／2048候選／每frame單次6400株upload。詳細固定實作與有限驗證入口見 [main-ground-grass.md](../features/main-ground-grass.md)。

作者本機Forward+有限路徑與兩原smoke actual exit0，birth11820／重複與排除反例0、peak749809；同相機baseline與16frame跨格GIF已留存，效能／raw入口見feature。工程獨立驗收／本機FF與新功能人驗pending；原出生樣式accepted不延伸成新串流功能accepted。不push／PR／網路CI／關票或外送source／圖／素材；root待fresh同Head PASS後正常本機FF。下方歷史不作本輪PASS。

---

# 2026-10-09 LEA-209 出生庭院草場續修

leadi 新裁決：全地圖大量生成有效能問題；先只鋪主世界坦克出生的空地，草須自然綿延交接。沿同票修正，尚待本機獨立工程驗收與 leadi 實測，不沿用前版人驗或 CI 結果。

本版固定 `Rect2(-116,-115,25,24)`，實車出生 `(-108,0,-106)`；0.2m 格距、±0.08m 抖動、seed117，15,000 候選經既有道路／建築世界 XZ 凸包外擴1m排除。一次性單一 MultiMesh，移除全地圖底草、視野細節tile與每幀生成。Quad 0.4×0.4m、subdiv2/2、centerY0.2，原四形atlas／billboard及平滑alpha，wind(0.6,0.3)。出生patch的無碰撞PlaneMesh與草葉共用同noise／palette／原demo受光算法；其餘floor材質保持。

免費原source atlas只是新增一個ignored本機CC0輸入，原586私素材與239原UID保持；shader/PNG來源不修改，atlas不Git／不外送。正常來源分支 `feat/lea209-spawn-grass`，基線 `3e88ec173e30b452df43749230ad4aba2c2148b4`。本輪不push、PR、網路CI或關票；本機FF由獨立驗收後交付處理。

作者同source有限證據：WinGodot4.7.1／Forward+，15,000候選、11,820株、單一MultiMesh、生成7ms；草根出界0／獨立凸包重建排除反例0、無每幀process，共用noise／palette讀回true。F1／F4與32幀2.56秒wind已實拍，兩原smoke actual exit0且無ERROR/WARN；圖形runtime的WASAPI與退出RID清理訊息與基線相同。此為作者證據，獨立驗收與leadi人驗仍pending。

以下前版記錄保留作歷史，不當作本版PASS。

---

# 2026-10-07 LEA-134 發射手感續調

狀態：LEA-134 發射手感／首發、LEA-194 建築淡出與 LEA-208 訓練場 AI 修正均已由 leadi 實測 accepted；本輪進行正常正式收尾。最新 HEAD 的必要 CI、獨立審查、PR 與合併仍須依 GitHub 實況完成，不沿用歷史 PASS。

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

本機證據根目錄為 `/home/markchou/evidence/retained-project-data-20261012/tank-player-wreck-occlusion-20261007/`：`fresh/report-final.json` 的同版 W1–W5 有限驗收成立，完整 tank／enemy smoke 各 exit 0、script／runtime frame errors 0；正常訓練死亡→三秒重生 GPU exit 0，已知兩條 shutdown D 與 RID warning 保留，不稱乾淨 error log 或新完整 quality PASS。`preview/ff-sync-readback.json` 核對 Windows 本機正常 FF 與 235 UID／586 素材 metadata；`closure/human-acceptance-readback.json` 為此次 leadi 裁決與兩票讀回 PASS。b876 exit 0／兩條 SCRIPT ERROR 的 A/W3 原始假綠及其他 D 未刪除。

本機產品已交付，人驗與兩票可收尾；GitHub main 仍 dc885899、open PR 0，本輪 source 尚未 upload／merge。後續來源對外 upload／review 須取得 exact source 範圍授權，新私素材 CI 須另列 exact PR／Head／run／attempt；舊 plan-only grant 已耗用，不能涵蓋 source／PNG／私素材。原 required quality／review 與正常 merge gate 保留，不以本機 accepted 宣稱 GitHub 交付完成。


## 2026-10-07 訓練場建築淡出啟動續修

leadi 對基線 `40c632f79dc4261a6d9d106608f03ae1368f27ff` 的開砲動效已 accepted，另選「接近實際車體遮擋時才平滑淡出（建議）」；LEA-194 重開、LEA-195 Done，R5＋outer2 保留。分支 `fix/lea194-training-occlusion-activation` 僅玩家啟動 gate／原 .18s amount 混合及必要測試、文件；本輪取代歷史預先淡出 P2，其他原 AC 不降低。鎖定 plan SHA-256 `c9c38f12ce7e989608ed90bf503e54d7a97f3316c9629adda23df875370229ab` 已原生 fresh 計畫審查 approve／0 blocker；外部計畫審查被平台拒絕，沒有有效 result，不重試外送。

實作、有限 A1–A4 和作者九直接 smoke RC 0／ERROR 0 見 [feature](../features/tank-occlusion.md#2026-10-07-訓練場建築淡出啟動修正)。原紅燈與訓練 fixture D 保留，修正停用方式後十二點涵蓋實際外露／遮擋。invalid window 沿原立即還原；.18s 只用於有效窗內正常進出資格。保持 236 UID、586 ignored 私素材與既有開砲／敵方／physics。本輪來源待同 HEAD fresh 來源／圖形及完整品質讀回，leadi 人驗 pending；沒有新的 GitHub CI PASS 或公開交付宣稱。


## 2026-10-08 LEA-134 首發 FX 預初始化

leadi 2026-10-08 回覆「可」，核可進場特效初始化與真首發／後三發對照。root 已查共享 LEA-134 未指派、In Progress，同目標無新 owner 工作、open PR 0；沿原 134、保留已 accepted 的開砲手感與建築過渡、LEA-195 Done。固定 A1–A7／CPU 預初始化限制與本機入口見 [feature](../features/tank-firing-feel.md#2026-10-08-首發-fx-同步預初始化)。

基線 `acdedad63df538256b18d79e799aa43fd48e5117`／tree `f971f91b16edc28d256b3e9ff5d202cdb29cba92`，新自有分支 `fix/lea134-firing-fx-prewarm`。sealed plan SHA-256 `8a65f598397faebbb0cd50d45bcba38c79c13e66925638db78229096109c2a27` 原生隔離審查 approve／0 blocker；外部計畫審查被平台拒絕，未重試，沒有跨模型有效結果或 source／素材外送。只改 CombatRuntime、既有 combat boundary smoke 與三份文件；不改 controller／scene／素材／cache／input／AI，不增 pool／await gate／viewport。作者四相關入口 actual exit 0／ERROR 0（既有 invalid ShotEvent fixture WARN 1 保留），新 combat assertions exact baseline 紅燈 exit 1／ERROR 1；首次 mapping ERROR 297 與一次候選 import 的 TCP ERROR 4 raw logs 留本機 writer，未冒稱完整 CI PASS。原四樹／cache／userdata 與候選236原UID／586素材metadata真guard保持，無新增UID。Windows 原生收益、最新 HEAD fresh、正式 M 交付及本輪人驗 pending；歷史 PASS 不代本輪證據。236 原 UID／586 ignored 素材 metadata、四個原工作樹／refs／Windows userdata 保全；新網路私 CI 與對外 source 操作不沿用舊 grant。


## LEA-208：訓練場敵車轉角脫困選向成本修正

使用者原話：「剛剛測試首發射級卡頓便可以接受了，剩下還有AI敵人在轉角判定很容易掉禎」，接著回覆「訓練場」。首發人驗已通過，既有相機、透明過渡與 AI 玩法保持；本輪 AI 修正人驗 pending。沿新 [LEA-208](https://linear.app/leadingtw273/issue/LEA-208)，從 clean `b9a03acaa1c6e109b3a360f4fe5fbb94a56f87aa` 隔離分支 `fix/lea208-ai-recovery-selection-cost` 工作；不以先前完整 CI／人驗代本候選結果。

本輪只作三項同義成本修正：radius 逐 shape 提前取得 typed points／world transform 與 root origin，保留原頂點順序、distance_to／maxf／初值與 +0.01；同步 provider 私有重用一個 ray parameters、每次完整覆寫原旗標／from／to，保持四條查詢與 reserve(4)；selecting_escape preview 優先用同 query 的既有 driving model，solver null／缺方法仍用 tank direct fallback。保留 10s 選向／3s continuation、4096 query／20ms cap、完整模型碰撞、微步／候選／terrain-first／drift，沒有新 async、節流、pool、profiler 或 physics／aim／ShotEvent／renderer／cache／素材／CI 變更。

本機封閉計畫及性能證據保存在本輪 isolated artifacts；新增 `res://tests/ai_recovery_selection_cost_smoke.gd` 以真 Tank2 同 snapshot，保留完整原 radius／sample／provider 支撐算法作 oracle，比較全支撐欄位與 query 計數、連續 pose／mask／exclude／旗標覆寫、八組模型輸入與真 selecting_escape 輸入的原 forward／angular 輸出；ground segment 後加 drift 另屬原處理。相關回歸只跑 `rigid_terrain_segment_smoke`、`escape_handoff_smoke`、`recovery_continuation_smoke`；新增同義 smoke、terrain 與 continuation 均 actual exit 0／ERROR 0／WARN 0。escape handoff actual exit 1／ERROR 2／WARN 0；相同 flags／資產／cache／script 的 exact b9 baseline 亦相同兩個 Mirror gun／hull 失敗（queries 103／148、相同 blocker／fraction／phase），因此 root 分類本單前既有 fixture／backlog，未改原 expected 或 physics。新 smoke 初次 typed empty-array fixture D 的 script／shutdown errors raw 保留，測試修正後通過；完整 CI 未跑，不冒稱全部回歸 PASS。

是否採用須由同場景／Tank2／heading／cap 的 Windows 原生 before／after 各 120 ticks 證明實質收益，初始化與性能窗分開，不含每內層 query 計時包裝，不以碰到 20ms 上限推定改善。產品三檔已固定供 Windows before／after 量測，root 讀回短窗有實質改善並支持採用；詳細 source tuple／性能分布以本機封存 receipt 為準，ray parameters 重用未量到獨立收益，僅保留已驗證同義結果。最新封存版本 fresh-context 審查／有限實跑、guarded 正常 FF 與 AI 人驗仍 pending；收益不足交 root 裁決，不降低碰撞精度或擴大架構。236 原 UID／586 ignored 素材及原工作樹／refs／cache／Windows userdata 保全，原 editors／games 不操作；本單不是 GitHub CI／合併／公開發布完成。


## 2026-10-08 已驗收三票正式收尾

leadi 實測後明示「可以，暫時沒問題了，請你做好收尾合併后關單」，核可 LEA-134／194／208 正常 PR、最新 HEAD 驗證與獨立審查、符合既有平台條件的合併後關單。三票產品人驗 accepted；LEA-195 原 Done 保留，各票 owner 不變。範圍僅收尾已接受的發射／相機、玩家建築淡出、首發 FX 與 AI 選向同義成本修正，不新增玩法或調整物理參數。

新增 AI 同義 smoke 的同名 Godot UID 納入來源，並將該 smoke 加入既有 quality 清單；原 74 命令、ERROR／exit 掃描、workflow 與必要 checks 保持。escape handoff 不在現行 quality 清單，exact b9 與候選同失敗的 fixture 證據保留為診斷 backlog，不改 expected 或聲稱 PASS。完整最新 quality／review／PR／merge／main 結果以 [GitHub](https://github.com/leadingtw273/tank-skirmish) 真實同版紀錄為準；[LEA-134](https://linear.app/leadingtw273/issue/LEA-134)、[LEA-194](https://linear.app/leadingtw273/issue/LEA-194)、[LEA-208](https://linear.app/leadingtw273/issue/LEA-208) 的工程狀態、owner 與正式交付由 Linear 讀回。合併真成功後才關三票，不預填 CI 綠燈或已合併。新私素材 CI 仍須 exact PR／HEAD／run／attempt grant，舊 grant 不重用。


## 2026-10-08 LEA-209：主地圖空地草皮

leadi 要求「主要地圖的建築與道路間小空地，以及建築群外露出的地面都補上草地」，並選定「偏自然的灰綠草地（建議）」。本輪只作主圖平面不透明草底；[LEA-209](https://linear.app/leadingtw273/issue/LEA-209/主地圖建築道路間與街區外空地補草皮) 已建立 In Progress／未指派，歷史 117／122／140／177 原狀且無 blocking 依賴，人驗 pending。基線 `main 590c80177125bd8f86acc273954d5f3d4b1d9d2d`，隔離分支 `feat/main-world-ground-grass`。

封存 plan SHA-256 `23f12db1f907d7ec30f95bce28258f409c2a43678ac656c14eb0756f85c1220b` 的平台原生隔離第二模型審查 approve／0 blocker；Claude 外送被平台拒絕，沒有有效 Claude 結果或 source／素材外送。本機實作 GO 只含 GroundMaterial、自有世界 XZ 草皮 shader／必要 UID 與最小本輪文件；原地形／collision、道路／建築、玩法、正式相機／環境與必要平台 gate 保持。固定 F1–F3、兩個原 smoke、作者真原生 renderer 證據與 shutdown 限制見 [feature](../features/main-ground-grass.md)。

237 原 UID／586 ignored 素材 metadata、正式 M／其他 refs／工作樹／cache 保全；新增 shader UID 明列。最新候選待 fresh-context 同版 source／有限真圖驗收，之後才由 root 正常 guarded FF 本機交付，leadi 色調／畫面人驗仍 pending。完整 quality／新 CI／PR／push／正式 GitHub merge 尚未執行，不以本機作者證據或歷史 PASS 代替。


## 2026-10-08 LEA-209：BinbunGrass 草株續輪

leadi 指定使用既有 BinbunGrass，沿用自然灰綠配色與 LEA-209，人驗 pending。基線為已交付草底 `07249fea`；新隔離分支 `feat/lea209-binbun-grass`，正式 preview、main／origin/main 與其他作者來源保持。v2 plan SHA-256 `efebd118098b301b0aa838eda051d38025c66b271d59886cf3a248f001ec9209` 與有限校準附錄 `a61014a6da5b869e2172ab78f9fd07de051b6a2caf0ac537767f80d7a42ad343` 經平台原生第二模型 approve／0 blocker，root 明確 GO；沒有有效 Claude 外送結果。

最終只新增 GrassField 生成 script／UID、自有 Binbun material 與必要 scene refs；Quad 0.6×0.9m／center.y0.45、內格 jitter±1.4m／各軸首末±0.5m。來源 PNG／shader、草叢間低飽和灰綠色差、seed、候選上限與 1m 排除保持。作者最終 F1–F4 同鏡頭真原生 A/B 與兩原 smoke actual exit0，原 shutdown cleanup raw 保留；初輪圖未覆寫。實際參數、403320 株與有限證據入口見 [feature](../features/main-ground-grass.md#本輪-binbungrass-草株)。fresh-context 與正式本機同步由 root 後續執行；不代替 leadi 親測。

## 2026-10-09 LEA-209：demo 密草與風動

leadi 提供 MF5mbh／Z3QuLY demo 並要求主圖草地接近它，仍沿LEA-209與自然灰綠裁決；root封閉GO只含草株script／自有material及本feature／ITERATION／HANDOFF。計畫SHA-256 `d872296f3f79bfd31431ea526cadae9faedabd71a1310291d686b82c9ac7b314` 原生隔離review approve／0 blocker；沒有來源／素材外送或Claude／Gemini有效結果。Base為本機 `cc21ff8`，隔離W正常分支 `feat/lea209-grass-demo`；main／origin仍590c801，正式M與原未提交工作保持。

固定範圍是全floor底草與排除算法保持、相機附近32m／9×9／0.5m密草有界分批更新、原wind uniform與自有獨立noise；完整scope／初始化補齊取捨與有限AC見 [feature](../features/main-ground-grass.md#2026-10-09-demo-密草與風動續輪)。作者本機真Forward+圖／GIF、外區返回／inset／排除與有限frame成本、兩原smoke證據存N7；fixture D及舊renderer shutdown raw保留，最新actual結果依receipts讀回，非完整CI或gameplay benchmark。239原UID、586私素材hash／metadata／ignored與玩法逐檔保持；沒有scene／來源素材／碰撞／AI／透視／相機／光照調整。最新source待fresh-context有限工程驗收及root guarded FF至本機playtest；leadi F8/F5人驗pending，不push／改main／關單。
