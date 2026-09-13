# 脫困交接驗證紀錄

狀態：H1 尚未通過，依連續驗收失敗熔斷凍結修改；不是可交付試玩版本，Windows 未啟動驗收。正式環境及使用者編輯器未關閉或覆蓋。

## 修改前基準

真實使用者場景／Tank2 記錄姿態，以 live CombatAI、導航及物理執行，重現兩輪倒車後回到原受阻區域：最近 0.151 m，frame 726 terminal stuck。這是有限姿態重現，不是確定性輸入回放。原始證據見 `/tmp/escape-handoff-repro.md`。

## 保留範圍

- 使用者場景 SHA256：`8df361c61678290464cbfebb00ffd6353af52291421ea8d7d958590d688be3be`
- 導航資源 SHA256：`7db3c844566f374b65efe6fdfab844bf5e28bbb17cf221845e8326096a7f877f`
- Recorder SHA256：`707d0a8d000dd032ecc88ef91a752ac0fe9cf2a6f4d89a056d20fbbb6d0955e1`
- Production 允許修改限 Recovery、Navigation、DrivingPredictor；保留既有 dirty 檔案及使用者編輯器。

## 固定驗收

1. H1：記錄案例實際轉向、正向前移至少 0.5 m、安全交回原始導航，交接後至少 600 個 60 Hz physics frames 未返回受阻點 0.5 m 範圍且未 terminal stuck。
2. H2：完整砲管碰撞、左右鏡像、只轉安全但前移不通不得選用、選定方向不任意切換。
3. H3：無候選／受阻／無安全銜接時，16 秒 attempt 硬期限及最多兩次嘗試；生命週期清理。
4. H4：既有移動、導航、預測、接觸及最後目標回歸。舊測試與核可的新脫困語意衝突時保留原始失敗，只調整已變更的語意斷言。
5. H5：新增 trace 合約可讀、場景及導航資源未變、Windows 載入；既有且有 baseline 證據的 renderer 退出錯誤另列。

## 限制

外部 Claude review 傳送曾遭拒，未重試或繞過；使用原生獨立模型複審，並非跨供應商複審。最終驗收須由 fresh-context 代理獨立執行，實作者自測不代替驗收。

## 第一輪失敗分類

- D（測試還原缺口）：新增的 `blocked_origin`／`blocked_forward` 未由記錄姿態還原；已補入真車的 stable center／forward，不改任何 H1 驗收門檻。
- 補正後一次獨立診斷仍失敗：倒退 3.413 m、轉向 0.02°、未前移及未交接。該次載入 trace-only 補齊之前的版本，不能以 `blocked` 直接認定所有完整候選都被真實幾何擋住。
- A（第 1 輪原 AC 實作缺口）：continuation 未沿用目前 phase／進度、handoff 誤用 reason 布林值、同幀重複計時，以及 terminal 診斷被 reset。
- A（診斷合約未完）：profile first blocker／phase／advance metadata 已補齊，待實跑。
- 尚無直接 B 回歸或真正 Spec blocker 證據；未增加新驗收或碰撞例外。診斷報告：`/tmp/escape-handoff-diagnosis.md`。

## 收束檢討／凍結交接

1. 原目標（L0）：實際側轉前移後接回導航，不重回原卡點；不是證明某一小段倒車或旋轉成功。
2. 最小安全閉環（L1）：完整形狀預檢、當前 phase 的三秒 continuation、安全原地轉向仍由 rejoining 持有、正向 nominal 安全才交接。有限兩次及期限屬 L2。沒有新的使用者／用途／產品定位／動機維度。
3. 原失敗分類：fixture 初始狀態及 gun-only 測試高度為 D；continuation horizon 結尾無條件拒絕是原 A1 未修完整，已最小修正；未新增原驗收以外的義務。
4. 最新原 H1 證據：`/tmp/escape-handoff-repro-final.log` RC 1。實際轉向 57.91°、前移 1.923 m，兩次完整 selection 均 clear、沒有 first blocker，但沒有 safe_nominal handoff。獨立唯讀診斷確認原 AC7 缺口：rejoining 的安全 `movement=0, turn=-1` 被當成 unsafe_nominal 立即拒絕，沒有執行原本核可的安全原地朝向銜接。此為直接 A blocker，不是幾何／砲管證明無解。
5. 凍結：不再微調 production、不新增紅測。待裁決回原 AC7 封閉修正後才重新實作；不擴入砲塔控制、NavMesh、全域路線或放宽碰撞。外部對向 review 不可用，已用原生獨立決策模型做唯讀範圍核對並揭露限制。

H2/H3 的首跑原始輸出 `/tmp/escape-handoff-h23-final.log` 保留：continuation 已通，但宣稱 gun-only 的測試障礙原先覆蓋履帶。測試作者僅修正障礙高度且保留 gun-first 斷言，修改後尚未實跑。H4 回歸與 H5 Windows／fresh-context 最終驗收尚未進行；不得由局部進展宣稱整體完成。
