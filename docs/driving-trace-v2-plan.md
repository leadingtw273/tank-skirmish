# 駕駛紀錄 v2：狀態與決策重建

## 已採用範圍與澄清
使用者核可繼續到可測試。本輪採前次建議：供 leadi 與代理追查訓練場卡住原因的本機診斷紀錄，不是確定性物理重播器。產品、使用者、單人 Windows 訓練場與除錯動機維持原有前提。grill-with-docs 所釐清的「復現」在本輪限定為還原狀態、操作及判斷順序；自動重播另案。

## ADR
- 背景：三次卡住 log 欠缺明確車型、角度座標系、阻擋部位／物件，10Hz 亦不足以對齊短暫指令，F9 與內嵌遊戲暫停衝突。
- 決策：擴充既有 JSONL；保留 10Hz 詳細 sample，增加逐物理幀精簡姿態／已套用操作 frame 記錄、一次性車型／形狀描述、候選阻擋證據。改 F4 標記（先核對專案與內嵌遊戲快捷鍵），只存本機。
- 被否決：此次實作自動重播／錄影／完整世界存檔；移除砲管碰撞；調整 AI 選擇或 recovery；為取得 log 額外跑碰撞查詢。
- 影響：Controller 提供唯讀描述／姿態與真實接觸形狀索引；Predictor 在既有查詢旁收集有限候選證據；Recorder 序列化／標記；測試驗證不影響駕駛語意。

## 固定資料合約
- session schema_version=2；角度明示 radians，補可讀 degrees；世界／局部座標系、physics delta、來源脚本 hashes、場景 hash。舊欄位保留。
- actor 描述：instance id、場景／車型識別、車型顯示名（如有）、物理參數、geometry resource path 與 shape index→part anchor/name 對照。不得依猜測命名車型。
- 詳細 sample：車身 world yaw／transform、砲塔 local/world yaw、砲管 local pitch、炮口 world transform（可用時）、既有目標／輸入／輸出／速度。frame 精簡保存玩家敵車 transform／局部角度／套用输入及其frame，分辨提交與套用时序；这是狀態採樣，不承諾重播。
- 候選證據：request frame、各實際評估候選 movement/turn、安全／拒絕／budget、score（有評分才填）、第一個真實阻擋 shape index/part、階段與預測時間。只記已執行查詢，未評估不補造。
- intersect_shape 可提供 collider id/path/shape，記下。cast_motion 只給安全比例時記 source=cast_motion、fraction、己方 shape/part，collider_unknown=true，不能把 broadphase 候選当成真正阻擋物；無額外 physics query。
- 真實 slide contacts 補己方 local shape 與對方 shape／id／path；guard 的 kind 只是操作種類，不宣称它就是命中部位。
- terminal/cached predictor 明示 request_frame，不能誤認新計算。初始接觸、候選集合均有限，不逐微步 dump。
- 每秒 flush，標記立即 flush並輸出簡短提示；按鍵不暫停。不覆寫／刪舊 log；單檔上限128MiB，達限警告停記。debug GUI自動開，headless僅force；I/O失敗不影響遊戲。

## 固定驗收矩陣
1. 四種車型descriptor正確；非零車身／砲塔／砲管角度座標系可由fixture數值比對，shape映射不錯位。
2. 真實完整碰撞形狀撞牆有己方part與對方物件，predictor形狀阻擋有真來源；cast未知明示，不增加物理查詢或更換安全判斷。
3. JSONL schema2、frame序號／操作／姿態、候選拒絕、marker、正常結束可解析；舊10Hz/route-only-on-change、headless-off、限額／不覆寫維持。
4. F4會標記且後續physics frame繼續；F9不再觸發自訂marker。Windows GUI實跑驗新檔（不能只headless）。
5. 原predictive driving／contact／movement／navigation適量回歸；使用者地圖、資產與AI行為不改。獨立context複查及實跑證據。

## 邊界
不改目標優先度、距離、候選順序、評分、安全門檻、重試預算或幾何。記錄增加的成本不應導致預測watchdog頻繁耗盡；若回歸出現此現象則先回報，不提高閾值。無外部上傳與跨供應商review；先前外部權限拒絕不重試，使用原生獨立review。

## 原生獨立 review 裁決
採納唯一 blocker：predictor 計時區內僅擷取固定上限 scalar／已回傳 hit 的必要欄位，禁止 JSON、deep-copy、flush、場景遍歷與額外 query；路徑／part解析和序列化延後到 logger。收集以 Controller 的 `is_driving_trace_enabled()` 判斷，預設false，recorder遇到actor時以 `set_driving_trace_enabled(true)` 啟用。新增固定fixture比較 trace off/on 的 movement/turn/reason/query_count一致（非elapsed時間一致）。其餘review無阻擋，依使用者核可繼續實作。
