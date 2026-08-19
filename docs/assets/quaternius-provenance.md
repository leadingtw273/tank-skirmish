# Quaternius Asset Provenance Snapshot

本文件固定 [LEA-76](https://linear.app/leadingtw273/issue/LEA-76/preflight-03-01-%E7%9B%A4%E9%BB%9E-quaternius-source-files-%E4%B8%A6%E9%8E%96%E5%AE%9A%E6%A8%A1%E5%9E%8B) 的來源與授權證據。模型／atlas 的 strict identity、縮放與量測契約位於
[`quaternius-lock.json`](quaternius-lock.json)。本 snapshot 的權威 spec SHA-256 是
`7f5e26b8e2c36c86e042d67cf344a6791cb0ae03d1326443fe48db78f8c4906f`。

## 官方 pack 與 CC0 snapshot

| Pack key | 官方 URL | 官方 CC0 URL | 短摘要 | retrievedAt |
| --- | --- | --- | --- | --- |
| `animated-tanks` | https://quaternius.com/packs/animatedtanks.html | https://creativecommons.org/publicdomain/zero/1.0/ | Animated Tanks Pack 提供 4 個含動畫坦克模型；官方頁標示 FBX、OBJ、Blend 與 CC0，可供個人及商業使用。 | 2026-08-19 |
| `ultimate-buildings` | https://quaternius.com/packs/ultimatetexturedbuildings.html | https://creativecommons.org/publicdomain/zero/1.0/ | Ultimate Buildings Pack 提供 76 個模組化建築與可變換 palette 的 atlas；官方頁標示 FBX、OBJ、Blend 與 CC0，可供個人及商業使用。 | 2026-08-19 |

## 逐 pack License.txt identity

兩份 `License.txt` 必須依 pack key 分開保存與驗證；它們目前剛好具有相同的大小與
SHA-256，不能因此合併成同一筆來源紀錄。

| Pack key | fileId | 相對檔名 | sizeBytes | SHA-256 |
| --- | --- | --- | ---: | --- |
| `animated-tanks` | `1VuTMkuQymqZGmLIACWWMOI4lXLx0TCCY` | `License.txt` | 364 | `83d8959f9fc56353ed571fbe2dc52e4bcd64508e2399501cd45ac2ce3df0bf8c` |
| `ultimate-buildings` | `1tSk6QjHVGJtpPSDuggR02LyNgO0bBG7g` | `License.txt` | 364 | `83d8959f9fc56353ed571fbe2dc52e4bcd64508e2399501cd45ac2ce3df0bf8c` |

## 縮放與轉換記錄

- Blender executable：4.5.12 LTS，SHA-256
  `33ac108ebce3c271f5357e5c664d0488717263bcf2145c80300edd0b12c31880`。
- 後續 conversion 必須使用 lock 所列來源檔與 `scale`；預期 Godot AABB 為
  `round([rawX * scale, rawZ * scale, rawY * scale], 5)`。
- 每一軸的驗收 tolerance 為 `max(0.01m, expectedAxis * 0.005)`。
- 此 snapshot 不含素材 archive、轉換輸出或其 digest；這些值在 conversion manifest
  實際存在前，依 lock 的規定維持 `null`。
