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

### Animated Tanks 四車來源

| 車型 | 原始檔 | fileId | source SHA-256 | production GLB SHA-256 |
| --- | --- | --- | --- | --- |
| Tank1 | `Tank.blend` | `1uaTlQ-HqN27if0knwsGTpL2NiQKFEKms` | `1949b020efda14164b62f153e8d186e624aa4b6edb8d3539a31d42e2286a5692` | `3d529f76befe09f614ed354defe49403b6bb0ff58866eb268ea09c3963bdc8fb` |
| Tank2 | `Tank2.blend` | `1OMHkxObJluIDIGMPLhuPu4SlmJtJ4047` | `71a4e5305196ed8abd57207d3b185b24da858363ae519bb89ff917914235e6d6` | `61b05ab82d0e57b3ce1d73f2b78f3c0010fc677b9115dd4965b67356a1431e9a` |
| Tank3 | `Tank3.blend` | `1z_CR2nhFwz8n2z0JM6sI5bXD-2iC4_r5` | `882975a599e7d265803f971424b2ffe7ca6d7aab5736cec98058e99239092e7d` | `8b1aa6676b833b18b65110af98be523606042e9d79336fbb0089ace3e5498acd` |
| Tank4 | `Tank4.blend` | `1hrG1XAUSpbCAtvxsOEdx0Csi-O4yTSAx` | `25613d55289dce03f71c19f11cb1386be24927ad28f6766af6ec19a51f4cb93e` | `02a2f612f8fc35be86ace74607d27d990c9023940854082d9bb959b7189ed6d8` |

- Blender executable：4.5.12 LTS，SHA-256
  `33ac108ebce3c271f5357e5c664d0488717263bcf2145c80300edd0b12c31880`。
- 後續 conversion 必須使用 lock 所列來源檔與 `scale`；預期 Godot AABB 為
  `round([rawX * scale, rawZ * scale, rawY * scale], 5)`。
- 每一軸的驗收 tolerance 為 `max(0.01m, expectedAxis * 0.01)`；這涵蓋 Blender 原始物件界線與 Godot 對骨架網格實測界線間的小幅差異，不改寫來源尺寸。
- 12 個 production 模型的輸出 digest、Godot 實測尺寸、動畫與內嵌貼圖契約，固定在 [`conversion-manifest.json`](conversion-manifest.json) 並由 quality gate 重驗。
