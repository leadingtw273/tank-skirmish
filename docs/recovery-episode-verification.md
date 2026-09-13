# 每次卡住事件三次機會：驗證

## 核可行為

每次獨立卡住事件最多三次。handoff 不立即補滿；恢復 normal 正向追擊且無接觸／預測介入，連續 3 秒並實際水平位移至少 0.5m，才結束事件。重算路線、可見／失視、generation、holding 及未確認恢復時的非 stuck 終態不補額度。三次耗盡鎖定停車當下目標，目標水平移動至少 3m 才重試。真正换目標、停用、死亡及換車完整清理。

## 範圍與版本

僅 CombatAI／Navigation／Recovery、事件測試與核可的兩次改三次舊測試更新；Controller、Predictor、街區與 NavMesh hash 未變。

- CombatAI `ce2939d633c7e05587a6222122d484c8ba154181d3da7e6e1d6433f8d19fbfca`
- Navigation `9cd5e6d32c5e1ea0730c0966b3358c6868fb05e2ac43aebedbc11f7ce1ecf086`
- Recovery `1b33a45cb10f06b32ecb5de138d0022e9db8a193616050b14ab7d6a68115481b`

before 副本：`/tmp/recovery-episode-before/`。實作報告：`/tmp/recovery-episode-impl.md`。

## 證據與限制

- 舊碼真紅：第三次機會不可用，`/tmp/recovery-episode-logs/baseline-recovery_episode.*`。新版事件 smoke 通過。
- 獨立檢查曾抓到 `_finish(non-stuck)` 清事件，已修為保留未完成事件並補三種終態測試。
- E4/E5 使用真 CombatAI／Navigation／Vision 與物理遮牆測試生命周期和 hidden 記憶；terminal 起始狀態一次初始化，不宣稱完整碰撞重播。新 lifecycle smoke 通過。
- 獨立回歸八案 RC 0：episode、lifecycle、travel、reintegration、escape、last_seen、predictive、enemy_recovery。詳細 log 與退出碼：`/tmp/recovery-episode-acceptance-logs/`。
- enemy_movement A9 初次在原 1800-frame 視窗結束時仍在第三次 recovering。依核可新增一個 16 秒嘗試額度，把視窗加至 2760 frames；恰三次真倒車、stuck、零命令與持續停車斷言全部保留，原始失敗 log 未覆寫。

最終 A9 獨立重跑 RC 0：`attempts=3 actual_reverse=true final_status=stuck`，零命令及 5 秒持續停車斷言均保留並通過。九案 E1–E6 全通過，原八案使用相同 frozen production hash；詳細独立報告 `/tmp/recovery-episode-acceptance.md`。驗收代理未參與本次實作或測試撰寫，但沿用先前任務的代理 context，並非本次新建 fresh thread；也不是跨供應商 review。

## Windows

- 正常場景：PID 44428，遊戲 RC 0；`/tmp/travel-pose-windows-20260913-122309.{out,err}.log`。
- F4：PID 7160，frame 119 收到標記，之後持續 120 個 physics frames，遊戲 RC 0、`TRACE_ROTATION_WINDOWS PASS`。
- F4 session `2026-09-13T04-24-12-194473`，header 核對本文件三個新版 AI hashes；trace 已包含事件／確認進度／停車鎖定目標。
- F4 log `/tmp/trace-rotation-windows-20260913-042407.{out,err}.log`。兩案仍有既有 Texture RID／RenderingServer 退出錯誤；F4 wrapper 因 stderr ERROR 回 RC 1，不宣稱乾淨退出。沒有修改 renderer。
- 保留使用者編輯器與街區。可 F6 重新試玩，異常時 F4 記錄。

本次已具備下一次人工試玩條件。既存 enemy_combat 砲口遮擋紅燈不在本次修復範圍，未以本次九案通過宣稱全套測試全綠。
