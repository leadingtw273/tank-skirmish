# Binbun 戰鬥 VFX 來源與整合紀錄

本專案保存 Binbun 的完整 Muzzle Flash、Impact VFX、Magic Projectiles，
以及 Supporter／Green Extra 中不重複的內容。這些素材只作為資料匯入，
未執行下載包內的任何腳本或指令。

## 官方來源與授權

| 素材包 | 官方頁面 | 授權 | 取得日期 |
| --- | --- | --- | --- |
| MuzzleFlashVFX | https://binbun3d.itch.io/muzzle-flash-vfx | CC0 | 2026-08-27 |
| SupporterExtraTextures（Muzzle supporter extra） | https://binbun3d.itch.io/muzzle-flash-vfx | CC0 | 2026-08-27 |
| ImpactVFX | https://binbun3d.itch.io/impact-vfx | CC0 | 2026-08-27 |
| MagicProjectilesVFX | https://binbun3d.itch.io/magic-projectiles-vfx | CC0 | 2026-08-27 |
| GreenExtra（Magic supporter extra） | https://binbun3d.itch.io/magic-projectiles-vfx | CC0 | 2026-08-27 |

官方頁面標示可用於個人、教育與商業用途，且不要求署名。

## 下載封存雜湊

| 原始封存檔 | SHA-256 |
| --- | --- |
| `MuzzleFlashVFX.zip` | `58349d3f578caa5e9723b21b2ccf30f07a7913b9c3c2d47891cac722b942ca31` |
| `SupporterExtraTextures.zip` | `59fad069d782605359ac6801299c39843f9140daf3c17262b214fc78a419f21e` |
| `ImpactVFX.zip` | `0b2c90325160351e8f7060337a78061e79762a8c5dc32ae0984004eca170734b` |
| `MagicProjectilesVFX.zip` | `821fdada7d111bc05a0014734b3b76af3a40b84e568372ad47ddc8990bcde78d` |
| `GreenExtra.zip` | `47f5378c4bc91911f066d491ccca2144619c4d7bc71f228ef1cc5e068a3399ee` |

原始 ZIP 不提交到 repository；上表用於日後比對使用者持有的來源封存。

## Repository 內容

- `assets/BinbunVFX/muzzle_flash`：24 個效果（Big、Muzzle、Short、Wide 各 6）。
- `assets/BinbunVFX/impact_explosions`：7 個 explosion、7 個 impact、10 個 hit，
  展示入口為 `assets/BinbunVFX/impact_explosions/main.tscn`。
- `assets/BinbunVFX/magic_projectiles`：主包 12 個效果，並加入 Green Extra 的
  `m_projectile_basic_vfx_05.tscn`、`m_projectile_javelin_vfx_05.tscn`、
  `mprojectile_wave_vfx_05.tscn`；展示入口為
  `assets/BinbunVFX/magic_projectiles/magic_projectiles_scene.tscn`。

Green Extra 除上述三個 05 場景外與 Magic 主包相同，因此不保留獨立
`GreenExtra` 根目錄，也不覆蓋主包的 01～04。

## Shared 合併裁決

- Canonical 共用根目錄為 `assets/BinbunVFX/shared`。
- 三個主包原本就以 `res://assets/BinbunVFX/shared/...` 引用共用資源。
- `vfx_controller.gd` 採 MuzzleFlashVFX 較新的版本；其 `one_shot` setter
  會在 editor 判斷前先執行 `one_shot = value`。
- `vfx_light.gd` 與內容相同的 shared texture 只保留一份。
- Supporter Extra、Muzzle 與 Impact 的 flare PNG 位元內容相同，只保存於
  `assets/BinbunVFX/shared/texture/flare`，沒有複製第二份。

## Tank Skirmish 目前選用

- 槍口火焰：`assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_05.tscn`
- 槍口火焰 scale：`4.0`
- 坦克視覺後座距離：`0.36`
- 命中特效：`assets/BinbunVFX/impact_explosions/effects/hit/vfx_hit_01.tscn`

舊的裁剪路徑 `assets/GodotImpactVFX` 已遷移到作者原生
`assets/BinbunVFX/impact_explosions`；目前沒有把 Magic Projectile 接到遊戲砲彈。
