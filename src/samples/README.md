# 編輯器取用展示

主地圖：`res://src/maps/main_battlefield/main_battlefield.tscn`。
訓練場：`res://src/maps/training_ground/training_ground_playtest.tscn`。

- `roads/`：8 個原包的模型／合法貼圖變體；`custom_demo` 是最終客製路件；`compact_loop_demo` 示範標準 12m 直路的有限閉環。
- `buildings/full_pack_demo.tscn`：每款模型各一個，不重複展開所有配色。
- `buildings/finished_demo.tscn`：完整建築與配色；`base_demo`、`parts_demo`、`materials_demo` 分別為基底、零件與原始材質版。
- `buildings/2story_wide_colors_demo.tscn`：同款雙層寬建築，原材質版加 12 種貼圖。
- `tanks/tank_variants_demo.tscn`：4 個完整坦克場景。展示的 `Tanks` 容器停用執行；個別坦克複製出去仍繼承新父節點的正常執行狀態。

開啟主圖與展示兩個分頁，在展示的 `Models` 下選取整個模組根節點（不要只選 Mesh），複製後切回主圖，選 `Buildings` 或 `Roads` 貼上。
道路／建築根節點帶靜態碰撞。道路拖曳時按住**右 Alt**吸附最近且朝向相容的接點；先自行旋轉到需要的角度。多選保持相對位置，不會自動旋轉整組。

主地圖不要複製展示相機、燈光或標籤。F6 執行目前場景；F5 執行專案入口。
坦克貼地、上坡與橋面行駛另屬 LEA-176，本次靜態道路碰撞不代表該功能已完成。

原始下載內容位於 `assets`，客製與含碰撞的模組位於 `src/world`；展示集中本目錄。
付費道路及大型衍生模型在本機保存，不公開推送；完整使用請採專案離線備份，不要只複製 Git 工作樹。
