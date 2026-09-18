# 地圖目錄配置

`src/main.tscn` 載入 `src/maps/main_battlefield/main_battlefield.tscn`。這是目前遊戲的主地圖：根節點為 `World`，地面與碰撞範圍皆為 1920×1920，保留既有天空與光照參數；`Roads` 存放重建路網，`Buildings`、`GrassField` 留空供手工擺放。

舊有城鎮布局保存在 `src/maps/archive/town_layout/town_layout.tscn`，連同其道路元件，供參考或日後取用，不會由主入口載入。

訓練場入口是 `src/maps/training_ground/training_ground_playtest.tscn`。其資源按責任分類：`environment/` 放地面與網格、`navigation/` 放導航資源、`encounter/` 放靶車與遭遇控制、`range/` 放射擊場、`debug/` 放視野預覽。可重用的草地與區域資源持續位於 `src/world/`。

搬遷後先由 root 統一執行 Godot import，再可執行：

```sh
godot --headless --audio-driver Dummy --path . --script res://tests/training_ground_smoke.gd
godot --headless --audio-driver Dummy --path . --script res://tests/map960_components_smoke.gd
```
