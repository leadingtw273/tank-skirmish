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

主路網的預期為 54 junction、72 logical connection、138 physical segment，並檢查
連通性、端點誤差、水平／垂直／45 度方向、180 度 snap-geometry 對稱、1920m floor、
無 GapNotes／Label3D，以及 27.92m 中心線距（12m road width + 15.92m clear space）。

可在發布前檢查指定候選場景：

```sh
# 加在 Godot 指令末尾
-- --candidate=res://path/to/candidate.tscn
```

`--skip-catalog` 僅用於候選主地圖的快速診斷；正常驗收一律掃描完整 catalog。

## 已有證據

root 代跑正常全量驗收（未使用 `--skip-catalog`）已取得 exit 0 與
`road_rebuild_acceptance: PASS`；紀錄在 `artifacts-local/road-full-acceptance.log`。
此證據取代先前因單回合終端時間限制而列為 catalog inconclusive 的狀態。

範圍限制：此驗收不要求不存在的原始 transform 做 bit-identical 比對，也不做跨所有
junction mesh 的任意三角形兩兩碰撞證明。
