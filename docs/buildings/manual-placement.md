# LEA-177 手動取用對照

所有可手動擺放的建築都是 `StaticBody3D` wrapper；視覺模型與每一個 mesh 的
`ConcavePolygonShape3D` 碰撞已一同封裝。請從下列路徑拖入場景，而非直接拖
`assets/QuaterniusBuildings` 的原始 Blend。

| 用途 | wrapper 路徑樣式 | 可用數量 | demo |
| --- | --- | ---: | --- |
| 完整貼圖樓 | `src/world/buildings/quaternius/items/finished/<palette>/<name>.tscn` | 26 × 12 | `src/samples/buildings/finished_demo.tscn` |
| 模組化樓體 | `src/world/buildings/quaternius/items/base/<palette>/<name>.tscn` | 18 × 12 | `src/samples/buildings/base_demo.tscn` |
| 門窗、管線、招牌等零件 | `src/world/buildings/quaternius/items/parts/<palette>/<name>.tscn` | 32 × 12 | `src/samples/buildings/parts_demo.tscn` |
| 原廠 material 對應樓 | `src/world/buildings/quaternius/items/materials/default/<name>.tscn` | 26 | `src/samples/buildings/materials_demo.tscn` |
| 全套預覽 | 上列 `light` palette + materials/default 的既有 wrapper 引用 | 102 references | `src/samples/buildings/full_pack_demo.tscn` |
| 同型配色比較 | `2Story_Wide_Mat` + 12 個 `finished/<palette>/2Story_Wide` wrapper | 13 references | `src/samples/buildings/2story_wide_colors_demo.tscn` |
| 四車外觀擺放 | 四個既有 Tank variant 的外部 scene 引用 | 4 references | `src/samples/tanks/tank_variants_demo.tscn` |

`TankVariantsDemo/Tanks` 容器只為 sample 設為停用處理；四個 Tank 根節點保持
`PROCESS_MODE_INHERIT`。把其中任何 Tank instance 複製到主場景後，會繼承主場景
的正常處理模式，不會保留 sample 的禁用狀態。

## 命名與 palette

`<palette>` 固定為：`blue`、`casino`、`dark`、`darkblue`、`darkpurple`、`green`、
`grey`、`light`、`light2`、`red`、`signs`、`yellow`。`light` 是 official default
atlas 的對應版本；full-pack demo 不再新增一份 GLB，而是引用既有 `light` wrapper。

原始官方 `.blend` 與 palette PNG 的來源、雜湊及重新下載位置見
[quaternius-source-manifest.md](quaternius-source-manifest.md)。重新產生 wrappers 與
sample 可在 root 已完成 GLB import 後執行：

```sh
Godot --headless --path . --script res://scripts/buildings/build_quaternius_samples.gd
```

僅重建不帶 AI/physics 處理的坦克 sample：

```sh
Godot --headless --path . --script res://scripts/buildings/build_quaternius_samples.gd -- --only-tanks
```
