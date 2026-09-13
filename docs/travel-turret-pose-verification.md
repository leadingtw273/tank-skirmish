# 追擊砲塔回正驗證

## 本次範圍

僅修改 CombatAI 武器姿態策略與 Navigation 唯讀 terminal 查詢。失去視野且尚有追擊／脫困意圖時，砲塔水平朝目前車頭逐步回正；保留俯仰、最後位置記憶及原碰撞保護。可見、受擊查看、抵達及 terminal 沿用原策略。本幀 drive 首次產生 terminal，下一物理幀才切回觀察。

## 原始問題與測試邊界

最新使用者 F4 session：`2026-09-13T01-02-03-309062`，以 frame 2768 記錄姿態建立真 Tank2／現有街區的有限 30 秒 fixture。這是記錄姿態重建，不是玩家完整輸入的確定性重播。

舊碼紅測：初始相對 yaw 75.71°，前 180 個追擊意圖幀最低 72.56°，未達 ≤45°。完整診斷：`/tmp/latest-f4-aim-diagnosis.md`。

第一版測試誤要求 30 秒結束仍保留原始最後位置，忽略正常重新可見更新與停用清理。已改為追擊期間逐幀記憶／導航目標不被虛擬瞄點覆寫，重新可見時以 Vision 真實目標位置更新預期值；保留原回正門檻、30 秒足跡及非空檢查。未為迎合測試更改生命、傷害或場景。

## 凍結檔案

- CombatAI：`53961ca3fceba752e56963e99b2ae3ff269308707d524d140a0ed4358401935d`
- Navigation：`46b0855cadb20b4c27a40a454415e9a7dadec73653d216a6bb5a291ccf135163`
- Recovery 未變：`e775231223be0f86d4a719696a30e6033337ee894bd9c260013ca3bcf2663f69`
- Predictor 未變：`badf8374f853b2bffa0112612b9dd9ccfbf7b9ef7f4f77b99969760fc21949c0`
- Controller 未變：`cd5a0fd25a86ad31f9c25c1ac6cd40fa38200c300c339c2fe8dc60e8aa7a83e8`
- 使用者街區未變：`8df361c61678290464cbfebb00ffd6353af52291421ea8d7d958590d688be3be`
- NavMesh 未變：`7db3c844566f374b65efe6fdfab844bf5e28bbb17cf221845e8326096a7f877f`

## 驗證狀態

Linux 獨立重跑 T1 通過（`/tmp/travel-acceptance-logs/t1-repro.log`）：相對 yaw 74.75° → 0°，180 個初段追擊意圖幀，791 個記憶檢查幀；30 秒內最大位移 16.673m、1 次 handoff。這是有限場景結果，不代表所有卡住都能解除。

T2/T3 補齊後初次執行遇測試型別推斷錯誤；修正測試型別後 RC 0，無 SCRIPT ERROR／ERROR／FAIL（`/tmp/travel-policy-fixed.log`）：

- 零速追擊與相對車頭回正成立，terminal 下一幀切回 last_seen。
- 真 Tank2 無牆：yaw 0.900 → 0.000，無 shape overlap。
- 真 Tank2 有牆：guard blocked=true，yaw 限於 0.546，無 shape overlap。
- 兩案砲管 pitch 維持 -0.190。

T2/T3 亦經未參與實作的代理獨立重跑通過。last_seen、predictive、escape、enemy_movement 獨立回歸通過。

enemy_combat 仍有既存紅燈：新版兩次 RC 1；精確重建舊 AI `cf09708f0780e0f5151212c1f763f1857e1b938cbccb5b694d56fb6c9537ceb0` 與 Navigation `7467acd7c8d17b76148adad90618d0bba6bed5feb006714d9471b11e2c45d133` 後，同一測試亦 RC 1，皆為 `A clear vision result with a blocked muzzle ray must not fire`。判定非本次引入，但原因未修復，不宣稱全套回歸全綠。對照後 validation 已還原新版兩檔 hash。

獨立驗收報告：`/tmp/travel-pose-acceptance.md`；各案 log：`/tmp/travel-acceptance-logs/`。驗收者以獨立 context 起始，只接合約與產物，未參與程式撰寫；同一代理先做合約 review，並非驗收時再建的新 thread，也不是跨供應商 review。

## Windows 試玩交付

- 正常訓練場：自啟 PID 40248，遊戲 RC 0，log `/tmp/travel-pose-windows-20260913-094217.{out,err}.log`。
- F4：自啟 PID 51264，frame 123 收到標記，之後 120 個物理幀持續運行，遊戲 RC 0、`TRACE_ROTATION_WINDOWS PASS`。log `/tmp/trace-rotation-windows-20260913-014244.{out,err}.log`。
- F4 session `2026-09-13T01-42-49-316172` 的 header 核對新版 AI／Navigation hash 一致、場景及其他控制元件 hash 未變；新 `weapon_pose_mode` 欄位已實際寫入記錄。
- 兩個 Windows 測試仍有已知退出時 Texture RID／RenderingServer 警告；F4 harness 因偵測 stderr ERROR 回 RC 1，不能描述為乾淨退出。此次未出現 WASAPI 錯誤，未改音效設定。
- 保留原 Windows 編輯器 PID 43240 與使用者街區，未關閉、重開或覆寫未儲存場景。可從既有編輯器 F6 重啟試玩，異常時按 F4。

本次回正策略已具備下一次人工試玩條件；不保證所有砲管／車體卡牆皆能解除，既存射擊測試紅燈另列未解事項。
