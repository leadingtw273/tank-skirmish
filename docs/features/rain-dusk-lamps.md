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

## 2026-10-15 第二輪：R1 車燈、R2 遮擋、R3-A 全圖燈位提案

基底 `9e19e1a`，續用 `/tmp/tank-skirmish-lea212-atmosphere`／`feat/lea212-rain-atmosphere`。本節取代 v4 的玩家上方補光與「最近兩盞街燈陰影」；只交 R1＋R2＋R3-A，停企劃審查。R3-B 的全圖實例、動態光源預算與效能矩陣尚未實作，不將作者測試視為產品驗收。

### R1：四車型車頭錨點

四份 donor variant 場景各定義空 `Headlights/HeadlightL`、`HeadlightR`；rigid 組裝只把該空群組移到車身根層，不跟隨砲塔或視覺後座。位置依既有正式 hull／tracks convex snapshot 的 rigid-local 外形配置，沒有改 mesh、材質、碰撞或物理參數。車身前進為 −X、左右為 ±Z，錨點 yaw=π/2，Spot 的 −Z 因而朝車身 −X。

| 車型 | ID | 左右錨點 rigid-local (x,y,±z)，m |
| --- | --- | --- |
| 輕型 | tank1 | (−3.08, 0.90, ±1.60) |
| 中型 | tank2 | (−3.42, 1.00, ±1.80) |
| 重型 | tank3 | (−3.76, 1.00, ±1.95) |
| 驅逐 | tank4 | (−3.42, 0.85, ±1.70) |

MainWeather 移除 RainPlayerFill；只在存活的受控車兩錨點上掛 SpotLight3D：暖白 `(1,0.92,0.78)`、energy12、range20m、angle24°、向下6°、陰影開啟。不新增車燈模型，不接管坦克材質。換車／死亡／卸載沿用 runtime 與 health 訊號，立即隱藏並釋放舊燈；訓練場只有空錨點，不掛雨夜車燈。

`round2/screens/candidate/headlights-tank{1,2,3,4}.png` 為四車車頭近景；`weather_headlights_smoke` 實際檢查錨點前向射線能打到車身且起點在形狀外、前進／略向下方向、平移／轉向跟隨、四車切換、死亡與卸載。`headlight-road/` 另有關閉街燈後的同機位車燈開／關濕路面對照：距車燈14.58m樣本 PNG 亮度 `0.04545→0.06980`，範圍仍為20m。

### R2：兩種漏光根因與修正

根因一是六盞活躍 Omni 只有最近兩盞開陰影，其餘可照到建築背後。根因二是 mist／wet-glint／暖雨原本由 unshaded 距離公式自繪，沒有光源到受光點的遮擋；原 depth test 只管相機方向，無法代替光線陰影。halo 也可能在燈頭中心被牆擋住時仍露出外圈。

同主圖機位消去對照在 `round2/r2-ablation/{baseline,candidate}/`：正交 size28、camera `(−102,8,−118)` 看 `(−80,3,−120)`，先保留 F5 原燈管理狀態再固定。每版依序拍 full、只全開陰影、再停用自繪光效；lamp2 的 energy6／range22 全程相同。背牆地面固定 patch 的平均 PNG 亮度為：

| 狀態 | baseline 9e19e1a | 修正後 |
| --- | --- | --- |
| 完整效果 | 0.288423 | 0.128833 |
| 六街燈全開陰影 | 0.156886 | 0.128850 |
| 再關閉自繪光效 | 0.128833 | 0.128833 |

因此兩條漏光路徑都成立；修正後完整效果的背牆 patch 回到無自繪暖光基準，沒有降低路燈亮度或範圍來隱藏問題。完整同機位前後為 `screens/{baseline,candidate}/building-occlusion.png`，另有 F5、lamp-close。

`r2-geometry.json` 另以實體 ray 確認：相機到 StreetLamp2 光心，以及該光心到 patch 中心地面 `(−98.97682,0,−122.3099)`，兩條視線均被 `Buildings/4Story_Wide_2Doors_Mat_default6` 擋住；不是只憑畫面顏色猜測遮擋關係。

