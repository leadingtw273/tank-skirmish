# 道路 GLB 補全來源清單

這份清單只處理既有八個 Atomic Realm ZIP。原始 ZIP 與 entry bytes 不會改寫；以下三個唯一缺 GLB 的模型，會以 Blender `--disable-autoexec` 轉為 `src/world/roads/generated/converted/` 的衍生 GLB。

| 包 | 唯一模型 | 選定來源 | 其他同模型來源格式 |
| --- | --- | --- | --- |
| parking | `Road5_Shoulder2` | `PLUS/dae/Road5_Shoulder2.dae` | FBX、Unity Rotated FBX、OBJ |
| signs | `SignCircle` | `PLUS/Blank_Sign_Meshes/dae/SignCircle.dae` | FBX、Unity Rotated FBX、OBJ |
| racetrack | `Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right` | `PLUS/fbx/Racetrack1_YellowBlue_Curbs_Curve_45_Long_Right.fbx` | Unity Rotated FBX |

其餘 catalog 中的 29 個 `missing_glb` entry 不是缺模型：`Sig7Austrian.dae` 至 `Sig30Austrian.dae` 是既有 `Sign7Austrian.glb` 至 `Sign30Austrian.glb` 的 `Sig`/`Sign` 拼字別名；`Sign287dae.dae` 的 COLLADA 內嵌材質名稱為 `Sign27Material`，對應既有 `Sign27.glb`。這些證據避免把同一模型重複轉檔。

轉檔結果與材質摘要會寫入 `src/world/roads/converted_catalog.json`；選定來源的 SHA256 另寫入 `src/world/roads/converted_source_manifest.json`，供重跑前後確認來源未變。
