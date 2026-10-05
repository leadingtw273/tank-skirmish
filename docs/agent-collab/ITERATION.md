# 2026-10-05 管理流程切換

狀態：`approved`（本輪管理範圍已核可）；工程狀態：文件候選已準備，正式 PR／review／CI／merge 待執行。

| 本輪定義 | 內容 |
| --- | --- |
| 目標／動機 | 將現役開發管理全面導向 AgentCollab，由每位成員的互動代理主導，退役舊自動接單／派工。 |
| 本 repo 範圍 | 導入八個協作入口，調整必要的 README／host-managed-settings 管理指引；保留 Linear／GitHub 工單、PR、CI 與真實 merge gate。以文件 PR 普通合併至 `main`。 |
| 明確排除 | 不新增遊戲／產品功能、不重開已完成產品工作、不變更 CI／source／素材／package／CLI／legacy registration、不創造新產品開發 branch、不對外發布。不把文件採用視為舊服務已停或完整多人工程閉環已驗。 |
| AC-1 | 根 AGENTS、docs/agent-collab 六文件及 PR 範本皆可讀，無未展開 kit 替換符；相對文件連結有效。 |
| AC-2 | PROJECT 只填來源可驗事實；未知 Linear URL／所有權明示，不虛構角色、工作狀態或人驗。 |
| AC-3 | 已核可單輪範圍內自主續行，不逐 Task 重問；開單／PR 前查重、依賴與重疊，不能查不到就宣稱無衝突。 |
| AC-4 | 保留 `quality`（GitHub Actions app 15368）及 `agent-team/review` 與其餘真實平台 gate；獨立 reviewed_head 與必要 checks 均須對應最新 Head 才能普通 merge。 |
| AC-5 | 既有產品／安全限制／資料／歷史證據保留；未執行的 review、CI、遊戲 QA、人員產品驗收如實記未完成。 |
| Base／交付方式 | 既有 `main`，來源基線 `dd6e2fb00b5797363f1378fbcd04d4d26a00118f`；透過獨立文件 PR、最新 Head 獨立 review、同 Head 必要 CI／status 與平台 read-back 後普通 merge，記錄實際交付 commit。 |
| 核可人／日期 | leadi，2026-10-05。下方為本輪可讀授權摘錄與來源 digest。 |
| 聯絡人／責任 | leadi 為本輪產品決策聯絡人；實際工單負責人查 Linear，不自行接管他人。 |
| 人員產品驗收 | 本輪不改玩法／UI，未重測產品；管理文件工程交付與產品驗收分開，不假造 accepted。 |

## 可查證授權摘錄

2026-10-05，leadi 的原始目標：

> 將當前開發管理方式全面導向 Agent Collab 而不是 agent team

同日釐清答覆：

> 互動代理主導，退役舊自動派工

平台保留邊界為「保留 Linear／GitHub 工單、PR 與 CI」。來源記錄為當次對話保存的 `user-scope-decision.json`，capturedUTC `2026-10-05T02:53:09.299170+00:00`，SHA-256 `843b989b69e187a53fdd0c4faae25081d62226dc2e05a287530a75f60d8e9c2f`。本檔保留自包含可讀摘錄，不要求接手者存取原使用者個人 home／記憶或對話歷史；這份摘錄只授權管理切換，不是新遊戲輪次。

本次執行邊界已確認為文件 PR → `main` 普通合併；沒有新產品開發 base branch。本輪內查核、拆單、文件修正、驗證、獨立 review 與滿足真實平台條件後合併／交付可自主續行，不重複請日常核可。未知權限只暫停依賴部分；擴 scope、改產品方向或無法協調衝突才升回對應的人。

## 工程與人員結果

| 結果 | 實際狀態 |
| --- | --- |
| 文件候選／本機結構查核 | 已準備；本機 read-back 證據由本次交付附上。 |
| GitHub PR／交付 commit | 尚未建立／尚未合併，不能填舊產品 PR 為本輪交付。 |
| 最新 Head 獨立 review | 尚未執行；實作者檢查不算獨立 review。 |
| 同 Head 必要 CI／review status | 尚未執行；平台名稱保留不代表已 success。 |
| 普通 merge／Linear 交付更新 | 尚未執行。 |
| 遊戲／產品 QA 與人員 accepted | 本輪未重測、未宣稱 accepted。 |
