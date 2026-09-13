# 駕駛實測追查紀錄

## 2026-09-11：第一次有標記的重現

狀態：已記錄，等待使用者追加測試；不修改 AI、導航、防撞或脫困邏輯。

- 原始檔：使用者本機 Godot `app_userdata/Tank Skirmish/driving_traces/` 下的 `driving-2026-09-11T13-43-50-326899-000.jsonl`。保留原檔，不覆寫。
- F9：`seq=1608`、`frame=3146`、`t_ms=54185`。
- 詳細量測報告：`/tmp/repro-trace-analysis.md`。
- 全檔 1611 筆有效 JSONL，正常 session_end；F9 後沒有 sample，不能推論標記後的移動。

### 已知事實

標記前的量測窗為 `t_ms=44201..54183`，共 91 個 sample。

- 敵車全窗 `visible=true`、`pursuing=false`、`terminal=false`。玩家與敵車距離約 36.48 → 37.21 公尺，不能把沒有追近直接視為尋路失敗。
- 敵車 XZ 位置 `(38.959,-65.732) → (38.614,-66.032)`，首尾淨位移約 0.458 公尺；這是淨位移，並非累積行走距離。所有 sample 的 actual_linear_speed < 0.15。
- 原始要求：70 筆 movement=0（朝向調整等），21 筆要求倒車。selected.reason 為 risk 69 筆、blocked 21 筆、clear 1 筆。
- 兩輪脫困期間，倒車要求被預測器以 blocked 改為零輸出。全窗有 38 筆非零 AI output、37 筆非零 applied input；兩者的物理 frame 有錯相，不能只以同一 sample 強行比較。
- 敵車 contacts 全空，無敵車 contact_begin/end，motion guard root 沒有 blocked。玩家與 NorthGable 的接觸不能當成敵車撞牆證據。

### 暫定解讀與限制

依程式呼叫與資料，問題片段較接近「原地調整朝向 → 預測防撞介入 → 嘗試倒車脫困 → 倒車也被阻擋」，而非單純沒有導航路線。

目前尚不能確定預測被哪個物件／車體部位阻擋，也不能由空 contacts 推論周圍無障礙。此為待比較的診斷方向，不是已確認的完整根因或已修復結果。

後續：使用者再測數次，每次獨立開啟訓練場、問題出現按 F9，盡可能再繼續幾秒。依新檔與 marker 比較，未獲指示前維持現有邏輯。

## 2026-09-11：第二次卡住，並確認 F9 暫停衝突

- 使用者確認：按 F9 前也是坦克卡住；F9 的遊戲暫停是另一個問題，不應混為同一原因。
- 原始檔：同資料夾的 `driving-2026-09-11T13-49-08-288141-000.jsonl`，4007 筆，正常 session_end。
- F9：`seq=3856`、`frame=9459`、`t_ms=157573`。Godot 內嵌遊戲的 F9 同時是暫停／繼續鍵；使用者已再按以恢復。標記鍵尚未更換，舊操作說明暫不適合連續測試。
- 標記前約 10 秒共 100 sample：敵車淨位移約 0.377 公尺，全窗 pursuing=false，contacts 全空。59 筆 moving/risk/normal；41 筆 recovering/reversing，其中 40 筆 selected.reason=blocked。
- 暫停後直到 `t_ms=339446` 才恢復 sample，不能把中間約 182 秒當成 AI 卡住時間。
- 恢復後至結束約 3.1 秒共 32 sample，敵車首尾淨位移約 0.118 公尺；18 筆 moving/risk，後 14 筆 status=stuck。stuck 中 selected.reason 可能沿用先前快照，不當作新的預測結果。
- 比較：兩次都出現朝向調整時防撞介入、倒車脫困遭 blocked；本次恢復後另外明確進入 stuck。這支持重複出現同類現象，仍未定位預測阻擋的 collider／車體部位。
- 本次僅記錄及唯讀比較，未修改 AI 或快捷鍵。

## 2026-09-11：第三次重現，使用者觀察疑似砲管卡牆

- 使用者回報：「又紀錄一次，感覺這幾次比較多是因為砲管卡牆」。記為現場觀察／待驗假說，不當成已確認根因。
- 原始檔：同資料夾的 `driving-2026-09-11T14-01-25-294842-000.jsonl`，保留原檔。
- 目前 predictor stats 不含造成阻擋的碰撞 shape／部位；實體 contact 也未記錄車輛自身 local shape。motion_guard 即使能區分 root／turret／gun 操作，也不等同辨識是哪一塊形狀阻擋整車移動。
- 後續判讀需區分「砲管實際接觸牆面」、「砲塔／砲管旋轉受阻」與「完整車體的未來移動預測被攔截」。不能僅由 risk／blocked 斷言砲管卡牆。
- 本次只留存及讀取診斷資料，未改碰撞形狀、預測範圍或 AI 邏輯。
- 量測報告：`/tmp/repro-trace-third.md`。F9 為 `seq=5767/frame=11374/t_ms=189874`。
- F9 前 9.881 秒共 100 sample，敵車已是 stuck、terminal=true，XZ 淨位移 0，output／applied input 都為零。恢復後 4.016 秒共 41 sample，仍是相同停車狀態、位移 0；中間約 1.068 秒無 sample 不算 AI 卡住時間。
- 該觀測窗內無敵車 contact，root／turret／gun guard 為 no-op；已停車狀態中的 risk 可能是先前快照，不能作為當下仍碰牆的證據。要定位起因需查更早進入 stuck 前的過程，而非只看 F9 附近。

## 2026-09-12：v2 實測確認砲管形狀造成候選攔截

- 原始檔：`driving-2026-09-12T08-57-41-330212-000.jsonl`。schema=2；場景與 controller／predictor／navigation／recovery／AI 程式 hash 均和本次分析原始碼相同。
- 玩家與敵車皆 tank2，1118 筆 sample 未換車。F4：seq10848/frame5187/t86.528s；first stuck：seq10514/frame4906/t81.847s，在 F4 前4.681秒。
- 兩輪倒車脫困首拒分別在 t66.239s（seq7822）與 t76.815s（seq9676）：request movement=-0.524、turn=0，皆由 gun 部位／gun anchor／shape_index=14 的 cast_motion 拒絕，安全輸出為0。cast 不提供物件身分，不能指認是哪棟建築。
- 第一次僅約0.00081公尺淨位移後停住；第二次 reversing 期間位置未改變。initial_contacts 與敵車實體 contacts 皆空，這是預測攔截，不是已證實的當下碰牆。
- 最後轉向預測 seq10515/frame4906：turn=-1 候選的 gun#14 在預測 t=0.545455秒命中 `SightBlockers/BlockB/BuildingRowB/NorthGable`；turn=-0.5 也被 gun#14 cast 攔下；turn=0安全，最終輸出0/0。具名建築只對這個未來轉向候選成立，不回推為前面倒車的命中物件。
- 結論：本次已有直接證據支持「砲管形狀使倒車／轉向候選遭安全拒絕 → 兩輪脫困未有效移開 → stuck停車」。不是 NavMesh 無路的證據，也不能稱為已發生砲管實體碰撞。未修改 AI 邏輯。
- 完整量測：`/tmp/trace-v2-repro-20260912.md`。
