# LEA-212 T1b：開場三幀 GPU 預繪

2026-10-16，接續 `1d0a3a6`，依企劃追加 T1b 授權修改 CombatRuntime 預初始化生命週期。T2–T5 維持企劃已通過的產品檔案。本文為作者實測與回歸，沒有冒充 fresh-context／跨模型驗收；後續獨立驗收仍交企劃。

## 根因與修正

舊流程在同一次 ready 呼叫中，把四類 FX 隱藏、建立、播放後同步 free。RenderingServer 尚未處理第一個 render frame 就失去實例；本輪修前首發仍各新增 12 個 Surface pipeline。現在只建立一次 `FiringVfxWarmup`，在正式 world／正式相機視錐中央、地表附近，保留原 shader、材質、粒子與 FX light 類型，提交三個 render frame 後清除。來源仍同步註冊；玩家開砲不等待預繪。

預繪副本將粒子 transform／運動、一般 mesh 與 decal 縮至百萬分之一，FX light 使用非零的極低能量，原 range／shadow flags 保留。先把動畫推進至有幾何的時刻再暫停，避免動畫把預繪尺寸或光源能量改回來；三幀後移除全部副本並解除 RenderingServer signals。沒有建立戰鬥 Projectile、傷害、音效、loading、輸入 gate，沒有修改真射擊 FX、相機、project.godot 或畫質。

四車型射擊共用 Flash／Smoke／Javelin／Impact 四個 wrapper；四車 muzzle_flash_scale 同為 1.145038，姿態／尺寸是 uniform／transform 差異，並非四套 shader。新 smoke 在四車型分別於第 0–2 幀經原 PlayerController 開砲，也驗預繪期間換車、單次註冊、真 FX 尺寸未被污染及完整清除。跨受傷門檻的持續 damage stage／致死 depleted FX 不是本次首發四發 fixture 的輸出；不宣稱這次量過擊殺首用尖峰。

## 原生逐幀結果

Windows Godot 4.7.1／Forward+ Vulkan／RTX 5090，1920×1080、VSync 60Hz、草開。正式 main 資源閉包讀回 218 個道路 mesh、170 個建築 mesh、12494 株草。所有正式首發樣本均四次 request／四次 ShotEvent、camera size 100、四發窗口全程前景；沒有真開砲預熱。

每發後 0–2000ms（含 impact）取 frame_post_draw 單調時鐘最大間隔，不用 TIME_PROCESS。A 為 `1d0a3a6`，B 為修後，順序 A1／B1／B2／A2，然後同副本同 userdata 延續快取再跑相同順序。四份 cold userdata 原先不存在，Godot shader_cache 及 vulkan pipeline cache 都空；系統 NVIDIA driver cache 沒清除／隔離，不能稱完全冷 GPU。

| 情況 | 修前首發 max | 修前後三發 max | 修後首發 max | 修後後三發 max | 修後倍率 |
| --- | ---: | ---: | ---: | ---: | ---: |
| cold 1 | 55.945 | 27.099 | 35.948 | 23.785 | 1.511 |
| cold 2 | 59.225 | 23.803 | 25.552 | 23.026 | 1.110 |
| continued 1 | 37.632 | 24.420 | 27.543 | 23.817 | 1.156 |
| continued 2 | 24.209 | 24.765 | 28.137 | 26.623 | 1.057 |

單位 ms。修後四個 process 都符合首發 ≤50ms 且 ≤後三發最大值 2 倍。修前首發各新增 Surface 12／Specialization 37，修後為 Surface 0／Specialization 9，Draw 皆 0。Specialization 仍有背景最佳化；沒有宣稱所有編譯消失，也不把 counter 當編譯耗時。

## 真 GPU 提交與不可見性

另用兩個同步 SubViewport，共用正式 world、正式相機 transform／projection、1920×1080、環境與 shadow atlas；主相機不改。一個包含微型預繪，一個只排除預繪使用的診斷 layer 19。前三幀 visible draw call 差為 **14／12／12**，primitive 差 **24844／34220／34220**；第四、五幀差皆為 0。這證明 RenderingServer 實際提交了幾何，並非只 CPU instantiate 或 visible=false；不宣稱微型三角形一定產生可見 fragment。

