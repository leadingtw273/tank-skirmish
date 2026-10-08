# 主地圖空地草皮（LEA-209）

leadi 要求主地圖建築與道路間的小空地，以及建築群外露地面補草地，並於 2026-10-08 選定「偏自然的灰綠草地（建議）」。工單為 [LEA-209](https://linear.app/leadingtw273/issue/LEA-209/主地圖建築道路間與街區外空地補草皮)，人驗 pending。

基線為已合併 PR #129 的 `main 590c80177125bd8f86acc273954d5f3d4b1d9d2d`，tree `1519636493b8e5a16d4cb13aa652a9f943f4131d`。本輪計畫 SHA-256 `23f12db1f907d7ec30f95bce28258f409c2a43678ac656c14eb0756f85c1220b` 的平台原生隔離第二模型審查 approve／0 blocker；Claude 外送審查被平台拒絕，沒有有效 Claude 結果，不重試外送。

## 有限實作與保持條件

GroundMaterial 改用專案自有不透明 `ground_grass.gdshader`。兩個灰綠色與 `patch_size_meters` 可在 Inspector 調整；預設 12m 主斑駁與其 3 倍頻率的柔和細色差。座標取 `MODEL_MATRIX` 轉換後的世界 XZ，色差固定於地面，保留一般 PBR 受光／陰影與 roughness 0.92。

Ground 尺寸／transform／collider、200 道路、170 建築、Navigation、坦克遮蔽與射擊／移動、正式相機及 Environment 原 source 資料保持。這是平面草皮，不新增草株、風動、透明 pass 或地形位移，也不改既有私有素材。新增 shader companion UID 為 Godot 生成的 `uid://cb2d0xawr4aql`；237 原 UID bytes／metadata 與 586 ignored 私素材 metadata、原快取與正式來源保持。

## 固定驗收點

| 視角 | 驗證相機 | 檢查 |
| --- | --- | --- |
| F1 出生街區 | rig XZ=(-108,-114)，原斜俯視、size100、1920×1080 | 出生旁小空地草底，道路、人行道與入口可辨識。 |
| F2 中央街區 | rig XZ=(0,0)，原斜俯視、size100、1920×1080 | 中央建築與道路間草底，原建築淡出後仍有完整底面。 |
| F3 全街區 | (0,320,0.01)，正交俯視、size320、1500×1200 | 建築群外露地面草底，原路網輪廓與入口空間可辨識。 |

固定相機僅位於本機驗證 fixture，正式相機未改。用 Godot 開啟本輪工程交付的 `project.godot`，F5／`res://src/main.tscn` 即可親測；配色與自然場地觀感仍待 leadi。

## 作者有限證據與限制

Windows 原生 Godot 4.7.1、Vulkan Forward+／RTX 5090 的 baseline／candidate 同視角三張 PNG 均保存成功，兩段 CLI actual exit 0；擷取 runtime ERROR0／WARNING0。兩段在 `GRASS_CAPTURE_DONE` 後均出現同樣 2 ERROR／1 WARNING 的 Texture RID leak／ImageTexture renderer shutdown 訊息，raw 留存，不稱整份 log 無錯誤。

原 `res://tests/main_ground_visual_smoke.gd` actual exit 0／ERROR0／WARNING0，visible／collision AABB 對齊且三點 ground ray 命中 y=0。原 `res://tests/map960_components_smoke.gd` actual exit 0／ERROR0／WARNING0，僅為歷史元件回歸。主 scene 去除唯一 Ground 材質區與新增 resource 引用後，基線／候選 bytes 一致；其他原產品 source bytes 保持。

作者本機證據存於本輪 `tank-main-grass-20261008/{baseline,candidate,preparation}`，含實際命令／退出碼、renderer／相機 receipt、PNG SHA-256、原 UID／素材／快取守衛與 scene 不變式。初輪新增 UID 尚未進入 copied cache 的 text-path fallback WARNING 已保留；最終沿原 sky 的 path-only resource 引用，新增 companion UID 保留，最新 runtime WARNING0。

作者自驗不代替 fresh-context 驗收。本輪沒有執行完整 75 命令 quality／新網路私素材 CI、PR、push、合併正式來源或外送 PNG／素材；候選獨立審查與正式本機交付由 root 後續核對，人驗仍 pending。
