# 一次接手入口

目前核可輪次是 2026-10-05 玩家遮蔽淡出與敵車透視輪廓，權威為 [ITERATION.md](ITERATION.md)；自包含產品裁決、ADR、P1–P3／E1–E3、術語與有限測試入口見 [tank-occlusion.md](../features/tank-occlusion.md)。工程狀態：玩家 phase1 實作中；Claude plan review 已執行（提醒已裁決採納）；正式 Forward+ probe／新功能驗收／PR／CI 待完成。 人員產品驗收：`pending`，未宣稱 accepted。

上一管理輪已由 [PR #125](https://github.com/leadingtw273/tank-skirmish/pull/125) 合併至 `main`，commit `b9fe1f4a93d4e4c2b48a3ed3a866d660980f8aa7`；不要重開舊管理待辦。本輪以此為基線，先 [LEA-194](https://linear.app/leadingtw273/issue/LEA-194) 玩家局部建築淡出、P1–P3 本機驗證與 fresh-context 驗收，再 [LEA-195](https://linear.app/leadingtw273/issue/LEA-195) 敵車紅線輪廓與透視瞄準；後單依賴前單。

將下列 prompt 貼給新成員自己的 agent；不需中央 Controller、原實作者對話或個人記憶。

```text
請依這個 repo 的真實共享檔案與平台紀錄接手我的工作：
1. 讀根 AGENTS.md、docs/agent-collab/PROJECT.md、ITERATION.md、WORKFLOW.md，
   再讀 docs/features/tank-occlusion.md 的產品裁決與有限 AC。
2. 依 PROJECT 查 Linear、既有 PR、目前 branch／工作樹與版本；
   本輪 base 與目標分支以 ITERATION 為準，PROJECT 管理輪快照保留為歷史。
   對帳授權、我的工單、責任人、重複／重疊／依賴與交付現況。
3. 第一次讀完先回報簡短摘要：授權與範圍、相關工單／PR、
   衝突或依賴、未知資訊及下一個可執行動作。
4. 已核可範圍內自主續跑查核、開發、正常修正、驗證、獨立 review、
   符合真實平台條件的開發分支普通合併、Linear 更新及可重現交付；
   不為日常動作重複請核可，也不接管其他人的工單。
5. 只有產品方向、超出授權或無法協調的衝突才找 PROJECT 對應的人。
   未知資訊只暫停依賴部分，繼續其他已授權且可獨立進行的工作。
```

身份／本人負責工單：待設定（由接手成員填入）；未設定時先唯讀對帳，不推定所有權。工單、負責人、依賴與共享進度以 Linear 最新紀錄為準；PR、Head、CI、review 與 merge 以 GitHub 最新紀錄為準。兩單建立後 read-back 為待執行、未指定責任人；接手須重查，不以快照排除後續改動或他人的未提交內容。

## 接手順序與保留邊界

Claude review 提醒已裁決採納：保留 `cull_disabled`、敵車專屬拾取略過非目標 RID、4.7 實測前提；輪廓命中包含紅線圍住的實體車體 silhouette 投影形狀與線寬鄰域，不使用 AABB。正式 Forward+ probe 及產品驗收仍待完成，不能把前提查核當功能通過。

依本輪固定順序完成玩家、再敵方。只有既定 AC 反例、正常路徑實際失敗或具體資安／資料破壞證據列為本單 blocker；其他 advisory 為後續 backlog／忽略，不改寫完成定義。三個產品術語已記入共通術語，產品未實作完成；完整定義在產品文件。

正式 `main` 主圖沒有敵方 Encounter，本輪不植入敵方戰鬥布局；敵方驗證限現役訓練場與有限測試場景。沿用 `TankVision.can_see` 與實體遮彈，視野外敵車沿用原顯示，不新增迷霧或發現記憶。

工單參考 [ISSUE.md](ISSUE.md)，獨立 review 參考 [REVIEW.md](REVIEW.md)，PR 使用 [PR 範本](../../.github/PULL_REQUEST_TEMPLATE.md)。交付須有實際 PR／commit、可重現取得與試玩入口、已驗項目與限制；工程驗證、獨立 review、平台 gate 與 leadi 親測分開記錄，不把準備文件、probe 或 CI 綠燈寫成人員 accepted。

保留 [PROJECT.md](PROJECT.md) 的環境／平台設定、[WORKFLOW.md](WORKFLOW.md) 的同 Head 獨立 review／必要 CI／普通 merge 規則、required `quality` 與 `agent-team/review` 及 protected settings。不跳過 gate、不降低 checks、不用 bypass；未知權限只暫停依賴部分。舊 Team registration／Job 只作歷史相容資料，不是派工入口。

安全與 CI 權威仍是 [host-managed-settings.md](../host-managed-settings.md) 及 [local-private-ci.md](../local-private-ci.md)。沒有擴大私素材、憑證、私有路徑或截圖外送權限；新網路私素材 CI 在封存 Head 後列該 PR／Head／run／attempt 的具體授權包，舊 grant 不泛延長。管理切換與本輪開發授權均不等於公開發布、商店發行或破壞性操作授權。