本階段只有原六盞街燈，110m內啟用的街燈一律開陰影；加兩盞有陰影車燈，最多8個局部陰影光源，Sun另計。自繪霧、暖雨及濕路倒影改用 shaded 自訂 `light()` 的真實 `ATTENUATION`（包含陰影）；冷雨底色保留，倒影依實際光方向匹配來源。halo 以 `project_ray_origin` 到燈頭中心的實體 ray 查遮擋，支援正交相機的平行視線；保留原逐像素 depth test。原路燈 caster layer20 排除自身的方案不變，仍保留月光柱影。

新增 Windows 原生 `weather_light_occlusion_smoke`：806個地面點、兩款真 GLB、俯視／斜視，shadow on/off 保留比皆 `100%`；一般 layer1 物件仍遮光，月光仍有柱影。另用實際三個 shader＋halo 對控制牆做冷基準／被擋／移除牆對照：兩款的被擋地面亮度均等於冷基準 `0.059894`、雨絲均等於冷基準 `0.539042`，halo全隱；移除牆後地面約 `0.648`、雨絲 `0.905223`，確認光效仍會發亮。此 smoke 必須用圖形 renderer，不能拿 headless 當影像測量。

### R3-A：演算法與俯視圖，尚未鋪入遊戲

`scripts/weather/export_lamp_geometry.gd` 唯讀匯出主圖實際 Roads/Junctions／Connections 的型別、完整 transform 與碰撞 faces，以及170棟建築的 collision faces。`generate_lamp_plan.py`（Python標準庫，不需pip）合併148個連接模組為72條 edge，以約30m站距兩側交錯；52個路口依實際 outward／pivot 求內角的人行道邊界交點，臂朝路口中心。custom端點讀原 catalog，沒有手寫全圖座標。以實際道路三角形查人行道支撐，並對建築三角形投影做內外與邊距篩選：柱半徑0.18m，柱外緣距建築至少0.5m。高度向上量化到10µm，避免單精度同平面微小穿入，未放寬碰撞檢查。

提案為 **138盞**：94個路口內角、2個直通路口、42個直線段。**略過8處**：D0／L0及其鏡像的4個45°彎道候選無實際人行道支撐；G1_to_G2、Mirror_G1_to_Mirror_G2、N_to_NW、Mirror_N_to_Mirror_NW 共4處距建築不足。逐點來源／朝向／高度、略過原因及既有六燈對應在 `layout/lamp-plan.json`；不把略過列作已放置。

原P3／P5／P6對應提案同座標保留；P1／P2／P4因30m站距提案改由距原點約12.53／6／13m的鄰近演算法燈位取代，明列於 existing_six，供企劃決定是否接受這次重排，未套用原六燈。`validate_lamp_plan.gd` 只重用一盞原型的真 capsule／arm shapes 查全部提案，138個初始 overlap／支撐錯誤皆0；`render_lamp_plan.gd` 輸出含繁中圖例的全圖 PNG。正式原六燈位置與數量目前保持，未執行R3-B。

俯視圖 `round2/layout/lamp-plan.png`，可縮放且有來源 tooltip 的版本為 `lamp-plan.svg`。重現順序為 Godot `--headless --script res://scripts/weather/export_lamp_geometry.gd -- <geometry.json>` → Python `scripts/weather/generate_lamp_plan.py <geometry.json> src/world/roads/custom_catalog.json <output-dir>` → Godot `validate_lamp_plan.gd -- <lamp-plan.json> <validation.json>` → 原生圖形 `render_lamp_plan.gd -- <SVG> <plan.json> <PNG>`。完整命令與來源 hash 留在本機證據，圖與 collision faces 不進Git。

### 第二輪作者驗證與交付邊界

證據根 `artifacts-local/lea212-20261015/round2/`。五支指定 smoke、`weather_headlights_smoke`、四車射擊／受損／切換回歸 `player_rigid_variants_runtime_smoke`，以及上述原生 `weather_light_occlusion_smoke` 均 actual exit0、ERROR0；主圖原生 before／after capture 與 ablation 均 exit0，退出皆有同基底的兩條 texture cleanup ERROR／一條WARNING，完整保留，不宣稱主圖全log ERROR0。R3-A實際形狀查核與規劃重現也通過。

