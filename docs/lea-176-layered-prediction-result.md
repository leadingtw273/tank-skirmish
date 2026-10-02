# LEA-176 分層預測結果

> 後續使用者 F4 的 Tank2 下方窄口反例已修正並補實際到達驗收，見 [窄口修正結果](lea-176-narrow-portal-result.md)。本文件保留此前分層交付的數字與有限 AC。

## 範圍與落地內容

已搬入 9 個 AI／測試檔案（尚未提交 Git）；逐檔雜湊清單為 `/tmp/lea176-layered-promotion.json`。變更限 AI 分層預測、兩個 smoke、navmesh gap smoke、recovery smoke 與 40 案平地 fixture；沒有修改玩家剛體物理或車型參數。

`/tmp/lea176-final-preservation.json` 驗證 1,144 個既有檔案沒有遺失，沒有非預期改動，且 promotion hash 全數相符。既有未提交變更已保留。這不代表整個 LEA-176 已結案。

## 演算法與適用邊界

- `tank_driving_predictor.gd` 先驗一個 physics tick 的控制前綴及完整制動路徑，再把遠期三秒當成風險。遠期只可使用整次呼叫開始後 6 ms 內的剩餘額度；20 ms／4096 查詢硬上限未提高。`clear/blocked/unknown` 分開記錄，遠期超時不抹去已驗近場候選，沒有已驗候選時的零輸入也不冒稱安全。
- `rigid_motion_prediction.gd` 保存跨步 DriveIntent、世界水平速度與一 tick pending force/torque；保留既有 feedback/feed-forward、摩擦橢圓及 normalized side budget，不直接寫入真車速度。
- 零輸入尾段只有在 Intent 與兩個導數精確為零、pending 已由模型線性分支計算、且可證明未來 station 不飽和時，才使用動能座標的 Gershgorin 收縮界。Frobenius 旋轉 arc 取代會受 acos precision floor 影響的角度量測；無法證明時不宣稱 near safe。
- 平地有限包絡為 `0.01 m + 0.08 s * max_model_vertex_speed + tail`，其中頂點速度上界為水平速度長度加上 `radius * abs(yaw_rate)`，包含初態與控制前綴；`tail <= 0.002 m` 才可採用。固定 35 cm 方案會把初始靠牆靜止姿態也判為阻擋並造成 stall，因此已拒絕，沒有採用。
- 非平地、支撐不明、接觸或 recovery 情境交回 legacy。Recovery handoff 的 nominal-only 行為維持。

原 16 案、12 案旋轉／倒車混合控制、4 案真正控制前綴及 8 案額外低速驗證，共 40 案、3,223 筆真車姿態。fixture 檢查每個真車姿態對整條模型路徑的頂點位移上界、候選獨立性、旋轉共變及尾界；前 32 案量得的最大上界為 `0.2765 m`，不是同時刻中心位置差，也不是通用安全餘裕。物理參數、引擎或碰撞幾何改動後須重新量測，不能只依賴這組固定 fixture。

## 驗收結果

以下 AI smoke 均已在正式工作目錄重跑，以 60 Hz physics 執行；terrain 與 gap 的 `--fixed-fps 60` 只關閉即時同步，physics tick 仍為 60 Hz。

| 驗收 | 結果與證據 |
|---|---|
| 可見戰鬥固定場景 | PASS。`previous-clear` mean/p95 `5.6449/6.072 ms`、budget `3/240`、yaw `19.68°`、layered `235`；`observed-budget` 為 `5.5365/6.046 ms`、`1/240`、`19.67°`、`239`。舊 baseline 是 `134/240`、`17.6515/20.06 ms`。`/tmp/lea176-final-rigid_visible_combat_performance_smoke.log` |
| 開闊追擊 | PASS。yaw `29.74°`、位移 `9.759 m`、budget `0`。`/tmp/lea176-final-rigid_training_pursuit_smoke.log` |
| 四車 24 地形案例 | PASS。`RIGID_AI_TERRAIN failures=0`。`/tmp/lea176-final-rigid_ai_terrain_smoke.log` |
| 40 案制動模型 | PASS。tail 均不超過 `0.002 m`，fixture 與 geometry 都通過。`/tmp/lea176-final-rigid_braking_prediction_smoke.log`、`/tmp/lea176-final-rigid_braking_sweep_smoke.log` |
| 車身／砲管／同 RID floor-wall 邊界 | PASS。`/tmp/lea176-final-rigid_ai_curb_boundary_smoke.log` |
| recovery | PASS。progress gate、三次有限倒車、blocked terminal 與 reset 都通過。`/tmp/lea176-final-enemy_recovery_smoke.log` |
| 玩家曲線與受保護檔 | 四車共 144 筆 CURVE 紀錄與 4 筆 CURVE_PARAMS 的數值差異均為 `0`，22 個 protected hash 差 `0`。`/tmp/lea176-layered-stage/curve-tank{1,2,3,4}.log` |

