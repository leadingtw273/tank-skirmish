# Binbun Godot Grass provenance

## Source and license snapshot

- Author: Binbun
- Official source: <https://binbun3d.itch.io/godot-grass>
- Downloaded: 2026-02-07
- Archive: `GodotGrass-source.zip`
- Archive SHA-256: `49603c3da773708108c2bbd8937c4caff0447c9a3d775ffd75d65dba3517f060`
- License: CC0 1.0 Universal / Public Domain Dedication
- License evidence: the official source page identifies the asset license as
  Creative Commons Zero v1.0 Universal and states that the pack may be used for
  personal, educational, and commercial projects without attribution.

## Imported source-code subset

The private `godot-grass` cache archive was verified against the stated SHA-256
before import. Only the following byte-for-byte copies from
`source/assets/BinbunGrass` are included; the demo scene, ground shader/material,
atlas, XCF source, other textures, and full presets are excluded.

| Repository file | Source SHA-256 |
| --- | --- |
| `assets/BinbunGrass/shader/grass.gdshader` | `46d46ce8ac4f90732686074aaddd5d17c0802252376e135bf5157c33f9f3be63` |
| `assets/BinbunGrass/shader/grass.gdshader.uid` | `8c9e12e8ef9048f56f5c72596a8b2fe2f9f061ea4939c539ddfa42a2d05e8fca` |
| `assets/BinbunGrass/shader/util/dither.gdshaderinc` | `2442617abb5de689075c18ea4fe72462ca063a12da938fdd2fbe39eecfba37d6` |
| `assets/BinbunGrass/shader/util/dither.gdshaderinc.uid` | `448f36c82563f9f501a76adb4fac98f5ec99d7a3d8455bf70dae96ef95f5bd2a` |
| `assets/BinbunGrass/texture/grass_basic_02.png` | `aba7c7bc5695cacd6a82b1a2e59fa36a6c96cacedd769bd9aec19502a6264e5f` |
| `assets/BinbunGrass/palette/palette_01.tres` | `9296a7ae2245560f067f0d6a460bb8d3cec11f7454f44f5cdc9869a5fea35c93` |

`src/main.tscn` owns the material parameters and `GrassField` configuration. The
project-local `src/grass_palette_dry.tres` supplies the muted yellow-brown palette
without modifying the imported source palette. `src/grass_field.gd` creates at
most 144,000 deterministic MultiMesh transforms with seed `117` across the playable
ground. Scene-specific road corridors and the existing building collision boxes
plus a 0.5-meter clearance are excluded; other ground remains grass-covered and
driveable. The source shader is used unmodified; its animated wind texture receives
a non-zero velocity from the scene material.

## 2026-10-09 local source atlas input

出生庭院改用免費 demo 的四形 atlas；不使用或聲稱具有付費 Full 的14形狀／10 presets。原樣 `copy2` 自既有 cache `source/assets/BinbunGrass/src/texture/basic/grass_basic_atlas.png`，本機目的為 `assets/BinbunGrass/texture/grass_basic_atlas.png`；SHA-256 `73471dd753dc80b141dc1b958a834107205c23d7982fc6b01319921128b73995`。來源 archive／作者／CC0 授權沿上方已驗證紀錄。atlas 與 Godot `.import` sidecar 精確 ignored，不提交或外送。它是新增一個CC0本機輸入，與保留不變的586私素材分開計數。

原 demo `main.tscn` 為20×20m／10,000株、Quad0.4×0.4、subdiv2/2、centerY0.2；原材 billboard／atlas true、Dithered1（0.4–0.6），地葉共用同noise／palette／light。此版Smooth0與wind(0.6,0.3)是本輪平滑與動畫需求的自有材質選擇；原shader／PNG不改。出生地面使用project-owned `spawn_grass_ground.gdshader` 配對原grass light，兩材共享同一NoiseTexture／GradientTexture，不改原floor。

## 2026-10-16 LEA-212 本機 CI 封存輸入

沿上述免費 demo、原 archive 及 CC0 紀錄，將同一份未修改 atlas 納入 repo 外的 `quarter-lea212-589.tar`，供獲准的本機私有 CI 還原。目的 `assets/BinbunGrass/texture/grass_basic_atlas.png`，259854 bytes，SHA-256 `73471dd753dc80b141dc1b958a834107205c23d7982fc6b01319921128b73995`；路徑／大小／SHA 與 archive SHA 由 [local-ci-assets-lock.json](local-ci-assets-lock.json) 固定。

上段「與586分開計數」為 2026-10-09 的歷史基準；新版為保留原 586 筆，再加兩個路燈 GLB 及此 atlas，共 589 筆。原 586 筆與原 `quarter.tar` 不變；不納入付費 Full、XCF 或其他原圖。atlas 保持 ignored，不進 Git 或外部服務；`.import`、`.godot/imported` 由乾淨 runner 的 Godot `--import` 重建，不封存。本次不增加草地生成資源。
