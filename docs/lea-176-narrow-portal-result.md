# LEA-176：F4 下方窄口反覆進出修正

## 人工驗收（2026-09-23）

使用者明確確認：「可以，當前驗收敵方坦克會正確過宅口追擊」。本次訓練場下方窄口的穿越與追擊行為人工驗收通過；不據此擴大為所有場景或整張 LEA-176 結案。

## 使用者反例與根因

使用者在訓練場建築旁探頭被發現後退回隱蔽，Tank2 嘗試下方窄口、退出再進。F4 session `2026-09-23T10-20-21-246845` 的五段 trace 已保全至 `/tmp/lea176-gap-loop-user-trace/`，manifest 核對來源／副本 SHA 5/5 相同。

首次全候選 blocked 是 frame 4010；4380 到窄口 index 8，4433／4513 持續 blocked，4555 開始 recovery；後續再次進入同一路徑，6512 terminal stuck。F4 marker 在 8933、8995，保留鏈包含先前失敗。原有 gap smoke 是 Tank1、只要求前進與無碰撞，不能代表本次 Tank2 到達。

平地制動預測把每個部位的整條路徑合併成世界座標 AABB；坦克旋轉後，AABB 的空角會罩住 NorthGable，將實際可通過的動作否決。以本次 frame-4380 姿態及量測速度建立的診斷路徑，舊 AABB 拒絕、新定向包絡證明分離、密集真實 30 個 convex 查詢無建築碰撞。Trace 未記錄完整 pending force／Intent／物理解算器狀態，因此這是觀測初態重現，不宣稱逐幀決定性重播。

## 修正與安全不變量

僅修改 `src/ai/rigid_braking_sweep.gd`：保留 world AABB 廣相檢查，遇到高靜態 Box 相交時，再以起點車身座標累積所有預測姿態的部位包絡，透過三維 SAT 分離證明排除空角誤判。必須所有部位都證明分離；不是將一次碰撞查詢失敗視為安全。

完整制動路徑、相鄰姿態旋轉弧線、`0.01 + 0.08 * max_vertex_speed + tail`、原本兩層 MARGIN 與時間／查詢上限都保留。SAT 只接受靜止正交 Box，非均勻縮放保留在投影支撐半徑；每次查詢重新建立包絡。未知支撐、動態障礙、同 RID 的不同 shape 與原 terrain/recovery 行為維持。未改 navmesh、路徑狀態機、玩家物理或車型資源。

新增兩個 regression：`rigid_training_narrow_portal_smoke.gd` 要求 Tank2 從 approach／stalled-turn 兩個觀測位置真正穿口並到 last-seen 3m 內，且逐 tick 查完整形狀不得與建築重疊；`rigid_braking_oriented_sweep_smoke.gd` 驗舊世界 AABB 誤擋，以及兩端 clear、旋轉中段 gun 真碰撞的負例。

## 最終驗收

Linux／Windows Godot 4.7.1 均循序通過 9 項：新窄口、新定向包絡、40 案制動、原 braking sweep、curb boundary、recovery、24 案 terrain、可見戰鬥雙姿態與開闊追擊。Windows 使用實體隔離副本；第一次 symlink 樹啟動失敗屬環境問題，原 log 保留，未計入 PASS。功能矩陣使用 `--fixed-fps 60`，效能與追擊使用即時 headless。這些自動測試不量測 GPU 幀率；後續人工穿口追擊驗收另見上方紀錄。

### 窄口紅綠對照

同一 60 秒觀察窗，舊版兩案分別在 3157／2042 tick terminal stuck，都未穿口（`/tmp/lea176-gap-loop-narrow-before-60s.log`）。新版結果：

Linux：
```text
NARROW_PORTAL case=approach status=arrived frames=1440 crossed=true distance=2.756 building_overlap=false position=(76.17066, 0.009722, -13.17488)
NARROW_PORTAL case=stalled-turn status=arrived frames=3048 crossed=true distance=1.893 building_overlap=false position=(77.12754, 0.008665, -12.50465)
```

Windows：
```text
NARROW_PORTAL case=approach status=arrived frames=1398 crossed=true distance=2.873 building_overlap=false position=(76.21401, 0.009021, -13.31626)
NARROW_PORTAL case=stalled-turn status=arrived frames=1687 crossed=true distance=2.055 building_overlap=false position=(76.92858, 0.009102, -12.65136)
```

初次新 smoke 採 40 秒窗口，一案已穿口但仍距目標 4.727m，照實記 FAIL；延長診斷後可到達，正式矩陣統一 60 秒並重跑相同窗口的舊版對照。沒有刪除到達／距離／不碰撞斷言，也未放寬既有性能 AC。

### Windows 掉幀回歸

原門檻 mean ≤ 6ms、p95 ≤ 10ms、budget < 5% 且有實際位移或轉向，保持不變：
```text
VISIBLE_COMBAT case=previous-clear visible=240 turn_requests=194 samples=240 budget=5 mean_usec=5849.3 p95_usec=6077 max_usec=20069 queries=40219
VISIBLE_PROGRESS case=previous-clear distance=0.313 yaw_degrees=19.38 zero_commands=51/240 layered=233 max_physics_interval_usec=31843
VISIBLE_COMBAT case=observed-budget visible=240 turn_requests=192 samples=240 budget=4 mean_usec=5794.3 p95_usec=6049 max_usec=20060 queries=54560
VISIBLE_PROGRESS case=observed-budget distance=0.395 yaw_degrees=19.52 zero_commands=52/240 layered=236 max_physics_interval_usec=30057
```

完整清單：`/tmp/lea176-gap-loop-final-linux-results.json`、`/tmp/lea176-gap-loop-windows-final-results.json`。Linux oriented 最終證據為 `/tmp/lea176-gap-loop-oriented-final-linux.log`；早期 harness 錯用 quaternion angle 且零速初態的失敗保留，最終版已用真正 Frobenius 舊公式、frame-4380 速度及雙 MARGIN 重驗。獨立代理的幾何審查、log read-back 與實跑見 `/tmp/lea176-gap-loop-fresh-review.md`、`/tmp/lea176-gap-loop-fresh-oriented.log`。

## 交付邊界

既有未提交變更完整保留，沒有 Git commit。玩家物理與資源依本次 1,156 檔基線驗證未變。只修正本次靜態 Box 空角誤判與有限 Tank2 回歸，不宣稱任意動態地圖可達或整張 LEA-176 結案。既有玩家手感驗收維持。