新增 commit 接在9e19e1a後，不amend；主目錄 `playtest/lea212-rain-atmosphere`、素材與cache保全讀回見本機 delivery receipt。只完成本輪作者實作與驗證，停企劃審查，不push／PR／關票，不自行做fresh-context驗收。

新增原 weather smoke 的六盞自身投影檢查；未修產品來源時 `red-weather.log` actual exit1／六個新檢查 FAIL，其餘原檢查 PASS；修正後 `green-weather.log` actual exit0／failures0，兩者 ERROR0。命令為 `<Godot4.7.1> --headless --audio-driver Dummy --fixed-fps 60 --path <隔離專案> --script res://tests/weather_lamp_smoke.gd`，XDG 三目錄獨立置於 `/tmp/lea212-xdg/`。Windows 對照命令沿前述原生入口，改用 `--script res://lea212_capture.gd --resolution 1920x1080 -- baseline`／`-- candidate`；有效兩次 actual exit0／ERROR0。首次 960×720 helper 座標換算錯誤的輸出保存在 `baseline-harness-invalid/` 與 `baseline-console.log`，不作有效證據。

最新封存 Head 的 fresh-context 四原 smoke、weather smoke 與有限來源／證據查核另存本輪 `fresh/`。不以本機修正宣稱原功能全部人驗通過、完整 CI、push、PR、合併或關單；原產品設定與 `.godot` 未交給測試引擎寫入。

## f2a96b3 審查修正：R1 柔暖車燈、R2 正式機位證據、R3-B

本節取代第二輪初稿的車燈參數、六燈數量及三層薄霧；依企劃核可進入 B。只完成作者實作／回歸，交付後停在企劃審查，不自行派驗收、不 push／PR／關票。

R1 四車的既有錨點不動，Spot 改為暖白 `(1,.85,.65)`、energy `2.4`（街燈仍為6）、range20m、俯角16°、半角42°、angle attenuation `.6`、distance attenuation `1.25`，兩盞都開陰影。光束由近地面開始並柔化外緣，沒有加入車模型／材質補光。四車均以正式遊戲相機的相同 basis、正交 size27 拍近景；另有原 F5 與車頭距實際建築約1m的近牆圖。關閉街燈的原生 off/on 量測，沿左右錨點前1.08m的亮度由 `.04854` 分別變為 `.16747/.17111`，之後沿各束方向持續漸弱，前14.58m仍有 `.04574→.04938` 的受光。數據是 PNG 亮度，不是光度學單位；車頭中央前1m尚未落在左右光束交集，不能拿它代替各束的近端樣本。四車跟隨／換車／死亡／卸載條件仍由 smoke 檢查。

R2 正式機位證據位於 `round2-b/formal-occlusion-ground/`。三組保持正式相機 basis／projection，只平移並改 size60，來源是 G2、Mirror_H1、RI 三盞生成燈。`formal-cases-ground.json` 以實體 ray 確認相機到燈被建築遮住、光源到取樣地面被建築遮住、相機到該地面則可見；不以屋頂擋住取樣點的畫面冒充地面測量。每組依序為 `before-mechanism`／`after`／`cold-control`：前者在相同新燈位重現9e19e1a的無陰影 Omni 與原 unshaded 光效，後者使用本輪修正，cold 關該光作控制；其餘街燈與車燈關閉以隔離來源。這是修正前機制的控制重現，不宣稱整張圖來自9e19e1a。路燈 energy6／range22 全程不變，三組被擋 halo 皆隱藏，取樣 after 與 cold 的 PNG 亮度差為 `0 / 0 / .002805`；完整畫面保留供企劃檢查背面、屋頂邊與牆角。

水平 banding 的消去實驗（`banding-diagnosis*`）顯示：放寬倒影方向門檻、移除 film、移除 light attenuation／陰影仍存在條帶；關閉 GroundMist 才消失。原因是三層水平霧片在掠視角形成分層，不是已移除的正弦倒影重新加入。改為一片22×3m、中心高0.8m的柔邊 billboard 低霧，保留深度軟交界與真實 `light()/ATTENUATION` 遮擋。`banding-regression/` 重建原六燈同座標／朝向，在原退回低角度與正式 basis 各拍舊三層／新單層對照；陰影全開、energy6／range22不變。沒有用關光或降低路燈範圍修圖。

