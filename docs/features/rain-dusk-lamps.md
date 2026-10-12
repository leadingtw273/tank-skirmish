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
