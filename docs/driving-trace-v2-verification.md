# v2 紀錄驗證證據

- 舊 trace smoke：RC0，cases=2；`/tmp/trace-v1-smoke.log`。
- v2 smoke：RC0，cases=3，無 SCRIPT ERROR；`/tmp/trace-v2-smoke-final-b2.log`。四車描述／非零角度、真車接觸 shape 對照、trace off/on 命令與查詢數一致、prediction 真資料寫入／cached 去重、F4 後繼續 frame 均驗證。
- 原生獨立 code review：PASS；`/tmp/trace-v2-code-review.md`。
- 獨立原基線地圖回歸：movement、navigation、contact、predictive 四項各自 RC0/PASS；`/tmp/trace-v2-regression.md`。七個同步程式檔 hash 相同。
- Windows Godot 4.7.1 GUI 實跑 RC0：`driving-2026-09-11T15-47-43-290183-000.jsonl`，位於 `%APPDATA%\Godot\app_userdata\Tank Skirmish\driving_traces`。
- 該檔 1360 行有效 JSONL，1137 個 frame。F4 marker：seq=490、frame=394、t_ms=6488；之後繼續至 frame=1138 正常 session_end，確認標記不暫停遊戲。
- 第一個 Windows input harness 在 log-ready 前投遞按鍵未留下 marker，不採作鍵盤成功證據；修正為等待新 log 與更新測試視窗 handle 後，得到上述有效 F4 證據。未改 production 來配合測試。
- 使用者場景 SHA256 維持 `8df361c61678290464cbfebb00ffd6353af52291421ea8d7d958590d688be3be`，未改地圖／素材或關閉原編輯器。

## 交付界線
此版是狀態與決策的診斷重建，不是自動或確定性物理重播。逐物理幀保留觀測姿態與套用操作，每幀最多保存當次觀測到的最後一個 Navigation request。cast_motion 不提供物件身分時仍明示未知；guard kind 不是碰撞部位名稱。本次不修先前辨識的面敵評分與脫困行為。

## 下一次人工測試
重新以 F6 執行訓練場。發現卡住時在遊戲視窗按 F4，繼續操作幾秒後停止，再告知已重現。F9 保留 Godot 自身暫停功能，不是本版標記鍵。
