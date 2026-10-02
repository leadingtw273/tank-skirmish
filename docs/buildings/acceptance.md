# LEA-177 建築與坦克展示驗收

驗收日期：2026-09-18

## 結果：PASS

以 Godot 4.7.1 headless 執行，並設定
`XDG_DATA_HOME=artifacts-local/xdg/data`：

```text
tests/building_samples_smoke.gd      BUILDING_SAMPLES_SMOKE failures=0
tests/building_layout_acceptance.gd  BUILDING_LAYOUT_ACCEPTANCE failures=0
```

`building_layout_acceptance.gd` 額外逐條檢查：

- catalog 有 938 個唯一 wrapper；每個均為 `StaticBody3D`，具有 visual 和
  `ConcavePolygonShape3D`，且同 index 的 transform 相等。
- 五個展示場景數量為 full_pack 102、finished 312、base 216、parts 384、materials
  26，模型 XZ origin 不重複。
- `2story_wide_colors_demo` 含原始 `Material_Default` 與 12 個同造型 palette；
  palette 的 sampled albedo 影像指紋皆不同，且 `Material_Default` 具有非白色
  albedo，不是白色 fallback。
- tank demo 外部引用 tank1 至 tank4；僅 `Tanks` 容器停用 process，四個 tank
  root 維持 inherit。
- 每個建築 preview camera 向下指向 `Models` 的 XZ 邊界，並具 PreviewEnvironment
  ambient light，重建後展示場景數量與材質驗收仍通過。

Blender 4.5.12 的唯讀原始 Blend audit 亦確認：32 個 `parts` Blend 的每個材質皆
為 `use_nodes=true` 且各含一個有效 image node，因此不會走「缺 image 仍輸出灰白」
路徑；26 個 `materials` Blend 的材質皆為 `use_nodes=false`，而 focus demo 的原始
`Material_Default` 已以非白色 albedo 實測通過，證明 exporter 保留其 legacy material。

基線保護：相對 `e1b9c5b`，舊 `assets/models/buildings` 與 `src/actors/tank` 無差異。
