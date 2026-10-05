# Tank Skirmish

套件來源版本：`0.1.0`。現役開發管理採 AgentCollab；本檔記專案事實，不新增產品開發授權。當輪管理切換見 [ITERATION.md](ITERATION.md)。

| 最少必要設定 | 內容 |
| --- | --- |
| 產品／用途 | Godot 固定斜俯視單人坦克遭遇戰；既有產品基準見下方。 |
| Repo | [leadingtw273/tank-skirmish](https://github.com/leadingtw273/tank-skirmish) |
| 共享進度（Linear） | [Tank Skirmish](https://linear.app/leadingtw273/project/tank-skirmish-c9ebe903bf08)（2026-10-05 `get_project` 實讀）；project ID：`56d2ff5e-1290-48bd-b17f-a8b78afe3dcf`，team ID：`b27abe8b-a6db-46f2-8b42-c47096908925`。工單、負責人、依賴、進度以 Linear 實際共享紀錄為準，開單前仍須重查同目標工作。 |
| 引擎／執行環境 | Godot `4.7.1-stable`、GDScript；`project.godot` 宣告 4.7／Forward Plus。quality 使用 Linux x86_64。 |
| 本輪 base branch | 已存在 `main`；本次只有管理文件 PR，目標 `main`。後續產品開發 base／輪次須由各輪實際授權決定，不自行新增或虛構 branch。 |
| 查核基線 | 2026-10-05 本機 `main`／HEAD `dd6e2fb00b5797363f1378fbcd04d4d26a00118f`／工作樹 clean；同日 GitHub main 回應同 SHA。開始正式 PR 前仍須重查。 |
| 必要平台條件 | strict required status：`quality`（GitHub Actions app 15368）及 `agent-team/review`；[現役 ruleset](https://github.com/leadingtw273/tank-skirmish/rules/20924509) 為 active、無 bypass actor。需 PR 且 review threads 必須 resolved；allowed merge methods 包含 merge／squash／rebase。 |
| 驗證命令 | `GODOT_BIN=/path/to/Godot_v4.7.1-stable_linux.x86_64 bash scripts/ci.sh`；實際執行 `node scripts/quality.mjs`。私有素材 CI 必須遵循 [既有 runbook](../local-private-ci.md)。 |
| 交付取得與執行入口 | GitHub merged `main` 的確切 commit；Godot 開啟 repo 的 `project.godot`，主場景 `res://src/main.tscn`。 |
| 本輪產品決策聯絡人 | leadi（當次互動對話）；不得虛構其他成員或多人 roles。 |
| 工作負責人／產品驗收人 | 各實際工單負責人以 Linear 為準；未取得前不推定其他人所有權。後續產品驗收由該輪指定，本輪不新增玩法驗收。 |

## 現役流程與保留邊界

先讀 [HANDOFF.md](HANDOFF.md)、[ITERATION.md](ITERATION.md) 與 [WORKFLOW.md](WORKFLOW.md)。每人與自己的互動代理協作，Linear 記工單／依賴／範圍／進度，GitHub 記版本／PR／CI／review／merge；沒有新的中央 Controller。

`agent-team/review` 是保留的 required context 名稱；切換後由 AgentCollab 的一次性 publisher 在核對同一 PR Head 的獨立 review 與證據後發布，不能依賴舊 Job／dispatcher。名稱相容不代表舊自動派工仍現役，也不能以 Markdown、評論或自我審查取代平台 status。publisher 可用性與本次 Head 成功 status 均要實際核對；尚未核對不得宣稱 gate 已滿足或 bypass。

`.agent-team/project.json` 保留作 legacy registration／來源證據，不是新管理流程的授權來源。驗證命令與安全要求保留，以 repo 實際版本、當輪授權及平台現況為準。

## 既有產品與素材基準（本輪不變更）

已提交 registration 記載 960m × 960m 多街區可玩地圖、中央城鎮與四個衛星街區、正交斜俯視跟隨鏡頭、可移動坦克、滑鼠砲塔／砲管、射擊／命中特效、建築碰撞、黃昏環境光、乾草與自適應視窗；這是來源文件的產品基準，不是本次實跑或人驗結果。README 的第一階段靜態場景敘述較舊，不能以它把既有玩法降回靜態場景。

保留既有 Quaternius／Binbun 素材、來源／授權／hash 與轉換紀錄、現有 smoke 與錯誤掃描；重用資產不重下載／轉檔，新增 addon／改 mesh／重繪貼圖／tint 需該輪明列。Iron Dawn 參考影格、截圖或描摹資料不得進 public repo。

[host-managed-settings.md](../host-managed-settings.md) 的受控設定仍需明確授權及可審查變更。本次例外僅涵蓋八個管理入口與必要管理說明，不授權修改 `project.godot`、workflow、素材、runner 或 legacy registration。

[local-private-ci.md](../local-private-ci.md) 保留 586 私有素材的逐次 exact PR／Head／run／attempt 授權、assignment 查核及清理合約。本次未讀取素材或執行引擎，舊 grant 不涵蓋本次或未來新版網路 CI；缺少新的必要授權時只暫停那段驗證，不能 skip `quality` 或用合成測試冒充完整 CI。視覺／操作驗收仍依實際場景與 leadi 判定，不採跨 GPU pixel diff。
