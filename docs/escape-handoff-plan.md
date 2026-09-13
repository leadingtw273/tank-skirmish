# 預測受阻脫困與導航交接（已核可範圍）

## 背景與鎖定前提

使用者核可：記住受阻位置／原方向，倒退後評估左右側轉＋前移的安全性，暫持有脫困控制，實際前移且能安全接回導航才交還；仍檢查完整砲管、不改砲塔瞄準、NavMesh 或兩次重試上限。
使用者、Windows 單人訓練場、產品優先、NavMesh＋載具駕駛定位與動機沿用既有裁決，未新增維度。

真實紅燈資料：`/tmp/stuck-150639-analysis.md`，F4 frame 3994。兩輪安全 nominal 倒車 1.89／1.65 m，回 normal 後又回起點 0.10／0.09 m 範圍，最後 gun/#14 與 right_track/#13 的預測阻擋令候選停車。不是實碰、過期程式、查詢預算或 recorder 問題。無 contact 時現有 settling 直接 finish，是本次最小需修的缺口。

## 鎖定技術決策

1. **Recovery 擁有狀態**：獨立保存本輪受阻點／方向、選定 escape heading、前移起點、階段及期限。不得把 reset_progress 的暫存 origin 當成全部階段的成功依據。
2. **有限候選**：倒車後停穩才選候選；有接觸方向僅用來排序，無接觸仍生成左右。固定偏好側 30°／60°、另一側 30°／60°，無接觸預設正向側。上一輪失敗的同一 heading 不優先重選；不找新全域路徑或任意姿態網格。
3. **完整 staged 預測（使用者核可修訂）**：選方向時最多模擬 10 秒，依序原地轉向、停穩角速度、低速前移及停穩；完整完成且安全才取得候選資格，未完成即拒絕。新增 Predictor 的 escape profile 入口，使用同一次 snapshot、initial contacts、started_usec 與既有 4096 queries／20 ms／12 candidates 上限。沿用同一純動力、旋轉微步及完整各部位 sweep／intersect，不延長真實每幀的 3 秒預測窗。禁止把多次獨立 probe 的預算相加，禁止只檢查最後角度的 shape。
4. **共享操作定義**：Recovery 中可抽一個純 static escape-action helper，供真實階段與 Predictor staged 模擬共用（turning→align_settling→advancing→escape_settling）。Helper 不查 physics world／不控制真 tank；Predictor 不另複製一套互相漂移的轉向／前移規則。三秒是預測窗，不是整個真實脫困流程必須在三秒完成。
5. **候選資格**：完整動作軌跡安全，且已有至少 0.5 m 沿 escape heading 的正向前移，才視為有效 turn＋advance 候選；只轉而未前移不算。選定後逐幀只重檢這個 heading／目前 phase 的未來 3 秒 continuation，不要求每個 3 秒窗都完成整個動作，不用 choose_recovery 偷換側。新的風險或 budget 都煞停，期限仍計時。
6. **真實執行**：保留原倒車距離／速度／期限與車型轉速。沿 escape heading 前移以既有 2 m 為目標，成功門檻至少 0.5 m 正投影（從 advance 起點算，倒退不算）；每幀保持全形狀檢查，不能只靠 command 或計時宣布成功。turning 期限調整為 7 秒以容納原速度的 60° 轉向；advancing 沿用 2.5 秒。整次 attempt 設 16 秒硬期限，涵蓋等待、選向、停穩與銜接，不增重試額度。
7. **銜接**：新增 pending-handoff/rejoining 狀態。前移完成、停穩後 refresh route，以當下姿態重新算正常原始 nominal，使用 nominal-only 全三秒預測。可在此狀態安全執行必要原地朝向路點，但只有原始正向 movement 非零且安全才交回 normal；一般 predictor 的替代動作不能冒充原路線已可通。合法已抵達／partial_end 的既有停止語意維持。銜接階段亦受 3 秒與 attempt 總期限限制。
8. **失敗收斂**：沒有安全方向、動作逾時或銜接失敗，不回 normal 重走舊路。停下後直接開始剩餘的第二次 attempt（不重發額度），記住已失敗 heading；兩次用完即 terminal stuck。target generation／有效目標改變的既有重試語意保留。取消／死亡／換車清空全部新增狀態。
9. **整合邊界**：Navigation 保留原正常命令計算，可抽純需求計算 helper 供銜接使用；不得讓 preview 呼叫推進 NavigationAgent 路點。handoff 真實 refresh／next-point 查詢由 Navigation 擁有，不從 Predictor 做。hold 與 drive 記錄各自正常意圖，停止面敵的銜接以安全朝向與已完成前移為準，不強迫已達作戰距離者繼續追擊。
10. **診斷**：Navigation trace state 新增 `recovery` 字典：`blocked_origin`、`escape_heading`、`advance_origin`（Vector3）、`advance_metres`（float）、`phase`、`handoff_count`、`handoff_reason`、`handoff_frame`。成功 drive 原因為 `safe_nominal`，hold 為 `safe_hold`；count 同 Navigation 生命週期單調累加，交回 normal 後保留，full clear 可清空。Predictor trace 候選附 profile heading／phase／預測前移量與 horizon，仍由 recorder 既有通用序列化承接，不修改 recorder 或新增另一套記錄。

