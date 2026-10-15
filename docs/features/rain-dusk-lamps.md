# 主地圖雨天近夜晚與可推倒路燈

本輪沿 [LEA-212](https://linear.app/leadingtw273/issue/LEA-212/主地圖雨天近夜晚與可推倒路燈)，leadi 於 2026-10-12 指定「接近入夜，路燈主導」。原草地 `d5d7ef69` 人驗 accepted 保留；本功能作者有限實跑已留證，獨立同 Head 驗收及產品人驗均 pending。基線 `36afbf71e49ad90dbab7613dc76a66e017127a80` 只額外保存原兩文件證據路徑搬遷及草地接受狀態。

## 固定範圍與使用入口

Godot 4.7.1／Forward+ 開啟 `src/main.tscn`（正式主圖 F5）：冷藍灰近夜晚中雨、六盞暖路燈；保留主圖原坦克、道路、建築透視、草形／密度／hash／風動與相機。訓練場、天氣 UI、時間推進、傷害、碎裂、砲彈毀燈及全圖雨／路燈串流不在本輪。

`main_weather.gd/tscn` 只建立六個 `street_lamp.tscn` 及一個 7000 world-space GPUParticles3D；雨跟隨正式相機所見地面中心，180×80×180m 原生有限高度場以 512 解析度處理屋頂與地面，8m 格跨越才更新。最多六局部暖光、最近兩盞有陰影，原 Sun 遮蔽保持。六盞初始位置為 (-94,0,-106)、(-140,0,-132)、(-80,0,-140)、(-140,0,-72)、(-77,0,-88)、(-94,0,-114)，actual shape 查核無需微移。

原路燈 GLB 維持內嵌素材，自己的柱／燈臂 collider、暖燈頭與光源由小元件建立。直立時鎖水平及旋轉軸；只接觸 `ContactTank` 才一次解鎖、施有限自身力矩並同回呼熄光／自有 emissive。Ground 不觸發、距離管理先排除已倒燈；重碰不重亮也不重設計時。0–5s 保留碰撞且可推動，5–7s 幾何實例 transparency 增加，7s 釋放完整 root/light/collider。

專案自有 `stream_grass`、`spawn_grass_ground` 的 light() 最小乘 `LIGHT_COLOR`；出生草改引用 project-owned `weather_grass`，它衍生 BinbunGrass 原 `grass.gdshader`（CC0），除 LIGHT_COLOR 與搬移所必需的原 include 絕對路徑外算法保持，vendor bytes 不改。

## 本機素材保全

原 ZIP `/home/markchou/project/tank-skirmish-local-assets/AtomicRealmModularRoads/[FREE] Modular Roads - Base.zip` SHA256 `217979d913494d419f24da5578c76254f529bb85de0f2679a5e02f38e5c3ba20`；只唯讀提取 `PLUS/gltf/lamp_1.glb`、`lamp_2.glb` 至 ignored `assets/AtomicRealmModularRoads/lighting/`。lamp_1 SHA256 `98f90212c9b9d632518169ffa1d10fb0e55bbcf81952d9cf545ac64ad0cb05c2`；lamp_2 `4bdb38d66c0b5d180aa2c06e012fa67b2e950a1aa748df59264a1b985f29c85a`。Godot 原生 importer 另從 GLB 內嵌 image 生成兩份 `lamp_*_roads_UV.png`，已驗證 bytes 與原內嵌圖完全相同；兩 PNG／sidecar 及 `.godot/imported/` 的 scn／ctex／md5 合計 16 個本機檔案 closure 見 `author-lamp-cache-closure.json`，M 同名全部不存在，取得時只精確新增、不同 bytes 不覆寫。兩原 GLB 與全部隔離 import closure 不進 Git、不外送；原 586 私素材及 atlas 都從 M copy2，原 UID／來源 bytes 及 M raw metadata 保全。

## 有限作者證據與再跑

證據根 `/tmp/tank-rain-dusk-20261012/`，精確 Head/tree 及來源 manifest 以 `author-evidence.json`、`author-input-manifest.json`、`author-source-manifest.json` 為準。正式主相機 1920×1080 原生 Forward+ 靜態畫面為 `baseline-final.png`／`candidate-final.png`；短倒燈連續圖 `weather-lamp-{0.0,0.5,1.5,2.5,4.5,5.5,6.8}.png` 與 `weather-lamp-trace.json` 是同一原 Tank2 真實接觸 case（原生數值另存 `weather-lamp-native-trace.json`；`weather-lamp-trace.json` 為最後 Linux case）。作者確認六燈 actual shape 初始無 overlap、Ground 不誤熄；原生 case 傾倒峰值95.50°、倒下後再接觸推6.57m；0秒熄光／發光，4.5秒仍在且有collider、6秒半透明、7秒完整清除，釋放後再跑15個physics frame，另一燈仍亮。這些不是 fresh PASS 或 human accepted。

Linux 原入口：`<Godot4.7.1> --headless --path <隔離專案> --script res://tests/weather_lamp_smoke.gd`；搭配獨立 XDG_DATA_HOME／XDG_CONFIG_HOME／XDG_CACHE_HOME 到自有 /tmp。`main_ground_visual_smoke`、`map960_components_smoke`、`rigid_tank_contact_smoke`、`tank_occlusion_smoke` 同版本 baseline／candidate 各 actual exit0，原 smoke 不改。新 weather smoke Linux 及 Windows 原生 actual exit0、runtime/script/shader ERROR0；原生退出兩版同有既有 TextureStorage RID／ImageTexture 清理訊息，另分類，不能稱全 log0。

Windows 原生入口固定 `Godot_v4.7.1-stable_win64_console.exe --path <自有UNC隔離專案> --script <自有helper或weather_lamp_smoke> --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 --log-file <自有log>`。只在隔離專案使用本機未提交 `override.cfg` 指定唯一 `TankRainDuskAuthor20261012` userdata；原產品 project.godot 與使用者 editor/cache/userdata 不動。helper／完整命令及退出碼留在 evidence，正式 source commit 不含 override.cfg。F5 相機 transform 與 size 原樣，靜態 sample 360 warmup／240 steady 分列 median/p95，草地保持啟用；不是全圖性能承諾或完整 CI。

首次 derivative 相對 include 搬移錯誤曾使 palette/noise 讀取失敗並產生藍白 chunk 階梯，已修為 vendor 絕對 include 及重拍；只以 `*-final` 畫面與 corrected logs 作最終來源證據。作者自檢不代替 fresh 驗收；後續 guarded 本機 FF 由 root 按獨立結果處理，沒有 push／PR／CI／公開發布的預填結果。

短樣本使用 Godot `Performance.TIME_PROCESS`（引擎回報的 process frame 時間），不是獨立 GPU timer 或呈現時間戳。baseline／candidate 同 1920×1080、同 F5 與草地，360 warmup／240 steady；warmup median/p95 分別 18.229/31.953ms 與 17.298/32.735ms；steady 分別 16.783/19.004ms 與 17.774/18.382ms。原生 VSync／Engine.max_fps／fixed-fps 的實際 read-back 見 `native-frame-settings.json`；同 cap 的有限穩定性證據不推算雨夜額外 GPU 成本。

## 2026-10-15：滑鼠移動時路燈變暗修正

沿本機 `7a7f534` 與企劃派工，僅修正路燈自身投影。滑鼠 look-ahead 會移動畫面中心落地點，原管理器因此更換最近兩盞開啟陰影的燈。原兩款 GLB 各只有一個合併網格；`lamp_2` 的光源位於 `(0, 5.85, 0)`，在燈柱範圍內。光源陰影開啟後，自身模型會擋住向地面照射的光；WarmHead 也原本開啟投影。現在只將原模型實例及自有燈頭的 `cast_shadow` 設為 OFF，原光源 `shadow_enabled` 管理仍保留，其他場景物件仍可遮光。六燈／最近兩陰影、相機、雨、草、碰撞與倒燈 5＋2 秒生命週期及素材 bytes 均保持。

本輪本機證據位於 `artifacts-local/lea212-20261015/`（ignored，不外送）。隔離 helper `project/lea212_capture.gd` 使用實際路燈場景與原 GLB，在固定灰色地面、相同正交相機 `(0,30,0)`／size32、1920×1080 上逐款比較熄光、陰影關及陰影開；Windows Godot 4.7.1／Forward+／Vulkan／RTX 5090。126 個固定地面樣本的平均亮度扣除熄光值後，`baseline/metrics.json` 顯示 `lamp_2` 關陰影為 `0.0635041352`、開陰影為 `0`；`candidate/metrics.json` 兩者均為 `0.0635041352`（保留比例 100%）。`lamp_1` 修正前後開／關陰影均為 `0.0632078574`。同機位畫面為 `baseline/lamp-2-shadow-on.png` 與 `candidate/lamp-2-shadow-on.png`，各款開／關對照同目錄皆有保存。這是隔離路燈的因果對照，正式 F5 滑鼠操作仍待 leadi 人驗。

## 2026-10-15：LEA-212 雨夜氛圍第一包與 v3 細修

本節實作以 `3ee957f` 為 baseline，在 `/tmp/tank-skirmish-lea212-atmosphere` 的 `feat/lea212-rain-atmosphere` 開發。企劃已通過 direction-streets-v2 的方向；本次完成 A–D 細修及作者驗證，產品驗收交由企劃另派跨模型 panel，不宣稱已驗收。

### 實作邊界與做法

- 六盞單臂 variant1 改放出生街廓內側人行道；位置及 yaw 定義在 `main_weather.gd`。生成高度固定 `0.110125m`，以 `spawn_height` 記錄原點。旋轉整個剛體，模型、燈臂、碰撞及局部光效共同旋轉。原六燈、最近兩盞陰影、110m 距離管理及倒燈 5＋2 秒生命週期保留。
- `lamp_atmosphere.gd` 在每盞燈建立隨燈生命週期的光暈與三層貼地霧；halo 使用面向相機的柔邊亮度分布，薄霧使用低頻噪聲、柔邊及場景深度交界消散。霧隨暖燈熄滅，無全圖全螢幕濾鏡。
- `lit_rain.gdshader` 共用管理器提供的六盞實際光源位置、顏色、範圍及啟用狀態；燈外回到原冷雨的顏色 `(0.60,0.72,0.85)` 與 alpha `0.36`，燈下隨距離轉暖、變亮。粒子數 7000、尺寸、速度、屋頂 heightfield 及相機跟隨方式保留。
- 濕路只在 `Roads` 的執行期材質副本壓暗底色，保留原貼圖與金屬比例，抑制環境高光。`wet_road_glint.gdshader` 作為道路 next pass，依實際燈位及相機方向生成狹長暖倒影；以平滑低頻 value noise 取代規則正弦條紋。沒有覆寫建築材質或更動建築淡出 render layers。
- A（v3 做法，已退回並由下方 v4 撤回）：只為主圖目前受控玩家車的非特效 StandardMaterial3D 建立執行期副本，加入低量冷色填光。企劃判定會抹平原色／明暗並干擾既有材質路徑，現行版本不採用。
- D：逐項關閉新增霧、草葉、其他粒子及固定草色後，灰片仍在；改用標準地材或關閉月光後才消失。來源縮到原草底自訂光照的月光／陰影分界。正式修正只將主圖 Sun 能量由 `0.12` 降到 `0.06`、`shadow_blur` 設 `3.0`，柔化冷亮片區，草材質算法與 palette 不變。
- 柱影：原 GLB 模型恢復 `cast_shadow=ON`，暖燈頭仍為 OFF，Omni 移到燈頭下方 `(1.12,5.65,0)`。單純移位實測仍有 1.7–3% 自遮光，因此路燈模型使用專用視覺 layer 20，僅暖燈的 `shadow_caster_mask` 排除此層；月光仍包含此層，其他物件仍可遮擋暖光。相機仍可見燈具。
- 主圖 glow 採低強度與 HDR threshold `2.3`，新增 unshaded 光效由 ALBEDO 輸出亮度；原生雙 Quad 探針顯示單寫 EMISSION 無法得到預期可見輸出，故未採用該寫法。

### 正交 volumetric fog 實測

`atmosphere/fog-probe/` 是 Windows 原生 Godot 4.7.1／Forward+ 的最小 FogVolume 場景，保存同機位正交與透視的開／關截圖、屬性 read-back 及引擎資訊。正交模式能設定 `volumetric_fog_enabled=true`，開／關有圖像差異，但這不足以證明局部體積霧正確，亦未證明平移穩定、無條紋及無邊緣切斷。本輪採局部柔邊平面霧與低量環境霧，不將此探針說成正交 volumetric fog 已可正式使用。

### 作者實測與重現

證據根為 `artifacts-local/lea212-20261015/atmosphere/`，不進 Git、不外送。`direction-streets-v3/{baseline,candidate}/{f5,lamp-close,street-layout}.png` 為同三機位原生對照：F5 檢視冷雨及玩家可讀性，lamp-close 檢視 halo／暖霧／平滑倒影，street-layout 檢視街燈擺放。helper 與完整命令存於 `validation-v3/helpers/`、`native-capture-commands.json`；自有 override.cfg／userdata 不提交。

原生環境為 Windows Godot 4.7.1、RTX 5090、Forward+／Vulkan、1920×1080。兩版均原 F5 transform／size100、草啟用，VSync read-back `1`、Engine.max_fps `0`，未傳 fixed-fps。helper 只凍結玩家移動、瞄準及相機控制，避免桌面游標造成機位或砲塔差異；產品相機與玩法程式不變。Performance.TIME_PROCESS 是引擎 process frame 時間，不是 GPU timer。

| 樣本 | baseline median／p95 | v3 median／p95 |
| --- | --- | --- |
| 360 warmup | 17.736／32.188 ms | 18.110／32.411 ms |
| 240 steady | 17.339／19.105 ms | 17.456／17.775 ms |

兩版原生 capture actual exit 0；runtime／script／shader ERROR 0。兩版退出時皆有相同的 TextureStorage RID 與 ImageTexture cleanup ERROR 各一條及 Texture leak WARNING 一條，保留完整 log，不報成原生全 log ERROR 0。此短樣本不推論全地圖效能。

五項 Linux headless smoke（`weather_lamp_smoke`、`main_ground_visual_smoke`、`map960_components_smoke`、`rigid_tank_contact_smoke`、`tank_occlusion_smoke`）皆 actual exit 0、ERROR 0，見 `validation-v3/smoke-results.json`。共同入口為 Godot 4.7.1 `--headless --audio-driver Dummy --fixed-fps 60 --path /tmp/tank-skirmish-lea212-atmosphere --script res://tests/<名稱>.gd`，XDG 三目錄隔離於 `/tmp/lea212-atmosphere-xdg/`。

路燈 smoke 只將高度基準改為生成高度、模型投影檢查改為 GLB ON／燈頭 OFF；新 P1 的接觸路線沿街朝 +Z、車心向車道偏 1m，避免舊橫向路線推到對街建物。原傾倒、實體推動、倒後再接觸、立即熄光、5＋2 秒及釋放後繼續更新等門檻保留。實測傾倒峰值 `90.73°`、總推動 `7.44m`、倒後再推 `0.86m`。

`validation-v3/placements.json` 以實際 capsule／arm shapes 查六盞初始 overlap，結果全空；各 y 均 `0.110125`，support ray 誤差小於 `0.000001m`，直立且未傾倒。兩款真 GLB 的原生光照測量見 `shadows-final/metrics.json`：扣除熄光後，俯視及斜視 shadow on/off 保留比均為 `100%`，月光柱影 strip／reference 分別為 variant1 `0.31863／0.40000`、variant2 `0.34510／0.40000`，並保存柱影 PNG。

額外 layer 1 遮擋物的地面對照，兩款燈皆由關陰影平均亮度 `0.101996` 變為開陰影 `0`，確認其他物件仍實際遮光。F5 全圖 PNG 加權編碼亮度由 baseline `0.18795` 變為 v3 `0.17175`；暖色門檻像素由 `13821` 增至 `16346`，該群平均飽和度由 `0.44867` 變為 `0.42673`。計算方法與全部三機位數據見 `image-metrics.json`；這是門檻式輔助比較，不當作美術驗收結論。

`validation-v3/preservation.json` 查核主工作目錄 2607 檔的 hash／size／mtime、主分支及 HEAD 均未動；候選副本 627 個 assets 檔與原檔 bytes 一致。這些是作者可重現證據，不替代企劃 panel 或 leadi 的人員產品驗收。

## v4：改用玩家局部補光，撤回材質接管

依「企劃審查 v3」，保留已通過的 B／C／D；完整移除 `_fill_player_materials`、`_readable_player_material` 及 `rain_readability_applied` metadata。天氣系統不再寫入坦克的 material override、surface override、next_pass 或 emission，坦克沿用原本的配色、受光、射擊／受損與 LEA-194 淡出材質路徑。原資產 bytes 不變。

`main_weather.gd` 改以一盞 `RainPlayerFill` OmniLight3D 作為目前受控剛體的子節點，局部位置 `(0,3.2,0)`、冷色 `(0.72,0.82,1)`、energy `1.6`、range `5m`、attenuation `1.5`、陰影關閉；以實際光照保留車身亮面、暗面及履帶細節。補光不進入六盞 `lamps` 陣列、不參與街燈距離排序，也不寫入暖雨／道路倒影的六燈參數。穩態光源預算為最多六盞街燈加一盞玩家補光，街燈最多兩盞陰影，補光不增加陰影來源。原生 read-back 實際為六盞街燈全亮、兩盞有陰影，加一盞無陰影補光。

綁定 `PlayerRuntime.controlled_tank_changed`，換車先隱藏／釋放舊補光，再綁新車。死亡不只等車被移除：綁定直屬 `HealthComponent.depleted`，血量歸零當下即撤光，保留的殘骸不會繼續被補亮；已死亡車也不重新補光。地圖卸載時解除 runtime／health 訊號並釋放掛在車上的補光。只載入地圖且沒有 PlayerRuntime 時跳過補光綁定。

作者新增 `weather_player_fill_smoke`，透過實際主圖與公開換車／生命元件驗證跟隨、換車移除、死亡即熄、死車不重亮、重新換存活車及地圖卸載清理。它與五項指定 smoke 皆 actual exit `0`、ERROR `0`；完整命令與結果為 `atmosphere/validation-v4/smoke-results.json`。這是作者回歸測試，不是企劃的 fresh-context 驗收。

v4 同三機位截圖位於 `atmosphere/direction-streets-v4/{baseline,candidate}/{f5,lamp-close,street-layout}.png`，baseline 仍為 `3ee957f`。新增效能證據集中於 `validation-v4/performance.json`，完整命令與 actual exit code 為 `native-capture-commands.json`；逐幀原始樣本、機位、視窗與光源 read-back 在兩個 capture.json，helper 封存於 `validation-v4/helpers/`。

Windows 原生 Godot 4.7.1／RTX 5090／Forward+／Vulkan，兩版同 1920×1080、原 F5 transform／size100、草啟用、VSync `1`、max_fps `0`，依序執行，各取 360 warmup 及 240 steady。數據仍為 Performance.TIME_PROCESS，引擎 process frame 時間，非 GPU timer；受 VSync 影響的短樣本不推論全圖成本。

| 樣本 | baseline 3ee957f median／p95 | v4 median／p95 |
| --- | --- | --- |
| 360 warmup | 16.600／18.680 ms | 18.343／18.788 ms |
| 240 steady | 16.957／19.334 ms | 16.760／18.827 ms |

兩版原生 capture actual exit `0`，runtime／script／shader ERROR `0`；退出時均有與 v3 相同的兩條 texture cleanup ERROR 與一條 WARNING，完整保留，未列為 smoke 的 ERROR 0。`validation-v4/preservation.json` 另存主目錄與素材保全查核。v4 以新 commit 接在 `8c68e9f` 後，不 amend、不 push、不 PR、不關票；A 的視覺驗收仍交企劃。

新增原 weather smoke 的六盞自身投影檢查；未修產品來源時 `red-weather.log` actual exit1／六個新檢查 FAIL，其餘原檢查 PASS；修正後 `green-weather.log` actual exit0／failures0，兩者 ERROR0。命令為 `<Godot4.7.1> --headless --audio-driver Dummy --fixed-fps 60 --path <隔離專案> --script res://tests/weather_lamp_smoke.gd`，XDG 三目錄獨立置於 `/tmp/lea212-xdg/`。Windows 對照命令沿前述原生入口，改用 `--script res://lea212_capture.gd --resolution 1920x1080 -- baseline`／`-- candidate`；有效兩次 actual exit0／ERROR0。首次 960×720 helper 座標換算錯誤的輸出保存在 `baseline-harness-invalid/` 與 `baseline-console.log`，不作有效證據。

最新封存 Head 的 fresh-context 四原 smoke、weather smoke 與有限來源／證據查核另存本輪 `fresh/`。不以本機修正宣稱原功能全部人驗通過、完整 CI、push、PR、合併或關單；原產品設定與 `.godot` 未交給測試引擎寫入。
