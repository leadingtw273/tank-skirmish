# 駕駛紀錄滿額不中斷：封閉修正

## 已核可範圍與前提

使用者按 F4 卻沒有標記。紀錄已達 128 MiB 並停止，`mark_problem` 在 stopped 時直接返回。使用者核可先修此診斷缺口，不繼續修改 AI。沿用可信本機 Windows 單人訓練場、leadi 試玩診斷、產品優先的既有前提；不新增使用者／平台／產品定位。

## 決策

- `limit_bytes` 改為單段容量（預設 16 MiB），保留本次 session 最近 8 段；另外保護最新 F4 所在段與前一段（若不在最近 8 段內）。正常輪替完成後至多 10 段／160 MiB，包含目前開啟段。建立新段時暫容一個 pending 段；若清理失敗立即停止、不繼續增長，因此含此異常 pending 最多 11 段／176 MiB。
- 只刪除此 recorder 自己建立、明確列冊且已關閉、不在保留集合中的路徑。舊 session／使用者原紀錄一律不掃描刪除；整個歷史資料夾並非全域上限。再次 F4 更新保護集合，不承諾永久保留每次標記。
- 正常滿段即接續新段，不停止 recorder 或停用 actor trace。F4 成功寫入與 flush 後才回報成功並保護該段與前段；不複製大檔、不暫停遊戲等待固定秒數。
- 每段包含 session header：沿用 schema 2，增加 session_id、segment_index、previous_segment、retention metadata；source/scene hashes 取 session 初始快取。全 session seq、t_ms 不重置且儲存順序單調。
- 分段開頭另有 checkpoint，保存當下 encounter、玩家／敵車身分與車型／shape map descriptor、姿態、AI/navigation state 與路線／接觸，讓前段回收後仍可解讀。使用現有唯讀 getter，不呼叫推進路點或控制的方法；不可將一次安全預測宣称確定性回放。
- 寫入採非遞迴容量檢查。header/checkpoint/單一事件本身大於可用段容量（例如刻意極小測試 cap）可明確警告並停止，不無限建立空檔；正常容量滿額與 I/O 錯誤須分開。任何寫入／輪替失敗不得印出成功 F4。
- 新段成功開啟且寫妥 header/checkpoint 後才提交切換、清理本 session 舊段；失敗停寫且明確警告。內部寫入回傳成功／失敗，header/checkpoint/marker 不得遞迴觸發輪替。

## 允許修改與不變式

允許 recorder、相關 trace 測試、新 rotation 測試、用法文件與必要測試入口。禁止修改 AI、controller、碰撞、場景、資產、導航、Windows 使用者舊 log。保留既有 headless opt-in、只寫 user://、多 encounter 共用、F4 非 F9、10Hz sample 與逐幀輸出、候選證據與 read-only 合約。

不做：跨 session 自動刪除、UI 面板、上傳、壓縮、任意多 process 同檔競爭、惡意 filesystem 防護框架、所有 F4 永久封存、任意 I/O 故障後透明恢復。

## 固定驗收矩陣

1. 先保留舊 recorder 低容量滿額後 F4 未寫入的紅燈；不拿新 API 缺失代替原 bug。
2. 正常低測試容量連續輪替超過 10 次仍在記錄，滿第一段後真 F4 事件寫入且後續 physics frame 繼續。
3. 最新 marker 及前一段經後續多次輪替仍保留；下一次 F4 更新保護。所有本次檔案 <= 單段 limit、數量 <= 10，舊檔 sentinel 完整。
4. retained 段可解析 JSONL，header/checkpoint 含 actor descriptor、shape_map、姿態、AI 路線；seq/time 全 session 單調且接續。跨段 marker 有效、stop 有正常結束紀錄。
5. 超小 cap／超大單筆不無限輪替、不假報 marker 成功；保留既有 v1/v2 trace smoke 與 read-only 斷言。
6. Fresh-context 審查／實跑。Windows 新 session 實際 F4 驗證（可用隔離低 cap 測試入口加速），不可將按鍵投遞 API 成功當作 marker 成功。原編輯器與使用者場景不動。

## 執行與證據

原生獨立 review 找直接 blocker；外部 Claude 先前傳送遭拒，不重試或繞過。實作／測試分開，delivery 同時只有一個 CLI Godot，引擎 lease 逐次交接。測試先紅後綠，完整結果落 verification 文件；不得以先前 AI 短程測試代替本次 recorder 驗收。
