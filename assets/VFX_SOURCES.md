# 第三方 VFX 來源

本目錄只保存 Tank Skirmish 目前實際使用的兩個效果及其直接依賴，不包含作者的展示專案或完整素材包。

## Binbun Muzzle Flash VFX

- 來源：https://binbun3d.itch.io/muzzle-flash-vfx
- 授權：作者頁面標示 CC0，可用於個人、教育與商業用途，無需署名。
- 本專案使用：`assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_01.tscn`
- 取得日期：2026-08-24

## Binbun Impact VFX Demo

- 來源：https://binbun3d.itch.io/impact-vfx
- 授權：作者頁面標示 CC0，可用於個人、教育與商業用途，無需署名。
- 本專案使用：免費 Demo 內的 `assets/GodotImpactVFX/effects/hit/vfx_hit_01.tscn`
- 取得日期：2026-08-24

## 匯入政策

- 只保留上述兩個場景實際引用的 script、shader 與 texture。
- 不複製作者專案的 `.import`、`.uid` 或 `.godot/imported/`；由本專案鎖定的 Godot 4.7.1 重新產生必要 sidecar。
- 兩包原本重複的 VFX controller／light script 統一使用 `assets/BinbunVFX/shared/script/`，避免重複 UID 與維護分岔。
