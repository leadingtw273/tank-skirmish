# 專案 Agent 入口

先讀 `docs/agent-collab/HANDOFF.md`；專案設定在 `docs/agent-collab/PROJECT.md`，本輪範圍、AC 與可查證單輪授權在 `docs/agent-collab/ITERATION.md`，共同規則正文在 `docs/agent-collab/WORKFLOW.md`。

首次接手先讀共享狀態並回報查核摘要。開單前查 Linear 與既有 PR，重複沿用、重疊協調、依賴排序；不接管他人工單。Linear 是共享工單、進度與範圍的事實來源，不另建平行事實表。

已核可整輪範圍內自主執行拆單、開發、修正、驗證、獨立 review、符合真實平台條件的開發分支合併與交付，不重複請日常核可。只有改產品方向、擴 scope 或無法協調的衝突找專案對應的人；未知資料只暫停依賴部分。

工單與驗收內容參考 `docs/agent-collab/ISSUE.md`。Review 使用 `docs/agent-collab/REVIEW.md`：另一模型隔離 reviewer 優先，同模型 fresh-context 為替代；無隔離能力請其他成員，不假造獨立。最新 Head 改動後重審；PR 用 `.github/PULL_REQUEST_TEMPLATE.md` 記錄實際驗證、reviewed Head、CI Head 與真實合併條件。

工程交付與人員產品驗收分開；交付附版本和可重現入口。開發分支合併不授權公開發布或商店發行。各成員可使用自己的工具與模型，不強制中央 Controller；repo 內規則版本才是本項目依據。

本 repo 的本輪管理切換已核可；[ITERATION.md](docs/agent-collab/ITERATION.md) 定義文件 PR 至既有 `main` 的授權。保留既有 protected settings／必要 CI 與 required `agent-team/review`；舊 Agent Team registration／識別字保留作歷史證據，現役流程不依賴舊 Job／背景自動派工。
