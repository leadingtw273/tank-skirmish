# 自訂道路模組

`scripts/roads/build_custom_roads.gd` 產生 `custom_catalog.json` 與
`generated/custom/` 的 scene。它只讀 Atomic Realm 的 GLB，不會覆寫來源檔；
碰撞則由道路 sample builder 統一建立。

## Curve2 45°

Curve2 的中心線半徑是 24m、轉角 45°、弧長 `6π`m。入口為
`(0, 0, -6)`、outward `-Z`；出口為
`(7.029437, 0, 10.970563)`、outward `(√½, 0, √½)`。

生成器將原 `Road1.glb` 的每個三角形按原本 `z=-6..6` 的 12m 模組切成
32 片，插值原 UV 與法線後映射到圓弧。完整 12m 重複原網格；最後不足
12m 的部分裁切，不拉伸虛線或路肩。

## Y 接點

`Road11_Y_Splitter_45_Custom` 的 stem 從來源 south `z=-6` 裁至 `z=3`；兩個
斜支保留原端面。`Road12_Diagonal_Splitter_{L,R}_Custom` 將 north 與 diagonal
裁至法向距離 `14.485281m`，保留南端 `z=-6`。裁切三角形保有來源材質、UV、
路肩高度與法線；新的垂直端蓋不改變上表面。L/R 都是獨立烘焙網格，不使用負
scale。

Road12 視覺 mesh（以及 root 後續統一產生的 collision）維持 `y=-0.015`，但
全部 SnapPoints 在 `y=0` 安裝平面，避免吸附時抬升交匯。實測 diagonal cap
中心有原始幾何造成的橫向偏差：L outer `(10.259273, 0, 10.226008)`，R 為
x 鏡像；inner 再沿 outward 回退 3m。這些實際中心寫入 catalog，主模板可用
virtual pivot 對齊接線軸。

不使用特殊直線長度的有限閉環可採半環中心對稱：半環走兩個同向 45° Y
支路、再走一個 90° corner，第二半是它的 180° 旋轉副本。若半環（含所有
標準 12m 直線）位移為 `V`，副本就是 `-V`，因此精確閉合；半環及副本各轉
180°，總轉角為 360°。小型案例使用四個 Road11_45、兩個 corner 與四段
12m 直線；大型案例以四個 Road12 L（R 是鏡像）取代，使用十二段 12m
直線。這是削角的梯形／菱形環，非八個 45° curve 的平凡環。

## 驗證

先由 root 統一完成 Godot import，再執行：

```sh
godot --headless --path . --script res://scripts/roads/build_custom_roads.gd
godot --headless --path . --script res://tests/custom_roads_smoke.gd
```

第二個命令會檢查四個來源 GLB 的 SHA-256、四個 custom scene、Curve2 解析
端點、Road12 inner/outer snap、沒有自帶 collision 與沒有負尺度 mesh。
