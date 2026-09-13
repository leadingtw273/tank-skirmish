# 復盤後封閉修正與下一次實測

> 歷史執行 packet：其中兩次額度等當時限制已由後續 `recovery-episode-plan.md` 取代；現行行為以 `enemy-movement.md` 為準。

2026-09-13 使用者核可復盤建議並要求繼續至下一次實測。本 packet 是熔斷後的新執行邊界，不抹除既有失敗紀錄。

## 前提與裁決

使用者、Windows 單人訓練場、遊戲產品定位與 NavMesh＋專用駕駛動機未變。保留架構、局部重整；不重寫或回退使用者街區。依 `/tmp/driving-retrospective-review.md`：F1/F2/F4 是 blocker；F3 是必須對齊的既有模擬合約，不能宣稱已證實事故；F5 是測試觀測與未驗狀態；F6 非必要 API 清理轉 backlog。

## 範圍

Production 限 `src/ai/tank_navigation.gd`、`tank_recovery.gd`、`tank_driving_predictor.gd`。可補這些合約的有限測試與本次驗證文件；不改 CombatAI、Controller、recorder、scene/tres/assets、車型速度、碰撞精度及查詢預算。不新增全域姿態尋路、直通捷徑、砲塔接管、未來瞄準預測。

Threat model：可信本機、既有車型／平面街區、完整當前碰撞形狀。Non-goals：任意坡地／多人、所有路況完備解、外部攻擊者與當機恢復。舊工作樹 dirty 資料屬使用者／既有工作，不覆蓋。

## 階段責任與鎖定合約

| 階段 | 操作與轉移擁有者 | 完整形狀預測 gate | 成功／失敗 |
|---|---|---|---|
| normal drive | Navigation 共用 nominal 計算 | 原 choose，3 秒 | 原 arrived/partial/no-path 語意 |
| normal hold | CombatAI 意圖、Navigation | 原 choose，3 秒 | 保留原面敵／停止語意 |
| braking/reversing/settling | Recovery | 恢復既有 choose_recovery，3 秒 | 無可用命令輸出零，期限仍走 |
| selection | Recovery 候選、Predictor 模擬 | 單 snapshot 全動作，最多 10 秒 | 完整停穩且正向前移 >=0.5m 才合格 |
| turning/align/advance/escape settle | Recovery 共用純 phase transition | 固定 heading 的 3 秒 continuation | 窗內安全不要求整套完成；unsafe/budget 零輸出 |
| rejoining drive | Navigation 共用原 nominal、Recovery 保有控制 | nominal-only 3 秒 | 安全原地 turn 持續執行，不耗新 attempt；安全正向 movement 才 handoff |
| rejoining hold | Navigation 當前 hold 意圖 | nominal-only 3 秒 | 安全面敵且停止後 handoff，不強迫追擊 |
| terminal/cancel/death/replace | 既有生命週期 | 停車與 Controller 物理保底 | terminal 保留診斷；full clear 重置 |

1. 共用正常 nominal：將正常 drive 既有角度、車型速度、路徑剩餘長度、stop distance、折角與煞車計算抽為單一純計算。normal 與 rejoin 使用相同輸入語意；刪除 rejoin 固定 `.5`。真實 route refresh/next point 仍由 Navigation 擁有，不在 preview 推進 agent。
2. 模擬／真車共用純 transition：輸入 phase、elapsed、attempt elapsed、速度、角速、heading、真前移進度與 delta，輸出下一 phase／elapsed／command／成功或失敗。未來模擬不得改真 Recovery，不能只把 elapsed 放 trace。保留 turning 7 秒、advancing 2.5 秒、attempt 16 秒、rejoin 3 秒，所有 deadline 每真 physics frame 一次。
3. 預測時遇預期 deadline，必須按同一規則轉為停止／失敗，而非繼續原動作；selection 必須確實完成，continuation 可在其窗內模擬停止，但不得把預測成功當真 handoff。
4. 固定左右 30/60 候選、兩次額度、全形狀、4096 queries／20 ms／12 candidates 不變。保留既有 `choose_recovery()` 支援倒車階段；不順手刪 API。
5. trace 保留 `recovery` 公開合約與 handoff_count/reason/frame；預測和真實 phase／advance 明確區別。Recorder 不改。

## 固定驗收矩陣

- R1：既有 H1，記錄 Tank2＋使用者街區＋正常瞄準，實際 turn>3°、正向前移>=0.5m、安全 nominal handoff，後續 600 個 60 Hz physics frames 不回原卡點0.5m或terminal；不是確定性 replay。
- R2：H2 修正後 gun-only 左右鏡像；全動作前移有 gun blocker 則拒絕；3秒 continuation 窗安全但未完成可執行；固定 heading 不偷換。
- R3：H3 全blocked／unsafe rejoin 兩次有期限停車、lifecycle。另有限檢查 braking/reverse/settling 都實際進 predictor，normal/rejoin 使用同 nominal，接近 phase deadline 的模擬與真車 transition 相同。
- R4：原 movement/navigation/predictive/contact/last_seen 回歸；使用專用 validation 舊地圖基線時只同步本次3 production檔及必要新測試，不覆蓋地圖。舊 immediate-normal recovery 斷言若與已核可語意衝突，保留失敗再精確更新，不刪安全／額度斷言。
- R5：scene/nav SHA 與原值一致、F4 trace新增資訊可見、Windows 正常載入及 F6 可試玩。既有 renderer 退出問題另列，不偽稱 clean stderr。

## 執行與升級

前次次階實作多次漏合約，這次採決策層實作者做受限跨檔整合；以獨立 fresh-context 代理驗收。先 read-back，主代理仍持有 scope 裁決。不得換數值／減安全／改 fixture 姿態洗綠；若需要 scope 外能力或改使用者可見規則，先停止提出證據。同一產品義務的失敗歷史持續保留，不因新檔名歸零。

既有資料：`/tmp/escape-handoff-repro-final.log`、`/tmp/escape-handoff-h23-final.log`、`docs/escape-handoff-verification.md`。Linux 引擎使用工具鏈快取中的 Godot 4.7.1-stable，以隔離 XDG、`--headless --fixed-fps 60 --path <worktree> -s res://tests/<test>.gd` 執行。單一引擎 lease，保留各次 log，RC 與 SCRIPT ERROR 同查。R1–R5 通過前不得宣稱可交付。
