# Atomic Realm Modular Roads 來源盤點

本報告記錄 2026-09-18 首次本機 SHA256 基準，不是官方簽章或授權驗證。每個 ZIP 已於匯入時以 `ZipFile.testzip()` 完成 CRC 檢查。

| 包 | ZIP SHA256 | GLB | PNG | 缺少 GLB 的來源項目 | 授權證據 |
| --- | --- | ---: | ---: | ---: | --- |
| base | `217979d913494d419f24da5578c76254f529bb85de0f2679a5e02f38e5c3ba20` | 27 | 15 | 0 | ZIP 內無名稱含 license 的檔案；授權狀態未查證 |
| parking | `c00f376736e88d1e9e058285158073b9659cb7c4c415a211e831b3d5fd500d23` | 42 | 73 | 4 | `assets/AtomicRealmModularRoads/parking/2. License.png`；授權狀態未查證 |
| ovaltrack | `2a02288c256a8a3b9998ee8b51f3379160b373cb54b952c03b789fe850445480` | 45 | 3 | 0 | `assets/AtomicRealmModularRoads/ovaltrack/2. License.png`；授權狀態未查證 |
| highway | `6ed6a77c219317222f837ae7c763c5f1eca0d13a129ce5abdd84bbdc0ab5f2f9` | 78 | 2 | 0 | `assets/AtomicRealmModularRoads/highway/2. License.png`；授權狀態未查證 |
| dirt | `fb0ea210ae7ef2e982db341ea6d221ba42664c83fc7ce886388092e5abba5207` | 13 | 41 | 0 | `assets/AtomicRealmModularRoads/dirt/2. License.png`；授權狀態未查證 |
| bridges | `ee141647417ecde7c9a414b15230594220d386887d8734a7a8b624b3fb1871a9` | 23 | 60 | 0 | `assets/AtomicRealmModularRoads/bridges/2. License.png`；授權狀態未查證 |
| signs | `6a4d31cbcca398161da70b03b28093908a5d3fe45f5a89254af53895bcd8abdb` | 150 | 402 | 29 | `assets/AtomicRealmModularRoads/signs/2. License.png`；授權狀態未查證 |
| racetrack | `e4141ea5b80b6351f9bf8bdaed5420b4cde8b92f22aab9da123b9542a7a0e463` | 85 | 2 | 2 | `assets/AtomicRealmModularRoads/racetrack/2. License.png`；授權狀態未查證 |

完整 ZIP entry 清單與 CRC 結果：`assets/AtomicRealmModularRoads/source-manifest.json`。

`missing_glb` 逐項清單位於 `assets/AtomicRealmModularRoads/catalog.json`；FBX/OBJ/DAE 保留在原始本機來源庫，未匯入 Godot。
