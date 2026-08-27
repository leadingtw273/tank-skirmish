# Binbun Godot Skies provenance

## Source and license snapshot

- Author: Binbun
- Official source: <https://binbun3d.itch.io/godot-skies>
- Downloaded: 2026-08-24
- Archive: `GodotSkies-source.zip`
- Archive SHA-256: `2550d3abe6be08c9c0dd55a424ce1dd96d463f512e6567916a824630136a3895`
- License: CC0 1.0 Universal / Public Domain Dedication
- License evidence: the official source page identifies the asset license as
  Creative Commons Zero v1.0 Universal and states that the pack may be used for
  personal, educational, and commercial projects without attribution.

## Imported source-code subset

The archive was verified before import. Only the following unmodified files from
`source/SourceCode` are used by `src/main.tscn`; no full presets or unused assets
are included.

| Repository file | Source SHA-256 |
| --- | --- |
| `assets/BinbunSkies/shader/main.gdshader` | `20e74f26c4d638e5117f96ee47cfca9f296b8ace2ba5cde3b0f0ad16d094396e` |
| `assets/BinbunSkies/shader/main.gdshader.uid` | `c446f705e4de04e5cebf7db556b4bf47e8139d9eb135cd1a5c8623597976c303` |
| `assets/BinbunSkies/textures/clouds/clouds_01.tres` | `b30ab84aa00fb16cb21eb1aec0d8d2647763c066589525a0b9c782a49cdb07e4` |
| `assets/BinbunSkies/textures/clouds/clouds_02.tres` | `bf77268301c67fc90bee684b3fe6b00fd5d9208e1e70ffefb66f950bcff4a9b5` |

The scene uses the shader's `cloud_tex_01` and `cloud_tex_02` parameters and its
existing DirectionalLight3D-derived sun direction. The shader source and cloud
resources were copied byte-for-byte; no mesh, texture, or shader modification was made.
