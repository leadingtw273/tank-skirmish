# 建築朝向對齊

需求：修正相鄰建築的朝向角度偏差，保留布局與原尺寸；斜向街區沿 45° 排列。

- 處理共 170 棟；98 棟原朝向偏差超過 0.001°，最大約 2.9363°。
- 朝向調整為最近的 45° 倍數；兩棟對稱建築原有約 0.075°／0.279° 的輕微俯仰／側傾一併扶正。
- 只改建築根節點 basis，保留 position、scale 及 PackedScene 引用。不調建築間距、不拉伸模型，不修改道路。
- 原場景備份：`artifacts-local/main-before-building-angles-20260921.tscn`。
- 候選：`artifacts-local/main_battlefield_building_angles_v1.tscn`，同名 PNG 為渲染預覽。
- 逐棟修改清單：`artifacts-local/building-angle-changes-v1.json`。

獨立驗收 PASS（Godot exit 0）：170 棟名稱／PackedScene 引用、位置與尺寸不變；朝向對齊、俯仰及側傾歸零；79 對副本維持 180° 相對變換；其他非建築節點的結構、Transform 與場景引用不變。證據腳本 `/tmp/accept_building_angles.gd`，輸出 `PASS: AC1/AC2/AC3 satisfied`。已發布至主圖，待使用者視覺驗收。
