# LEA-212 第三輪：真首發診斷 checkpoint

2026-10-16，依 `.git/codex-task-lea212-round3.md` T1。基線為9e19e1a與ae09baa；只新增診斷工具，不修改LEA-134的CombatRuntime預初始化、FX、玩法、輸入或相機架構。T1尚未修正／尚未達標，停在派工單允許的診斷checkpoint；其餘T2–T5另行實作與作者回歸，獨立驗收交企劃。

## 場景、方法與證據有效性

Windows原生Godot4.7.1／Forward+ Vulkan／RTX5090，1920×1080、VSync1／60Hz、max_fps0、草開，載入正式 `res://src/main.tscn`。完整資源閉包讀回218個道路mesh、170個建築mesh；每個執行副本含相同593個ignored生成資源，逐檔SHA另存本機。只在額外`/tmp/lea212-round3-runs/`副本跑引擎；主目錄與開發worktree的project.godot、cache、素材不交給引擎寫入。

每次process僅四次真左鍵：場景ready後7s首次，之後每4s一發；`Input.parse_input_event`走原PlayerController、request_fire與ShotEvent，保留原物理、砲口火光、煙、砲彈、命中特效與camera recoil。只停用鍵盤移動／滑鼠瞄準更新以固定案例，沒有預先開砲。記錄逐frame_post_draw單調時鐘間隔、最新viewport render CPU/GPU、setup CPU、累計pipeline counters及FX/光源新增事件。CPU／GPU回報不假設同幀對齊、不相加；沒有用TIME_PROCESS當逐幀時間。

主門檻窗口為每發後0–2000ms（含首次impact）：首發最大間隔須同時≤50ms且≤後三發最大值的2倍；0–200ms另列只作砲口來源定位。不能以200ms小窗藏掉較晚impact尖峰。

主要對照順序cold-A1／cold-B1／cold-B2／cold-A2。A=9e19e1a，B=ae09baa；各副本保留同一份import cache，但開始時沒有專案`.godot/shader_cache`，另有唯一userdata；沒有清理或隔離使用者driver cache，故不能宣稱完全冷GPU。四個主要process四發的2秒窗口皆100%前景。延續快取的另一輪A1／B1／B2／A2完整保留為參考，與主要組分開。

最初`round3/t1`、`t2/diagnosis`與`visuals`的副本漏帶ignored道路／建築生成資源，雖exit0但有大量載入ERROR；這些原始資料保留並由`invalid-runtime-closure.json`明列無效，完全不作正式遊戲效能／視覺結論。補齊閉包後的`*-full-map/`才是有效證據；新工具已加入道路／建築實例數guard。

## 主樣本結果（0–2000ms，毫秒）

| 樣本 | 首發最大間隔 | 後三發最大間隔 | 倍率 | T1門檻 |
| --- | ---: | ---: | ---: | --- |
| 9e19e1a cold-A1 | 74.885 | 24.882 | 3.010 | 未通過 |
| 9e19e1a cold-A2 | 132.081 | 23.057 | 5.728 | 未通過 |
| ae09baa cold-B1 | 168.564 | 25.189 | 6.692 | 未通過 |
| ae09baa cold-B2 | 83.549 | 20.496 | 4.076 | 未通過 |

cold-B1的168.564ms在首發後259.965ms；前200ms另有92.402ms峰值，兩者都保留。首發新增surface／specialization pipeline，後三發通常無增量；首個impact進入200ms內時，短窗也會包含impact的額外pipeline。延續cache的兩次ae09baa首發為31.970／26.222ms，不能與空專案shader cache樣本混成同分布，也不能用它否定嚴重卡頓。

## 消去實驗、根因範圍與停止理由

| ae09baa診斷變因 | 首發最大間隔 | 後三發最大間隔 | 解讀 |
| --- | ---: | ---: | --- |
| 只隱藏新增FX動態光 | 80.147 | 26.177 | 仍超標；首發200ms為前景，後續有背景樣本 |
| 保留CPU實例化、隱藏全部FX繪製 | 18.455 | 18.839 | 方向性支持；首發為背景，不當成完美受控因果或產品修正 |

所有觀察到的MuzzleFlash／Javelin／Impact OmniLight都未開陰影；只停FX lights仍有尖峰。沒有證據支持以砍街燈／陰影或調atlas當本次修正。資料支持首次可見FX及相關pipeline首用路徑是主要待處理來源，但尚未鎖定單一flash／smoke／projectile／impact材質、粒子pipeline或特定driver call；counter增量本身不是編譯耗時，不能把低GPU timer當作同一幀GPU不忙的證明。

`src/combat/combat_runtime.gd`現有預初始化把四類FX隱藏、CPU建立後同步free，原註解已明示不保證GPU pipeline。要在真首發前覆蓋首次可見繪製的GPU資源與受影響world材質，需要重新設計預初始化／預繪生命週期；這命中T1明列的CombatRuntime架構停止條件。本輪不自行擴建，T1以診斷checkpoint交企劃裁決，沒有採用關FX、降陰影、loading畫面或輸入閘門來掩蓋尖峰。

## 重現與檔案

```sh
<Windows-Godot4.7.1> --path <完整閉包隔離UNC副本> --script res://scripts/weather/profile_first_shot.gd --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1920x1080 --log-file <out>/engine.log -- <out> <label> normal
```

原生工具需`application/config/custom_user_dir_name`以`TankRainRound3`開頭，只在本機未提交override.cfg設定。`fx-lights-off`／`all-fx-off`等參數僅是消去實驗，不能作交付設定。

本機ignored證據根：`artifacts-local/lea212-20261015/round3/`。`t1-full-map/diagnosis.json`保存全部raw重算、兩種窗口、焦點、pipeline、事件與主門檻；各run的`first-shot.json`保存逐幀raw，`shot-summary.json`是簡表。`full-native-commands.json`與`t1-full-map/commands.json`保存命令／actual exit；有效主圖process全部exit0、runtime/script/shader ERROR0，退出仍各有原有兩條texture cleanup ERROR及一條WARNING，不報成全log ERROR0。`cold-cache-policy.json`、`generated-private-source-manifest.json`與`invalid-runtime-closure.json`保存條件與無效資料界線。
