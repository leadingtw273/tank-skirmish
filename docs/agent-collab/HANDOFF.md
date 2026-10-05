# 一次接手入口

本檔下方的工程待完成欄位為 2026-10-05 導入候選準備時快照。接手時以 [GitHub 實際 PR／合併紀錄](https://github.com/leadingtw273/tank-skirmish/pulls?q=is%3Apr+Agent+Collab) 與 PROJECT 所列 Linear 的最新進度為準；不從這份快照重開已完成工作。
將下列 prompt 貼給新成員自己的 agent；不需安裝中央 Controller，也不需原實作者對話或相同模型。

```text
請依這個 repo 的真實共享檔案與平台紀錄接手我的工作：
1. 讀根 AGENTS.md、docs/agent-collab/PROJECT.md、
   docs/agent-collab/ITERATION.md、docs/agent-collab/WORKFLOW.md。
2. 依 PROJECT 的位置查 Linear、既有 PR、目前 branch／工作樹與版本；
   對帳本輪授權、我的工單、負責人、重複／重疊／依賴及交付現況。
3. 第一次讀完先回報簡短查核摘要：已知授權與我的工作範圍、
   相關工單／PR、衝突或依賴、未知資訊及下一個可執行動作。
4. 已核可範圍內自主續跑查核、拆單、開發、修正、獨立 review、
   符合平台條件的開發分支合併、Linear 更新及可重現交付；
   不為日常動作重複請核可，也不接管其他人的工單。
5. 只有產品方向、超出授權或無法協調的衝突才找 PROJECT 對應的人。
   未知資訊只暫停依賴它的部分，繼續其他已授權且可獨立進行的工作。
```

身份／本人負責工單：待設定（由接手成員填入）；未設定時先唯讀對帳，不推定工作所有權。

以 Linear 記錄進度與範圍；工單內容參考 `docs/agent-collab/ISSUE.md`，獨立 review 參考 `docs/agent-collab/REVIEW.md`，PR 參考 `.github/PULL_REQUEST_TEMPLATE.md`。工程交付版本與人員產品驗收分開；交付要有版本取得方式和可重現步驟。

## 導入候選查核快照與接手步驟

本 repo 管理切換已核可，見 [ITERATION.md](ITERATION.md) 的原句、日期與來源摘要。2026-10-05 唯讀查核：本機 `main`／HEAD `dd6e2fb00b5797363f1378fbcd04d4d26a00118f`／clean，遠端 main 同 SHA；open PR 回應空清單、全部狀態的「Agent Collab」PR 關鍵字搜尋 0 筆。這只證明查核時的已讀共享範圍，不能排除其他人的未提交修改或後來新 PR。Linear 已實讀 [本專案](https://linear.app/leadingtw273/project/tank-skirmish-c9ebe903bf08)；同 team 含封存項目的 `Agent Collab`／`Agent Team`／`管理切換` 搜尋各回 96／97／125 筆、皆 `hasNextPage=false`，去重 161 筆。標題同採用目標的 [LEA-179](https://linear.app/leadingtw273/issue/LEA-179/接入-agent-collab保存-132-成果基線並準備協作文件-pr) 是已完成的 Spellbound 首案；實讀 [LEA-124](https://linear.app/leadingtw273/issue/LEA-124/更新過期的-agent-team-專案規則) 為已完成的 Tank 舊 config 規則更新，[LEA-42](https://linear.app/leadingtw273/issue/LEA-42/tank-skirmish-registration-audit)／[LEA-9](https://linear.app/leadingtw273/issue/LEA-9/agent-team-sandbox-registration-audit) 為 registration 稽核，皆不接管或重開為本次全面切換。上述已讀範圍未發現 Tank／Sandbox 本次管理切換同目標工單；搜尋結果並非 0，也不能排除其他命名、未讀描述、他人未提交內容或查核後的新工作，正式開單前重查。

下一步依序為重新核對 repo／平台 → 查 Linear 與同目標 PR／責任人 → 沿用或建立管理文件工單 → 在隔離文件 branch 提 PR 至 `main` → 最新 Head 獨立 review → 實際必要 CI 與相容 `agent-team/review` status → 核對真實平台條件 → 普通 merge → 回填交付 commit／Linear。Branch 名稱由真實建立結果記錄，目前未建立；不得推定舊 Job 或其他人的工作已被接管。

候選準備時工程交付待 review／CI／merge；沒有正式 PR、review PASS、CI success 或交付 commit。Tank 既有遊戲成果保留，本次未讀私有素材、未跑 Godot、未重測玩法；私有品質驗證另依 [runbook](../local-private-ci.md) 取得本次必要的精確授權。 Spellbound 已採用的入口與既有工作不覆蓋、不重開；其他未具 Team registration 的專案依全域 fallback 讀各自 repo 入口，不因本輪新增輪次。
