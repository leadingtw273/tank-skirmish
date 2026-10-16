# AtomicRealm 路燈來源與本機 CI 輸入

## 來源與授權狀態

- 作者／素材系列：Atomic Realm，Modular Roads。
- 原始包：`[FREE] Modular Roads - Base.zip`。
- 原始包 SHA-256：`217979d913494d419f24da5578c76254f529bb85de0f2679a5e02f38e5c3ba20`。
- 來源鏈見 [雨夜路燈](../features/rain-dusk-lamps.md) 與 [道路來源盤點](../maps/road-source-inventory.md)。兩個 GLB 原樣取自下表 ZIP 成員，未重新轉檔。
- **授權狀態：未查證**，沿用同 ZIP 既有 base 檔的狀態。原 586 筆 lock 已包含 10 個 `assets/AtomicRealmModularRoads/base/` 檔及同系列的 525 個道路衍生資源；本次不宣稱取得或查證新的授權。
- 企劃於 2026-10-16 在 LEA-212 收尾派工「B2–B4 續行」裁決：兩燈與既有 base 同包，採同一授權狀態，只補確切缺的三檔供本機私有 CI。`[FREE]` 不等同 CC0；[Quaternius Modular Streets](modular-streets-provenance.md) 為另一素材包，其 CC0 不適用於此處。
- AtomicRealm 整包正式授權查證列入 LEA-212 backlog，屬既有問題，不是本單引入。素材本身不進 Git、不上傳 GitHub artifact／cache 或其他外部服務。

## 原樣檔案映射

| ZIP 成員 | 本機目的 | bytes | SHA-256 |
| --- | --- | ---: | --- |
| `PLUS/gltf/lamp_1.glb` | `assets/AtomicRealmModularRoads/lighting/lamp_1.glb` | 667872 | `98f90212c9b9d632518169ffa1d10fb0e55bbcf81952d9cf545ac64ad0cb05c2` |
| `PLUS/gltf/lamp_2.glb` | `assets/AtomicRealmModularRoads/lighting/lamp_2.glb` | 679500 | `4bdb38d66c0b5d180aa2c06e012fa67b2e950a1aa748df59264a1b985f29c85a` |

## 封存與生成政策

兩檔只加入 repo 外的 `quarter-lea212-589.tar`；路徑、大小、SHA 及 archive SHA 見 [local-ci-assets-lock.json](local-ci-assets-lock.json)，操作見 [本機私有 CI](../local-private-ci.md)。原 `quarter.tar` 與原 586 筆 payload 保持不變。

兩 GLB 的 buffer／圖像均內嵌，沒有外部 URI，不另封存相鄰匯出 PNG 或 `.bin`。`.import` sidecar、`.godot/imported` 與內嵌圖匯入輸出由乾淨 checkout 的 Godot `--import` 重建，不提交或封存。本次不增加其他生成資源；既有道路／建築的 RES／TSCN 仍沿原 lock 還原。