五幀 RGB 差分依序為 0、2、0、0、0 個像素；唯一兩個像素只差 1/255，其餘 2073598 像素相同，沒有可見閃光或殘影。四 wrapper 無 AudioStreamPlayer／AudioStreamPlayer3D／Timer，所有預繪 child ID 在三幀後失效。原始圖在本機 `artifacts-local/lea212-20261015/round3/t1b/pixels-free-layer/`，每幀 `frame-XX-micro.png` 對 `frame-XX-excluded.png`；同目錄 difference.json／pixels.json 留像素與 draw 數字。首輪 pixels/ 誤用了路燈 shadow layer 20，已排除，不拿它作產品結論。

## 開場與 editor F5

正式八個樣本 ready 當下皆 controls_enabled=true、registered_sources=1；ready 後讀回可接受輸入狀態耗時 0.005–0.007ms，新增等待 **0 幀**。這是讀回時間，不是實際按鍵延遲 benchmark；真正四車型第 0–2 幀開砲由 smoke 驗證。

cold 的 ready→第一張 draw：修前 2909.865／2756.838ms，修後 2825.708／2897.921ms；continued：修前 2804.771／2940.675ms，修後 2792.262／2767.861ms。都包含整個正式場景的首次 GPU 工作，沒有新增三幀開場等待。UNC 副本的 load→ready cold 修前 7835.448／7887.659ms、修後 8413.803／8591.195ms；continued 修前 10775.602／10590.498ms、修後 7274.914／7967.053ms。檔案讀取／背景負載變異很大，不將之宣稱成啟動加速。

另在兩份 /tmp 副本只插入函式邊界計時，單次原生 `_preinitialize_firing_vfx()` CPU 為修前 **112.380ms**、修後 **144.907ms**（差 32.527ms）；該次整體 ready→首 draw 為 2936.204／2913.183ms，controls／來源皆在 ready 有效。預繪有少量初始化成本，沒有額外等待三幀才可操作；不把單對照外推為固定啟動成本。setup-baseline/、setup-candidate/ 保存原始資料。

另用 `/tmp` self-contained Windows editor、乾淨 workspace，透過 `EditorInterface.play_main_scene()`（F5 相同入口）啟動真 main，遊戲是原生 Forward+ 1920×1080，`EngineDebugger.is_active()` 實讀 true。只在隔離副本插樁 main 的 ready 尾端掛 Node 版 profiler；與正式協定同樣四次真左鍵、含 impact 2 秒窗口。首發 **22.016ms**，後三發 **17.542／50.027／23.300ms**，全部前景、Surface／Draw 增量為 0；首發仍有 10 個背景 Specialization。第三發 50.027ms 尖峰完整保留，不稱 debugger 完全沒有尖峰。這是 headless editor 管理的原生遊戲／debugger 實測，沒有操作 leadi 的 GUI editor 或改其設定。

首輪 editor-f5/ 曾沿用舊 training tool 預覽，且視埠 2019×1080，首發 227.589ms；該輪不符合受控視埠，也有 editor preview 錯誤，不作達標證據，原始資料保留。有效補樣是 editor-f5-clean/，遊戲與 editor log 均保留。

## 不退步與回歸

固定 1920×1080 後再交錯 A1／B1／B2／A2，每機位 360 warmup＋240 steady frames；所有 steady frame 均在前景、camera transform／size 不變、逐幀讀回 1920×1080。只看 frame_post_draw 幀間隔：

| 機位 | 修前 median（兩次） | 修後 median（兩次） | 修前 p95（兩次） | 修後 p95（兩次） |
| --- | --- | --- | --- | --- |
| F5 | 16.690／16.624 | 16.667／16.671 | 17.450／18.847 | 17.520／18.573 |
| dense | 16.641／16.636 | 16.649／16.666 | 17.661／18.839 | 18.266／18.427 |

單位 ms。median 均 ≤17.5ms，p95 沒有明顯增高，不宣稱穩態效能提升。全圖 117 燈，F5／dense 候選 48／61，啟用與陰影數皆 48／61、budget dropped=0；8192 atlas、32-bit、四象限 64 格（enum 4）不變。原始資料 weather-fixed-*/profile.json，逐 CPU／GPU／setup time 也保留，三者不視為同幀且不相加。

