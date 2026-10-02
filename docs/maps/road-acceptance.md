# 道路重建驗收

在 repository 根目錄執行（demo round-trip 暫存檔寫入 `/tmp`）：

```sh
XDG_DATA_HOME="$PWD/artifacts-local/xdg/data" \
  /home/markchou/.cache/tank-skirmish/toolchains/godot/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64 \
  --headless --path "$PWD" --script res://tests/road_rebuild_acceptance.gd
```

驗收腳本會實例化 catalog 的所有道路模組（目前 598 個），確認每個場景的
`StaticBody3D`、visual mesh 與 trimesh collision；也會保存並重載八個 base
demo 與 custom demo。主地圖的接縫則由已變換的 `Marker3D` snap point 重新推導，
不採用 `main-road-layout.json` 作為幾何證據。

主路網的預期為 52 junction、72 logical connection、148 physical segment，並檢查
連通性、端點誤差、水平／垂直／45 度方向、180 度 snap-geometry 對稱、1920m floor、
無 GapNotes／Label3D，以及 27.92m 中心線距（12m road width + 15.92m clear space）。
另逐一檢查綠線兩個外側 Y、兩個內側 T 路口及兩條橫向連接；紅叉四條舊橫路須不存在，原內側路口恢復 T。
左上與右下 U 彎各固定兩個原生 `Road10_90angle_Corner`，只用水平直路連接彎道；禁止恢復 `UL2`／`UL3` 舊斜邊。

可在發布前檢查指定候選場景：

```sh
# 加在 Godot 指令末尾
-- --candidate=res://path/to/candidate.tscn
```

`--skip-catalog` 僅用於候選主地圖的快速診斷；正常驗收一律掃描完整 catalog。

## 2026-09-21 內彎加大版（目前主圖）

`artifacts-local/main_battlefield_inner_bends_v1.tscn` 經 fresh-context 布局驗收 `road_rebuild_acceptance: PASS`，exit 0（`--skip-catalog`，只改布局）。右上／左下內側彎路各向內移 6m，新增具名 T 路口位置斷言，原有幾何、對稱、U 彎與綠線測試保留。同名 `.png` 為實際渲染預覽。已發布，前版備份 `artifacts-local/main-before-publish-1789956565.tscn`；加大幅度待使用者確認。

## U 彎路件先定形版（內彎加大前）

`artifacts-local/main_battlefield_u_corners_v1.tscn` 經 fresh-context 布局驗收 `road_rebuild_acceptance: PASS`，exit 0。額外實際 Marker 查驗：左右兩組水平連接各三段，端點與原生 90° 彎精確重合、朝向相反；同名 `.png` 為渲染預覽。其餘路口座標與綠線版完全相同。已發布，前版备份 `artifacts-local/main-before-publish-1789744005.tscn`；布局仍待使用者確認。本次只調布局，使用 `--skip-catalog`，素材全量驗收沿用前輪未修改的來源。

## 綠線版驗收（U 彎修正前）

依 21:24 使用者標記修正，候選 `artifacts-local/main_battlefield_green_links_v1.tscn` 經 fresh-context 完整測試輸出 `road_rebuild_acceptance: PASS`，log：`/tmp/lea177-green-accept-road.log`。同名 `.png` 為實際渲染。已發布至主圖，`PUBLISH_MAIN_RESULT code=0`，前版備份：`artifacts-local/main-before-publish-1789742669.tscn`。待使用者驗收位置；不沿用前版四條橫路。

## 前版側邊橫路驗收（位置後經使用者紅叉否決）

2026-09-18 側邊橫路修正版：fresh-context 驗收執行完整 catalog 與候選場景檢查，exit 0，`road_rebuild_acceptance: PASS`。候選為 `artifacts-local/main_battlefield_side_t_v1.tscn`，實際渲染預覽同名 `.png`。發布回傳 `PUBLISH_MAIN_RESULT code=0`，發布前主圖備份為 `artifacts-local/main-before-publish-1789737571.tscn`。本次不代表使用者已簽核布局。

## 原版已有證據（補側邊橫路之前）

root 代跑正常全量驗收（未使用 `--skip-catalog`）已取得 exit 0 與
`road_rebuild_acceptance: PASS`；紀錄在 `artifacts-local/road-full-acceptance.log`。
此證據取代先前因單回合終端時間限制而列為 catalog inconclusive 的狀態。

範圍限制：此驗收不要求不存在的原始 transform 做 bit-identical 比對，也不做跨所有
junction mesh 的任意三角形兩兩碰撞證明。
