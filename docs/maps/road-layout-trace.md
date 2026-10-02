# Ghost Town road-layout trace

Machine-readable topology: [road-layout-trace.json](road-layout-trace.json).

## 2026-09-18 使用者驗收修正

2026-09-21 紅線內彎加大：右上 `G3` 由 x=36 移到 30（仍在 z=-96 外側直線上），`D0`／`D1` 由 z=-72 移到 -66；斜段維持 45°、路件不縮放。左下同步旋轉 180°；外側道路線形與其餘路口不變。

外側 U 彎採「特殊路件先定形、直路補長度」：左上固定 `UL1=(-132,-132)`、`UL4=(-84,-132)` 兩個原生 90° 彎道，中間水平連接；刪除原先 `UL2`／`UL3` 及斜直路。右下旋轉 180° 生成；不改綠線連接或其餘路口。

下列像素 trace 保留作歷史參考，不再作為側邊路口的最終規格。依使用者 21:24 綠線／紅叉圖：移除前版四條中段橫路，保留原本端部連接，只於兩側外彎各加一條向內橫路。左側 `L1`（-111.92,-38）以 Y 字三叉接 `LJoin`（-84,-38）的 T 字路口；右側由 180° 旋轉產生。彎道平移 4.08m、維持原 45°，讓內側 T 與鄰接路口有足夠空間，不重疊。維持 27.92m 中心距／15.92m 淨距，不增加向地圖外的死路。最終公尺座標與連接以生成器及 [main-road-layout.json](main-road-layout.json) 為準。

The JSON is a centreline graph in the 724×717 reference-image coordinate system. It contains only the top half; generate the lower half with `mirror(x,y) = (728-x, 712-y)` and duplicate every edge with the `m_` identifier prefix. This gives the specified 180° rotational symmetry about approximately `(364,356)`, rather than a left/right mirror.

## Generation rules

- Join every listed edge as a continuous road despite the yellow `Gxx` source gaps. Those labels mark the unextended state of the screenshot, not intentional breaks.
- Keep segments horizontal, vertical, or at 45°. The trace snaps endpoints modestly where screenshot perspective, labels, and road caps made the original pixels imprecise.
- `diamond_n → diamond_w → mirrored(diamond_n) → diamond_e → diamond_n` is the central diamond ring. It intentionally has no road through the gizmo at the centre.
- The red-circled left and right passages are two separate parallel centreline chains. Their centreline separation is about 26–27 px (twice the ordinary narrow passage spacing); do not turn either into a thicker road.
- `open` nodes are map-boundary entrances/exits. A geometric line crossing is a junction only when the JSON explicitly gives it a shared node.

## Trace caveats

This is a reconstruction from the annotated raster, not original authored coordinates. The reliable macro-topology is the outer U loops, connected upper block grid, central diamond, and paired narrow side passages. Small upper-grid block-side stubs are the least certain portion because labels/line caps overlap them; they were intentionally omitted rather than guessed into extra intersections.
