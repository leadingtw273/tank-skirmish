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
| `src/assets/binbun_grass/shader/grass.gdshader` | `46d46ce8ac4f90732686074aaddd5d17c0802252376e135bf5157c33f9f3be63` |
| `src/assets/binbun_grass/shader/grass.gdshader.uid` | `8c9e12e8ef9048f56f5c72596a8b2fe2f9f061ea4939c539ddfa42a2d05e8fca` |
| `src/assets/binbun_grass/shader/util/dither.gdshaderinc` | `2442617abb5de689075c18ea4fe72462ca063a12da938fdd2fbe39eecfba37d6` |
| `src/assets/binbun_grass/shader/util/dither.gdshaderinc.uid` | `448f36c82563f9f501a76adb4fac98f5ec99d7a3d8455bf70dae96ef95f5bd2a` |
| `src/assets/binbun_grass/texture/grass_basic_02.png` | `aba7c7bc5695cacd6a82b1a2e59fa36a6c96cacedd769bd9aec19502a6264e5f` |
| `src/assets/binbun_grass/palette/palette_01.tres` | `9296a7ae2245560f067f0d6a460bb8d3cec11f7454f44f5cdc9869a5fea35c93` |

`src/main.tscn` owns the material parameters and `GrassField` configuration. The
project-local `src/grass_palette_dry.tres` supplies the muted yellow-brown palette
without modifying the imported source palette. `src/grass_field.gd` creates at
most 24,000 deterministic MultiMesh transforms with seed `117` across the playable
ground. Scene-specific road corridors and the existing building collision boxes
plus a 0.5-meter clearance are excluded; other ground remains grass-covered and
driveable. The source shader is used unmodified; its animated wind texture receives
a non-zero velocity from the scene material.
