# LEA-177 Quaternius 原始素材 manifest

本目錄的原始素材只取自 Quaternius 官方公開的 Ultimate Textured Buildings
Pack（2019-12、CC0）。本單不得以自行建模或其他來源替代。

- 官方 pack 頁：<https://quaternius.com/packs/ultimatetexturedbuildings.html>
- 公開 Drive root：`1RE3qXhbE5yGS3t-xGFJ8GmOtTgCUF3LQ`
- Textured Models：`1Vp2OEjEOpD65VlEVjmBjHGdCfZrcnih8`
  - `base/`：18 個 Blend（Base Modular Buildings / Blends：`1-ICvu5fXhGEoRpKY-qDZEFmxa_SBgSKv`）
  - `parts/`：32 個 Blend（Base Modular Parts / Blends：`1MiSvtRDJ_OakZxFBFXuLLfxIDyscKZS_`）
  - `finished/`：26 個 Blend（Finished Textured Buildings / Blends：`1W7w8v07eTBs1loslljfDH7hQJ28u-L5S`）
  - `textures/`：12 個官方 palette PNG（Textures：`1wk3RXizRZpkedxBvI1KUJmZ7O4Hh3kzm`）
- Models with Materials：`1eRF5EE1Z0_e4FwQfI0sdDNRzYvzHUADr`
  - `materials/`：26 個 Blend（Blends：`11hapfhThfMp0A62CnOvlqEvshzKQ5AEj`）

下載格式為 `https://drive.usercontent.google.com/download?id=<fileId>&export=download&confirm=t`。
所有已納管檔案及雜湊記錄於
[`assets/QuaterniusBuildings/SHA256SUMS`](../../assets/QuaterniusBuildings/SHA256SUMS)。

## 完整性基準

| 分類 | 應有檔數 | 本次來源 |
| --- | ---: | --- |
| base | 18 | 官方 Blend 子資料夾 |
| parts | 32 | 官方 Blend 子資料夾 |
| finished | 26 | 官方 Blend 子資料夾 |
| materials | 26 | 官方 Blend 子資料夾 |
| textures | 12 | 官方 Textures 子資料夾 |

`finished/2Story_Wide.blend` 的 SHA-256 必為
`1ab9dcd34fa365dc23eb6ff298893f15160a1adb5ae52866f1ac8dee694d48e8`，並與既有
[`docs/assets/quaternius-lock.json`](../assets/quaternius-lock.json) 的官方來源 lock 相符。

原始 Blend 以各分類資料夾的 `.gdignore` 排除 Godot import；palette PNG 保持可匯入。
