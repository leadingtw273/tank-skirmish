# 道路吸附外掛

`addons/road_snap` 已在本次復原工程的 `project.godot` 啟用，可於「專案 → 專案設定 → 外掛」檢查 Road Snap。

## 模組介面

```text
StaticBody3D  (metadata: road_module = true; optional road_id, variant)
└── SnapPoints (Node3D)
    ├── AnyMarkerName (Marker3D)
    └── AnotherMarkerName (Marker3D)
```

Marker 名稱不參與優先度。位置使用模組局部座標，全域 `-Z` 軸是接點外向方向；內外接點可共存於 `SnapPoints`。Road12 的接點安裝平面在 y=0，網格／碰撞刻意下降0.015m，吸附不會抵消這個降低量。

## 操作

選取道路模組或含道路的 Node3D 群組，以一般3D工具拖曳並按住**右 Alt**。範圍內最近且朝向相容的外部接點勝出；不吸附自己或其他已選道路。外掛不自動旋轉，先自行對好角度。

左 Alt 不啟用吸附；不按右 Alt 保留一般移動。多選只平移最上層選取節點，維持子物件相對位置與旋轉。放開滑鼠後，外掛延至idle、原生移動提交之後，加入獨立的 `Snap Road Modules` Undo/Redo 歷史；只更動此次選取節點，不更動目標道路。

編輯器設定內可調 `road_snap/snapping/radius_meters`（預設1.25m）及 `road_snap/snapping/opposing_angle_tolerance_degrees`（預設8°）。兩端外向方向需近乎相反；符合者一律選最近點，沒有內外模式按鈕。

## 驗證與限制

匯入後可執行：

```sh
godot --headless --path . --script res://tests/road_snap_solver_smoke.gd
```

實測輸出：`road_snap_solver_smoke: PASS`；外掛解析測試也通過。

`tests/road_snap_editor_undo_smoke.gd` 是 EditorScript，可從腳本編輯器執行。隔離 headless Editor 以真實 EditorUndoRedoManager 驗證release排序與Undo/Redo：`road_snap_editor_undo_integration: PASS`。

仍需在 Windows Godot 手動驗收：右 Alt 拖曳單個道路／多選／含子道路的群組、左 Alt 不吸附、內外接點切換、放開後不再跳動，以及原生移動工具的Undo/Redo。隔離測試不能冒稱已驗證原生GUI輸入。
