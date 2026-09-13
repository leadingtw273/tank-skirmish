# 駕駛紀錄輪替驗證

## 狀態

紀錄修正已可試玩；Linux 獨立驗證通過，Windows 跨段 F4 功能已實測。Windows 渲染退出錯誤亦在舊版對照重現，並非乾淨無錯誤的整體 Windows harness PASS。這次只修紀錄，不代表敵車卡住問題已解決。

## 變更

- Recorder 每段預設 16 MiB，最近 8 段循環保留；最新 F4 段與前段另行保護，正常最多 10 段／160 MiB。
- 新段保留來源雜湊、session／segment 身分與完整當下 checkpoint。跨段 seq／時間接續，F4 寫入成功才回報。
- 只清理本次 recorder 建立且不在保留集合的明確檔案；舊 session 不刪。輪替失敗停寫並警告，含 pending 最多 11 段／176 MiB。
- 新增 rotation smoke、Windows 視窗測試入口與 quality 接線，更新使用說明。

## 紅燈與修正證據

- 原 bug：`/tmp/trace-rotation-red.log`，256 KiB 真車 fixture 自然滿額後 F4 無 marker，RC 1；不是缺新 API 的假紅。
- 第一版輪替：`/tmp/trace-rotation-green-first.log`，RC 1，跨段 seq/time 逆序。修正為新段 metadata 寫入後重新序列化原事件；斷言未改弱。
- 正常退出邊界：沒有存活 encounter 時，輪替不得對空陣列呼叫 front；修正 nullable 選取並寫空 encounters checkpoint（正確反映當下狀態）。
- 測試相容性：`/tmp/trace-rotation-v1-first.log` 為舊 4 KiB cap 要求 attach 成功的唯一失敗。新增必要 checkpoint 後此容量不足，更新該分支驗安全拒絕、檔案上限及 sentinel 不動；`/tmp/trace-rotation-v1-green.log` RC 0。
- second F4 的舊 marker 可隨舊 pin 回收；測試改比新 marker seq／segment，而非假設保留目錄內的 marker 總數必增加。這是 harness 修正，不改 retention 政策。

## 最終結果

- 作者實跑 rotation／v1／v2 各 RC 0，具 PASS 且無 ERROR／SCRIPT ERROR。`/tmp/trace-rotation-tests.md` 列完整證據。
- v2 原常數斷言為舊單檔 128 MiB；依核定改為單段 16 MiB。初跑失敗已回報，但其 raw log 被同路徑最後重跑覆蓋，此處不宣稱仍保留原始失敗檔。
- Fresh-context：rotation／v1／v2／正常退出跨段四項均 RC 0；兩項直接 blocker 已關閉。報告 `/tmp/trace-rotation-acceptance.md`。
- Windows 第二次實跑：`/tmp/trace-rotation-windows-20260912-143332.out.log`，segment 001 的 F4 seq 160／frame 128 實際寫入，之後再跑 120 個物理幀，遊戲 RC 0。原始第一跑的空行 JSON parser 錯誤只修測試入口後已消失。
- Windows JSONL 獨立讀回：標記後實存 128 筆 frame，`session_end seq=312/frame=257/reason=stopped`；三段 header 的 recorder 雜湊均與新版 `707d0a8d000dd032ecc88ef91a752ac0fe9cf2a6f4d89a056d20fbbb6d0955e1` 相等，previous chain 與跨段 seq/time 正確。
- Windows harness 整體仍 RC 1，原因為退出時的 Texture／RID／RenderingServer 錯誤；不將它改稱 clean PASS。正常交付入口對照 `/tmp/trace-rotation-windows-control.*.log` 與舊 recorder 回歸副本對照 `/tmp/trace-rotation-windows-baseline.*.log` 皆為遊戲 RC 0 且重現同一渲染退出錯誤。此項列既有問題，不在紀錄修正中改渲染系統。
- 此次未改動 predictor／navigation／combat AI／controller，SHA 與修正前相同。使用者 scene 仍為 `8df361c61678290464cbfebb00ffd6353af52291421ea8d7d958590d688be3be`，導航資源仍為 `7db3c844566f374b65efe6fdfab844bf5e28bbb17cf221845e8326096a7f877f`。

## 試玩交接

停止舊遊戲後 F6 重新執行訓練場；這不需要清除／重烘焙導航，也不需要重開編輯器。問題出現時讓遊戲取得焦點再按 F4，繼續幾秒後回報情境。這次是讓下一次問題能完整留下證據，不是新的 AI 脫困修正。
