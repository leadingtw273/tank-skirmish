# 車身脫困候選：試玩驗證

## 本次調整

只修改 `tank_driving_predictor.gd` 與 `tank_navigation.gd` 的脫困命令選擇。原命令安全即保留，受阻才於共享限額內尋找低速替代；原停車命令不會被替換成移動。未新增砲塔／俯仰接管，未改索敵、射擊、導航半徑或使用者街區。

## 實測證據

- 修正前：`/tmp/body-recovery-pose-red.log`，RC 1；兩個記錄姿態重現 gun/#14 阻擋，缺少新的 recovery API。
- 實作者測試：`/tmp/body-recovery-pose-test-report.md`，RC 0。
- Fresh-context 驗收：`/tmp/body-recovery-acceptance.md`，無 A/B blocker。
- `body_recovery_pose_smoke.gd` 獨立實跑 RC 0：120 個真實 physics frame，倒車案例位移 0.507 m／轉角 9.07°；原地轉向案例轉角 4.16°。Navigation 真脫困入口整合位移 0.507 m。
- `driving_trace_v2_smoke.gd` 獨立實跑 RC 0，3 cases PASS；兩項均無 ERROR／SCRIPT ERROR／FAIL。
- 原基線場景五項回歸 RC 0：`enemy_recovery_smoke`、`enemy_movement_smoke`、`enemy_navigation_smoke`、`enemy_predictive_driving_smoke`、`tank_contact_response_smoke`。測試未改弱；詳見 `/tmp/body-recovery-regression.md`。
- 使用者街區 scene SHA-256 前後均為 `8df361c61678290464cbfebb00ffd6353af52291421ea8d7d958590d688be3be`；導航資源均為 `7db3c844566f374b65efe6fdfab844bf5e28bbb17cf221845e8326096a7f877f`。
- Windows 自動按鍵 harness RC 4（`LOG_NOT_READY`），不可宣稱該腳本 PASS 或本次 Windows F4 已實測。原編輯器 PID 43240 保留。新紀錄 `driving-2026-09-12T12-39-41-201545-000.jsonl` 經獨立核對：predictor／navigation 雜湊與新版完全相等、2897 筆 frame 約 48 秒、`session_end reason=stopped`。這證明 Windows 新版載入及正常結束，不代表已在 Windows 自動操作到 recovery 分支；完整路線行為交使用者試玩。

## 範圍與限制

上述結果證明這兩個姿態可透過新選擇器取得安全的短程實際進展，不保證所有建築群都能完全脫困，也不是原始事件的確定性重播。砲塔與砲管仍以當下完整姿態納入每次預測，沒有關閉碰撞或縮短 3 秒視窗。外部跨供應商複審先前遭拒，這次使用原生 fresh-context 驗收。

## 試玩方式

在既有 Windows 編輯器的 `training_ground_playtest` 場景按 F6；使用 Tank2，沿牆引導敵車後從另一側繞出。觀察受阻後是否嘗試低速倒車搭配側轉，而不只反覆直退。若仍卡住，當下按 F4 標記紀錄；不要用 F9，以免觸發編輯器暫停。
