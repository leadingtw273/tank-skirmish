# 復盤整合驗證

日期：2026-09-13。狀態：Linux 獨立驗證通過，Windows 正常場景與 F4 功能驗證通過，可交付下一次使用者實測；音效裝置與渲染退出警告另列，不宣稱乾淨 stderr。

本次依使用者核可的 `driving-reintegration-packet.md` 回到原安全與交接合約，不新增尋路或砲塔功能。既有失敗紀錄保留於 `escape-handoff-verification.md` 及其引用 logs。

## 驗收矩陣

| 條件 | 證據／狀態 |
|---|---|
| R1 記錄案例完整脫困＋安全交接＋600 frames | fresh RC0/PASS；真轉向 28.96°、交接前獨立幾何前移 1.923m、600 frames、距原點最小0.932m、無terminal |
| R2 gun-only 鏡像、選向完整、continuation 3秒 | fresh RC0/PASS；首啟動型別缺漏的原 log `/tmp/driving-reintegration-h23.log` 保留 |
| R3 各階段 safety gate／共用 nominal／deadline／兩次額度 | fresh RC0/PASS；純 transition 實呼叫＋wiring 靜態核對，另 body recovery 真物理倒車自測 PASS，不把靜態檢查稱作全階段實車證據 |
| R4 舊地圖基線 8 支回歸 | 最終三檔source hash下完整8支 fresh RC0/PASS，無FAIL/SCRIPT ERROR/行首ERROR；清單 `/tmp/reintegration-regression-matrix.md` |
| R5 trace／資源不變／Windows 載入 | 正常 Windows 場景 RC0；F4 marker實際落檔並繼續120 physics frames，scene/nav與新AI source hash相符；stderr警告見下 |
| fresh-context 獨立驗收 | `/tmp/reintegration-acceptance.md` 最終Linux PASS，原始證據 `/tmp/reintegration-acceptance-logs/round2_*.log` |

## 保留現場

- Windows editor PID 43240 仍在 delivery 專案，沒有關閉或強制重載。
- 使用者場景 SHA256 `8df361c61678290464cbfebb00ffd6353af52291421ea8d7d958590d688be3be`。
- 導航資源 SHA256 `7db3c844566f374b65efe6fdfab844bf5e28bbb17cf221845e8326096a7f877f`。
- 專用 validation 舊地圖與使用者街區不同，禁止互相覆蓋。
- 外部 Claude review 傳送先前遭拒，採原生獨立模型，不聲稱跨供應商驗收。
- 既有 Windows renderer 退出錯誤已有舊版對照，若再次出現需另列，不能偽稱乾淨退出。

## Windows 證據與限制

- F4 harness stdout `/tmp/trace-rotation-windows-20260912-173406.out.log`：遊戲 RC0，F4 frame122 / seq153，`TRACE_ROTATION_WINDOWS PASS`。wrapper RC1，因其嚴格檢查 stderr，不能當成完整 clean PASS。
- 實際記錄 `driving-2026-09-12T17-34-12-334162-001-000.jsonl` 含18筆 recovery 字典、schema2/F4與最終3個AI SHA。時間為該次 Windows 程序回報值，與本文件台灣日期分開保留。
- 正常場景載入 `/tmp/driving-reintegration-windows.out.log`、`.err.log`：RC0，非測試腳本入口。
- 兩次 Windows 都出現 WASAPI 音效裝置初始化失敗並 fallback dummy，測試為無聲；未調整使用者音效裝置，原因尚未診斷，不列為AI修正成果。
- 兩次仍出現已知 Texture RID／RenderingServer 退出警告，有先前舊版對照；不擴入本單。
- H1 為有限姿態 fixture 而非確定性玩家輸入回放；600-frame視窗後的所有路況不作完備性保證。仍需使用者在自訂街區 F6 實測，問題時 F4 留記錄。

## 最終生產識別

- Navigation `7467acd7c8d17b76148adad90618d0bba6bed5feb006714d9471b11e2c45d133`
- Recovery `e775231223be0f86d4a719696a30e6033337ee894bd9c260013ca3bcf2663f69`
- Predictor `badf8374f853b2bffa0112612b9dd9ccfbf7b9ef7f4f77b99969760fc21949c0`

舊recovery/corner測試只適配已核可selection/rejoining/public API，保留碰撞與額度檢查。舊private cast造成的中斷／cleanup污染在乾淨單序列重跑未再現；最終corner兩凹角皆兩次後blocked、零前移且不穿牆；兩凸角真轉向27.10°、前移1.931m、handoff且不穿牆。