首輪 weather-A1 的有邊框視窗被 Windows 壓成 2019×1080；整批首輪 weather-*/ 不作最終配對結論。已在診斷工具固定無邊框 1920×1080、每幀檢查並對不符尺寸回傳 exit 2，再以相同工具重跑修前後四份；產品視窗／相機設定沒改。

12 個 headless smoke 全部 exit 0、ERROR 0：firing_vfx_warmup、combat_boundary、vfx_wrapper、firing_visual_recoil、weather_headlights、weather_lamp、weather_lamp_budget、main_ground_visual、map960_components、rigid_tank_contact、tank_occlusion、player_rigid_variants_runtime（檔名皆加 `_smoke.gd`）。原生 firing_vfx_warmup、weather_light_occlusion 也都 exit 0，後者 806 samples、failures=0。新四車 fixture 有 10 條既有 damage visuals owner warning，既有 tank_occlusion／variants_runtime 分別 2／8 條；沒有改與本單無關的 owner 路徑。

```sh
# 在完整閉包 /tmp 副本，Linux Godot 4.7.1；全套實際命令與 exit 見 smokes/results.json。
<Godot> --headless --path <副本> --script res://tests/combat_boundary_smoke.gd
<Godot> --headless --path <副本> --script res://tests/firing_vfx_warmup_smoke.gd
<Godot> --headless --fixed-fps 60 --path <副本> --script res://tests/firing_visual_recoil_smoke.gd
# 原生 GPU，非效能用固定時間步長：
<Windows-Godot> --path <副本UNC> --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1920x1080 --script res://tests/weather_light_occlusion_smoke.gd
```

recoil 首輪命令漏了 quality.mjs 既有的 `--fixed-fps 60`，修前也重現相同三幀 live render 失敗；改用原標準命令後兩版皆通過，沒有改該測試或放寬斷言。rigid/contact、occlusion、variants 同樣以固定 60Hz 模擬跑功能 smoke，與真時間效能樣本分開。combat_boundary 只把舊「同步 free」更新成 T1b 授權的「三幀後 free」；健康、cooldown、recoil、鏡頭、事件數、真開砲／命中／cleanup 斷言都保留。

基線 479 個 src/tests tracked blobs 逐檔符合 1d0a3a6；修後變動的產品／測試 GDScript 與執行副本 bytes 相符。T2–T5 的草、四車燈錨點、路燈 halo／燈罩、wet road shader 均無 diff。主目錄分支仍 playtest/lea212-round2、Head ae09baa；主目錄既有非 cache 檔案無變更，worktree 的 project.godot／素材／.godot 保全無差異。主與 worktree 各 627 份素材 bytes（含 18 GLB）符合前輪素材快照，593 個私有生成資源也一致。

主目錄已有 editor 持續開著：本輪 guard 觀察到 35 份前輪證據 PNG 的既有 .ctex cache 消失，global_script_class_cache.cfg 只有 mtime 改變；沒有新 cache 檔，不能宣稱整個主 .godot 完全不變。本輪沒有在主目錄／開發 worktree 啟動引擎，也沒有對它們的 .godot 做寫入或刪除；沒有回寫或復原使用中的 cache。證據目錄在寫檔前確認 .gdignore，全部引擎在額外 /tmp 執行副本。

本機證據根 `artifacts-local/lea212-20261015/round3/t1b/`：first-shot-summary.json、formal-commands.json、formal-plan.json、method.json、各 run raw JSON／log、pixels-free-layer/、editor-f5-clean/、smokes/results.json、guard-after.json、harness/。原生 main 執行退出時仍有既有兩條 texture cleanup ERROR／一條 Texture WARNING，與 runtime/script/shader ERROR 分列，沒有報成全 log 零 ERROR。未跑完整 CI，未 push、未開 PR。

Godot 4.7 官方對 Surface／Draw／Specialization 的說明及 hidden instance 生命週期背景：<https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html>。此處是否有效以本機真 draw、首發原始樣本為準，沒有改內建渲染設定。
