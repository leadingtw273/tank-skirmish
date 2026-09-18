# Ghost Town road-layout trace

Machine-readable topology: [road-layout-trace.json](road-layout-trace.json).

The JSON is a centreline graph in the 724×717 reference-image coordinate system. It contains only the top half; generate the lower half with `mirror(x,y) = (728-x, 712-y)` and duplicate every edge with the `m_` identifier prefix. This gives the specified 180° rotational symmetry about approximately `(364,356)`, rather than a left/right mirror.

## Generation rules

- Join every listed edge as a continuous road despite the yellow `Gxx` source gaps. Those labels mark the unextended state of the screenshot, not intentional breaks.
- Keep segments horizontal, vertical, or at 45°. The trace snaps endpoints modestly where screenshot perspective, labels, and road caps made the original pixels imprecise.
- `diamond_n → diamond_w → mirrored(diamond_n) → diamond_e → diamond_n` is the central diamond ring. It intentionally has no road through the gizmo at the centre.
- The red-circled left and right passages are two separate parallel centreline chains. Their centreline separation is about 26–27 px (twice the ordinary narrow passage spacing); do not turn either into a thicker road.
- `open` nodes are map-boundary entrances/exits. A geometric line crossing is a junction only when the JSON explicitly gives it a shared node.

## Trace caveats

This is a reconstruction from the annotated raster, not original authored coordinates. The reliable macro-topology is the outer U loops, connected upper block grid, central diamond, and paired narrow side passages. Small upper-grid block-side stubs are the least certain portion because labels/line caps overlap them; they were intentionally omitted rather than guessed into extra intersections.
