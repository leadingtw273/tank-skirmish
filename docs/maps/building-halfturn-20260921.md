# 建築中心對稱複製

使用者確認：來源為已擺好的左上／外圍街區；中央菱形內建築保持原樣，外圍旋轉 180° 複製到另一半，不使用負縮放，不移動原建築或道路。

- 修改前場景：`artifacts-local/main-before-building-mirror-20260921.tscn`，91 棟。
- 中央菱形：以地圖中心為原點，建築位置 `abs(x) + abs(z) < 48m`，12 棟保留、不複製。
- 外圍：79 棟各產生一個 `Rot180_` 副本；位置 `(x,y,z) → (-x,y,-z)`，世界旋轉繞 Y 軸增加 180°，保留原模型、材質、碰撞及縮放。
- 候選：`artifacts-local/main_battlefield_building_mirror_v1.tscn`，共 170 棟。
- 對照清單：`artifacts-local/building-mirror-v1.json`；同名候選 `.png` 為實際渲染。
- 預檢未發現副本落在既有建築相同位置。此處不宣稱檢查任意建築體積互相碰撞。

驗收：fresh-context 載入兩場景，確認 91 個來源 Transform／PackedScene 引用不變、79 個副本為 Y180 且縮放不變、中央 12 個無副本。通過有限驗收；未逐一展開比較每個 PackedScene 的材質／碰撞子樹，來源與副本皆保留同一場景引用。

另跑非建築節點核對：`NONBUILDING_UNCHANGED []`，exit 0，確認結構、場景引用與 Transform 不變。發布回傳 `PUBLISH_MAIN_RESULT code=0`，發布前備份 `artifacts-local/main-before-publish-1789970946.tscn`。此紀錄不代表使用者已完成視覺驗收。
