# 訓練場駕駛診斷紀錄

## 目標與邊界
針對使用者多圈貼牆繞行後的追擊問題，先取得真實操作證據；本單不修尋路、預測、碰撞或脫困決策。沿用 Windows 單人試玩與使用者手工街區。這是既有問題的診斷工具，不新增遙測上傳或重播引擎。

## 鎖定實作
- 訓練場 debug GUI 執行預設自動啟用；headless 原測試不自動產檔，專用測試可明確啟用。Encounter 可停用紀錄，不修改使用者 tscn。
- 一場程序共用一個 recorder，註冊所有訓練場 Encounter；每 0.1 秒記錄各玩家／敵車對的實際位置、朝向、速度、命令、相對向量與 AI／導航／預測／脫困快照。
- 在晚於預設控制器的 physics priority 取樣。每筆附 physics frame 與 session 相對時間；AI 決策附自身命令 frame，contacts 附 age，明確區分同一快照中不同更新時點。
- 接觸開始／結束、actor 換車、視野／AI／recovery／predictor reason 轉變逐 physics tick觀察；路線改變記完整路點，其餘樣本不重複整條路線。位置取樣不是逐 frame 完整動作重播。
- F9 在遊戲有焦點時寫入問題標記並立即 flush；正常每秒批次 flush，正常結束 flush。強制終止最多可能缺末一秒，不承諾 crash-proof。
- JSONL 存 `user://driving_traces/`，每場唯一檔名，header 含 UTC、引擎版本、場景路径與場景檔 SHA256。單檔 32 MiB 上限，滿額停止紀錄並提示，不刪除／覆寫舊紀錄；不收鍵盤文字、帳號、網路或其他專案資料。
- Snapshot 僅讀 cached AI／navigation／controller 狀態，不再呼叫 can_see、get_next_path_position、predictor.choose 或物理查詢；不改既有 physics 執行順序與玩法。只新增 observer 節點自己的較晚優先度。

## 有限驗收
1. 明確啟用的 headless smoke 能產出可逐行解析的 JSONL：session、sample（player/enemy/relative）、actor change、contact begin/end、state change、route change、F9 marker、session end。
2. 真實坦克撞固定牆的紀錄含 collider id/path、normal/position 與 contact age；能区分AI原始需求、選中命令與實際速度。
3. 多 Encounter 同檔且 identity 可區分，換車不混用舊 actor id；時間／seq 單調。
4. 可停用；不可寫目錄與檔案額度用盡不影響遊戲、不得覆寫先前 log；不擴建輪替／自動刪檔機制。
5. Snapshot read-back 不改導航 index、recovery attempts、command 或 target；原 movement/navigation/contact 回歸維持通過，使用者街區保留。
6. Windows Godot 實際建立紀錄檔，核對路徑與內容，再交付重現方式。

## 審查範圍
原生獨立 code／test 驗證，外部 Claude 尚未獲資料傳送授權，不繞過。非目標：修正本次移動 bug、任意網路／惡意場景、未來模型相容、完整 deterministic replay、影像錄影或分析 UI。