R3-B 由200個實際道路模組與170棟建築生成配置，先排路口內角，再排直通及連接道路。全域柱中心最小12m，沿路由相鄰路口燈投影起算30m並交錯；沒有合法 anchor 的兩條 edge 才從 connection 起點起算，記在 JSON。新結果 **69盞**（54內角、2直通、13沿路），實際最小 **12.17651m**；52個候選略過：46個不足12m、4個沒有實際人行道、2個距建築不足。數量下降同時來自去除密集角燈與改為從角燈起算，沒有手動刪座標。原六燈依裁決由新配置取代，逐一對應仍在 `existing_six`。

`generate_lamp_plan.py` 同時輸出完整 `lamp-plan.json/svg` 及只含 pose／來源ID的 `lamp_layout.gd`；將後者複製到 `src/maps/main_battlefield/`，主圖讀此產物建立全部實體。生成產物可逐 byte 重現，未將私有碰撞 faces 納入 Git。`validate_lamp_plan.gd` 對69個姿勢以原 capsule／arm 真實 shape 查核，overlap／支撐錯誤0；遊戲中的69盞也全部通過 standing 檢查。直立時另鎖Y軸以避免 Jolt 在人行道產生約2.7mm的靜置穿入；接觸時解除所有鎖，原倒燈推動、即熄光、5秒等待＋2秒淡出及釋放條件都保持。

光源預算為 **最多8盞街燈＋2盞玩家車燈**，Sun另計。每0.2秒依正式相機下光照球的螢幕投影邊界篩選，優先距地面焦點近者；所有啟用街燈都有陰影。超額或畫外關 Omni／halo／mist，WarmHead emission 保留；倒燈仍立即熄頭並走原生命週期。倒影只上傳8個活躍來源，暖雨由引擎接收實際光源，沒有全圖硬編碼6燈限制。非活躍霧不跑 halo射線，直立燈停用空轉的 physics callback，倒下時恢復計時。

Windows原生 Godot4.7.1／RTX5090／Forward+ Vulkan，同1920×1080、草啟用、VSync1、max_fps0，每機位360 warmup／240 steady。正式 F5 不改 transform／size100，密集街廓沿同 basis 平移至焦點 `(-84,0,-48)`、size100。`Performance.TIME_PROCESS` 為引擎 frame 樣本，非GPU timer，也不推論長時間駕駛成本。

| 240 steady | 9e19e1a median／p95 | 本輪 median／p95 | median差 |
| --- | --- | --- | --- |
| F5 | 17.504／17.551ms | 17.851／18.000ms | +1.98% |
| 密集街廓 | 17.3285／18.744ms | 17.792／18.722ms | +2.67% |

兩機位的240/240幀（100%）均觸及預算：F5候選32、啟用8、關光24；密集街廓候選44、啟用8、關光36。候選包含光照球碰到畫面但柱在畫外者。未發生無陰影仍開光；未承諾所有可見燈頭都有照明。`weather_lamp_budget_smoke` 另跨五個街廓驗證此取捨與遠燈發光頭。

證據根為 `artifacts-local/lea212-20261015/round2-b/`：`layout/lamp-plan.png`、`screens-final/` 四車／近牆／F5／密集街道、上述正式遮擋與banding、`headlight-road-anchor-rays/`、`performance.json`、`smoke/results.json`、`light-effects/metrics.json`。五支指定 smoke＋headlights＋四車runtime＋budget共8支 headless，及1支原生 `weather_light_occlusion_smoke` 皆 actual exit0、ERROR0。原生自遮光806點×兩型×兩機位仍保留100%，控制牆遮光／月光柱影及雨絲受光也通過。native fixture只更新8來源基準、移除雨shader廢棄uniform，光度控制以直接切換真Light隔離FX；原檢查門檻未降低。

主圖原生 capture 全部 exit0，runtime／script／shader ERROR0；退出仍有與9e19e1a相同的兩條 texture cleanup ERROR與一條WARNING，並未算入 smoke 的 ERROR0。helpers、完整原始樣本、來源manifest及主目錄／627素材保全讀回封存本機。工程結果交企劃審查，不代表視覺AC已由作者自行核可。