## 封閉實作範圍與相依

Production 限 `src/ai/tank_recovery.gd`、`tank_navigation.gd`、`tank_driving_predictor.gd`。新增或更新必要測試／文件可行；CombatAI、Controller、recorder、scene/tres/assets 不改。實作前先保留真 case 原版本的全流程紅燈；資料若不能重現，不假造紅測或直接假定 fixture 正確。

Threat model：可信本機 Godot、平面街區、既有車型／碰撞、玩家記錄軌跡。Non-goals：未來砲塔瞄準預測、砲塔接管、全域規劃器、導航烘焙變更、降低碰撞精度、無限重試、所有街區完備解、動態玩家意圖預測、多人與任意坡地。

## 固定驗收矩陣

- H1 真記錄 Tank2＋使用者街區＋原瞄準行為：原版本重現退後回原處／terminal；新版完整跑到實際 turn/advance、安全 handoff，再正常導航至少 10 秒，不能又回原受阻點 0.5 m 內或 terminal stuck。敵車只初始化一次姿態，不能 teleport；玩家有限記錄回放需明示不是確定性 replay。
- H2 無 contact 的左右鏡像障礙：包含砲管，profile 的轉動或前移任一段受阻均不可放行；只有轉得動但前移不通不算有效候選。選定方向不能每幀偷換側。
- H3 全阻擋／無有效 profile／銜接不安全：按硬期限與最多兩次額度安全停止，不回 normal 洗重試。取消／換目標／換車依既有生命週期清理。
- H4 原 movement/navigation/predictive/contact/last_seen 回歸不改弱；原 recovery/corner 若斷言「無contact退完立即normal」與新裁決衝突，先保留具體失敗證據，再只更新該已變更語意，其他物理／上限斷言保留。
- H5 F4 trace 可看到新 phase／heading／handoff 原因；使用者街區／導航資源 SHA 不變。Windows 正常載入，新code可 F6 試玩；已確認舊版同樣存在的渲染退出錯誤不擴入本單。

## 修訂依據

使用者已核可選向完整預檢可超過 3 秒且設上限，實際執行仍逐幀預測 3 秒。依真實 Tank2 純動力公式 60 Hz 推算，保持原轉速及操作規則，30° 全動作約 5.1833 秒、60° 約 7.8000 秒；60° 轉到容差約 6.1000 秒。故取選向 10 秒、turning 7 秒；含倒車及最多 3 秒銜接的 attempt 取 16 秒。這些是時限調整，不是加快坦克或放寬碰撞。目標使用者、用途及產品定位未變；原 3 秒內完成的矛盾由此修訂取代，不重開第三輪設計 review。

## 複審與交付

已採納原生獨立設計 review：不依賴真contact、共享預算的 staged trajectory、真實正向進展、nominal-only交接、鎖定heading與有限deadline。內部門檻依上列數值鎖定。外部 Claude 傳送曾遭拒，不重試。最多兩輪設計review；實作／fresh-context驗收分離。若原AC仍失敗或需砲塔接管等 scope 外能力，停下回報，不繼續微調候選洗綠。