Fresh agent `layered_acceptance` 亦獨立重跑 40 案與 geometry 並審查程式；Opus 第二輪沒有本單 blocker。

## Navmesh gap 的精確敘述

最終 gap smoke PASS 的 AC 是 navmesh 連通、實車前進超過 0.5 m、且不穿牆。最終執行中 `portal=false`、距 goal `14.318 m`、zero ratio `5.78%`；因此不能聲稱最終 run 已通過 portal 或到達 goal。較早 stage 的 `portal=true` 記錄不作最終到達證據。最終 log 為 `/tmp/lea176-final-rigid_enemy_navmesh_gap_smoke.log`。

## 可重跑方式

使用本機固定版本 Godot 4.7.1；效能測試依下列方式獨立、循序執行：

```sh
/home/markchou/.cache/tank-skirmish/toolchains/godot/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64 \
  --headless --audio-driver Dummy \
  --path /home/markchou/project/tank-skirmish-worktrees/lea-177-main-world \
  --script res://tests/rigid_visible_combat_performance_smoke.gd
```

依序重跑 `rigid_visible_combat_performance_smoke.gd`、`rigid_training_pursuit_smoke.gd`、`rigid_ai_terrain_smoke.gd`、`rigid_enemy_navmesh_gap_smoke.gd`、`rigid_braking_prediction_smoke.gd`、`rigid_braking_sweep_smoke.gd`、`rigid_ai_curb_boundary_smoke.gd` 與 `enemy_recovery_smoke.gd`；各項的正式輸出檔列於上表。terrain 與 gap 的本次正式重跑額外使用 `--fixed-fps 60`；效能兩項沒有使用此選項。玩家曲線在隔離測試樹執行，受保護物理及資源與正式工作目錄雜湊完全相同。

## Windows 補驗（2026-09-23）

Windows Godot `4.7.1.stable.official.a13da4feb` 透過 console executable 在同一正式工作目錄循序執行，既有 Editor 保持開啟。8 項測試 exit code 均為 0；此為 Windows 原生 headless 自動驗收，不是人工視窗試玩或 GPU/render 幀率量測。

| 驗收 | Windows 結果 |
|---|---|
| previous-clear 可見戰鬥 | mean/p95 `5.9584/6.103 ms`，budget `4/240`，yaw `19.57°` |
| observed-budget 可見戰鬥 | mean/p95 `5.8483/6.066 ms`，budget `3/240`，yaw `19.58°` |
| 開闊追擊 | yaw `30.50°`、位移 `9.846 m`、budget `0/240` |
| 制動／碰撞／脫困 | 40 案制動、braking sweep、curb boundary 與 recovery 全數通過 |
| 地形／窄口 | 24 案地形及原窄口進展契約通過；不追加完整到達聲稱 |

效能門檻仍為 mean ≤ 6 ms、p95 ≤ 10 ms、budget < 5%，並驗證實際位移或轉向。效能測試沒有使用 `--fixed-fps`；僅 terrain/gap 使用 `--fixed-fps 60`。Windows previous-clear 的平均耗時接近 6 ms 門檻，本次通過不代表所有機器或負載下都有相同餘裕。

證據：`/tmp/lea176-final-windows-visible.log`、`/tmp/lea176-final-windows-results.json` 及其中列出的 7 份 log。獨立代理已核對可見戰鬥、追擊、40 案制動與 geometry log，並確認 9 個程式／測試檔的交付雜湊未變。

## 限制與未做聲稱

- Windows 同版本 headless 自動測試已通過；尚未將人工視窗試玩或畫面幀率視為已驗收。
- 最高速真車撞障礙的單一 E2E 尚未執行；40 案 motion 與 geometry smoke 是互補證據，不能把它們寫成該單一 E2E 已完成。
- 不宣稱一般動態世界、任意地形或完整 LEA-176 已驗收。
- Native track「原 probe 為 0」的推論已撤回：原 probe 缺欄。第 90 幀 native 約 `36.9 kN`；`<0.05 N` 僅適用選定 spring-only frame 的 replay。
- 工具可建立、完成並 reuse 子代理，但沒有 close/release 操作；沒有舊 agent 已清掉或名額已釋放的證據。
