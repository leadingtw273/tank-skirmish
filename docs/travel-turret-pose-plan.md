# 追擊時砲塔回正：封閉實作

2026-09-13 使用者核可：失去視野且有追擊／脫困意圖時，砲塔朝車頭；重新可見恢復瞄準；停止守望沿用最後位置瞄準。此為明確核可的新武器姿態策略，沿用 NavMesh、專用駕駛、單人 Windows 訓練場與產品定位，不改尋路／脫困架構。

## 證據

最新使用者 session `2026-09-13T01-02-03-309062`，F4 frame4925。最後 fresh prediction frame3991：gun/shape14 cast_motion 約1.8545秒阻擋，collider未知；AI不可見仍每幀aim_last_seen。終局砲塔local yaw約-80.880°。此證據支持調整移動姿態，不證明回正必能解除所有卡住。

## 鎖定行為

1. 可見目標：完全沿用現有選點、瞄準、開火及追擊規則。
2. 不可見但有受擊inspection：完全沿用既有優先度與行為。
3. 不可見、有最後世界位置、且導航尚有移動意圖：砲塔**水平**朝當前車頭逐步回正。相對車體的回正，不是固定世界方向；車體轉向後每幀重算。保留目前砲管俯仰，不加入新俯仰控制。
4. 移動意圖定義：距最後位置超過既有搜尋到達距離，且不是該goal/generation的terminal。包含尚在原地轉向、預測煞停、倒車／脫困；不看瞬時車速或目前movement是否非零。不從 `_pursuing` 判斷，該欄位僅服務可見目標的距離帶。
5. 到達或同goal/generation terminal（arrived/partial_end/no_path/stuck）後，恢復原本最後位置觀察。若 terminal 於本幀 drive 內首次產生，下一物理幀才切回觀察，避免 predictor 後再次改姿態。新goal/generation仍沿用既有重新嘗試規則，不因回正重置額度，不讓terminal自動復活。
6. 姿態更新在 navigation.drive/predictor 之前，使用 Controller 現有 `aim_turret_at()`（遠處車頭方向虛擬瞄點），完整turret/gun joint guard、速度/限角不變。禁止直接寫rotation、瞬移、disable碰撞或新增安全例外。
7. 回正與車身移動可並行，原body predictor依當前姿態決定安全命令；不新增「一定等到完全回正才能動」階段。回正若被guard擋住，保留現有有限body recovery，不能承諾必定脫困。

## 邊界與介面

- Production只允許 `src/ai/tank_combat_ai.gd`、`src/ai/tank_navigation.gd`。Navigation只新增唯讀 `is_terminal_for_goal(goal,generation)` 查詢，以原 `_terminal`／generation／`RETRY_GOAL_DISTANCE` 判斷，不推進agent、不建立route、不改任何控制或額度。若抽出純新goal判斷供drive/query共用須行為完全不變。
- CombatAI唯一擁有瞄準／travel姿態策略。用現有turret pivot與車體forward形成虛擬遠點，最後世界位置絕不被該虛擬點覆寫。
- AI trace新增姿態模式（visible/inspection/travel/last_seen/idle），由既有通用recorder序列化，不改recorder或新schema；生命周期停用／死亡／換車清姿態意圖，不改載具保留姿態語意。
- Controller、Predictor、Recovery、VFX、場景、NavMesh、車速、旋轉速率、query預算與兩次脫困額度不改。
- 保留所有既有dirty資料。Threat model：可信本機、既有車型／平面街區。Non-goals：新姿態搜尋器、未來瞄準預測、砲管收縮、全地圖完備脫困、多人／坡地、音效裝置修正。

## 有限驗收

- T1：最新記錄的preterminal追擊姿態建立舊碼紅燈。新版live AI於不可見且追擊時，guard允許的情況下相對yaw往0收斂，lastseen世界位置不變；記錄真移動／phase／是否terminal，不能用只回正宣稱所有卡住已解。
- T2：有限policy矩陣：可見仍瞄準／可開火條件不變；inspection優先；不可見追擊但speed=0仍travel；到達／terminal仍lastseen觀察；新goal不被舊terminal阻擋；車身轉向後回正相對方向更新；生命週期清理。
- T3：真Tank砲管回正路徑有牆時，joint guard阻擋/限轉、不穿牆；無牆可逐步回正。不得拿瞬移角度或stub guard作通過證據。
- T4：既有 last_seen_target、enemy_combat、enemy_movement、enemy_predictive_driving、escape_handoff_repro 回歸。只有舊「失去視野仍移動追擊時一定瞄lastseen」斷言可依核可語意精確更新；保留最後位置記憶、目標優先、射擊門檻與位移安全。其他矩陣若static確認無影響可沿用前次同hash證據，新增phase變更則重跑原相關測試。
- T5：fresh-context獨立驗證、scene/nav/Controller/Predictor/Recovery hash不變；Windows正常場景/F4載入新碼，保持編輯器與街區。已知音效裝置／renderer stderr另外揭露。

## 執行

先保留T1原碼紅燈，再做兩檔最小實作；新測試與正式碼分工，單一Godot engine lease，隔離XDG/fixed60Hz。已核可策略的局部實作可執行；若最新姿態仍無法通過，不自行加砲塔避障選角／改NavMesh等機制。外部Claude曾遭拒，使用原生獨立review／驗收，不聲稱跨供應商意見。不為更名重置同一產品義務的失敗歷史。
