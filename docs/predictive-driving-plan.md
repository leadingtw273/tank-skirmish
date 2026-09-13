# 3 秒預測駕駛：封閉試玩範圍

## 鎖定前提與 ADR
目標使用者為 Windows PC 單人坦克玩家，leadi 在訓練場驗收；產品優先，不製作通用機器人框架。沿用 NavMesh 路線＋自訂駕駛的類比；目標是減少建築角落的反應式卡住，同時處理玩家追撞。四問依既有產品定位及本次討論覆核，沒有改變使用者、產品定位或動機。

背景：縮窄 navmesh 半徑使宅口可通，但位置路線不保證長車身轉向可行。使用者核可正常照路開、預測未來 3 秒內碰撞時才修正、實際受撞後重新評估，持續卡住才有限次脫困。

決策：新增只輸出 body command 的局部預測駕駛。正常追擊與停車面敵共用，最後仍交 Controller 真實物理。當下完整車身／砲塔／砲管納入 snapshot，不模擬未來瞄準；每次以最新姿態重建預測。危險時比較有限候選，不建新全域路線。

否決：改成全域 Hybrid A*/lattice（成本超本次）；恢復直通捷徑（已明確移除）；只檢查第 3 秒端點（會漏中途碰撞）；碰到立即固定倒車（玩家追撞時方向可能錯）；此次加長既有倒車距離／時間（使用者暫緩）。

影響：Controller 提供唯讀動力與形狀資料；駕駛預測／選擇操作；Navigation 持有既有 recovery 預算；CombatAI 保留唯一命令提交與生命週期停止。瞄準、射擊、作戰距離、烘焙半徑、使用者地圖不變。

## 澄清與詞彙
- 正常移動：NavMesh 找路，駕駛提出油門／轉向；使用者已確認。
- 預測視窗：未來 3 秒整段，短段執行後重評估；使用者已確認。
- 姿態快照：當下完整碰撞形狀，未來砲塔瞄準不預測；使用者本輪明確確認。
- 接觸重評估：實際受撞後不用舊預測；前方有空間可駛離、受阻先停，不能每次接觸重置重試預算；使用者已確認。
- 動態邊界：不預測玩家未來軌跡，接觸後以其當下形狀作障礙檢查；不保證防止所有動態碰撞。
- 細部取樣、候選及效能參數為本次實作可調內部細節，不是新的產品義務。

以上已回答的兩個子系統交互與姿態問題依本次對話記錄，不重問已核可方向。術語「預測駕駛」「接觸後姿態重評估」已登記共通 TERMINOLOGY.md，四問覆核維持產品優先的同一定位。

## 獨立計畫複審裁決
外部 Claude 唯讀傳送遭權限檢查拒絕，未繞過；改本環境原生獨立模型複審，缺跨供應商第二意見。四項採納：Controller 共用動力 snapshot/pure-step；self 與承載地板精確排除；hold 讀最新接觸（靜止載具不能只依賴自身 slide）；Recovery.observe 保留原始需求，修正後煞停不可洗無進展計時。查詢硬上限與量測納入試玩驗證，不新增 FPS SLA。

## 有限實作與安全條件
1. 基於同一加減速與角速度積分，產生 0–3 秒根節點軌跡；所有部位相對根節點保持當下姿態。平面訓練場適用，不新增坡地運動模型。
2. 檢查中間姿態與移動掃掠，不能只比端點。排除自己與承載地板，保留靜態牆、柱、建築；偵測接觸後納入接觸載具當下形狀。真實物理 guard 不放寬。
3. 安全且無接觸的正常命令原樣保留；有風險／接觸才比較減速、低速調向、停車調向與煞停。短倒車只作安全調整候選／既有脫困，不改正常近距戰術。
4. 候選需通過相同檢查，優先維持路線進展／解除接觸；沒有安全候選時停車。限制候選與取樣數，記錄查詢次數／耗時，試玩不以全局大搜尋卡頓。
5. 持續安全煞停不得抹除原本的無進展需求；仍可進入既有最多兩次脫困，重複接觸不重置預算。stuck 保持停車，目標改變沿用原本重試語意。
6. 預測不直接改 transform／velocity。停用、死亡、換目標／換車立即清除狀態及命令；取消停止出口不得再啟動安全調整。

## 固定驗收矩陣
P1 空曠處原始命令不變；四車動力軌跡以無障礙實體短程比對（允許離散積分誤差，明列數值）。
P2 3 秒端點雖清空但中間穿越薄牆必報風險；包含移動及原地轉動車尾／砲管掃牆。
P3 左右凸角真實物理：碰撞前介入並改變命令，不穿牆，開放逃逸空間案例實際有前進／姿態進展，不只看 command。
P4 玩家車從後方接觸停止敵車：前方空曠時重新評估且安全駛離；前方牆阻擋時不可向牆硬開；無玩家未來運動預測宣稱。
P5 接觸持續受阻時有限重試後停住，同目標不可因接觸反覆重置；取消／換車清舊操作。
P6 現有 corner/recovery/movement/navigation/navmesh_gap/contact/motion_guard/last_seen 回歸；不修改地圖、射擊、索敵、半徑。保留 movement smoke 已知偶發 A1 不穩的原始證據，不能以 retry 抹掉。
P7 使用者新街區場景載入；記錄單敵車預測成本／查詢上限；Windows 編輯器可 F6，保留其手工場景。

## 實作順序與驗收
先盤點唯讀API與測試介面，再實作預測／接線和有限測試。實作者跑 targeted；fresh-context 獨立驗收。不同 worktree 不共用 Godot process；使用者素材與街區保留在交付副本，不混入程式提交。不推送、不合併、不建立外部工單。

原 threat model：可信本機 Godot 與既有資產、平面靜態街區及一台玩家接觸。非目標：多人網路、惡意資料、任意地形、完備導航、所有動態避撞、通用框架。review 只阻擋以上有限 AC 的具體反例。

## 基線證據
獨立完整資產／匯入快取工作樹 `/tmp/tank-skirmish-predictive-validation`，HEAD `90bd4f9`，尚未套用預測程式時執行 `enemy_movement_smoke.gd`：RC 0，`A9_RECOVERY attempts=2 actual_reverse=true final_status=stuck`，A1–A11 指定案例 passed。log `/tmp/predictive-baseline-movement.log`。這次基線可有效載入資源，不沿用上一輪缺匯入資源的無效對照。

## 驗收黃燈與範圍收束
- 原目標仍為完整當前碰撞姿態的 3 秒預測駕駛、接觸後重評估與有限脫困；不新增功能、全域規劃器或新效能承諾。
- A／原驗收 P3：修正測試前牆座標後，左右凸角均耗盡 4096 次查詢且無實際進展，屬直接 blocker；先定位重複查詢，不提高上限掩蓋。
- B／原驗收 P6：正常 hold 把 arrived 覆寫成 holding，是狀態整合回歸；保留原抵達狀態，只在實際調整時覆寫。
- D／測試幾何：先前 P3、P4 前牆座標符號錯誤，相關舊 PASS 撤回；修正初始幾何 gate 後重新驗證。
- 舊 rear-wall 測試要求向僅 0.25 m 外的牆倒車接觸，與本次碰撞前介入語意衝突；改為分別保留底層真實倒車碰撞防護，及上層預測安全攔截／原重試預算，不以強迫碰牆換取綠燈。
- 原 navigation 回歸 RC 1 仍待定位；所有舊通過結果須對齊最終程式版本。沒有新增驗收義務，也不把較短預測視窗當成修正。

## 修正後 targeted 證據（尚待最終獨立回歸）
- 原 navigation Tank2 失敗已由實跑 trace 定位為同一查詢額度耗盡：有效 route 下零命令持續無進展，最後兩次脫困後 stuck；沒有新增尋路方案。
- 每 0.1 秒區段先整合原有全部微步姿態，建立完整各部位的保守掃掠 world AABB；範圍清空才跳過細查，命中仍保留每個 convex 的平移 cast 與旋轉姿態檢查。3 秒、2 cm、4096 次與 20 ms 閘未放寬。
- 作者 targeted `enemy_predictive_driving_smoke` RC 0；P3 左右實際前進各 17.905 m、19 次非 budget 介入、0 budget、無穿透。末筆 136 次查詢約 4.3 ms，這是樣本數據，不是所有幀或所有硬體的效能保證。紀錄 `/tmp/predictive-driver-impl.log`。
- `enemy_recovery_smoke` RC 0；底層真後退碰牆不穿透、上層預先攔截與自然 settling 分別驗證。新增 arrived_hold 維持 arrived 與零移動。
- 使用者街區場景 headless 載入並執行 180 幀，RC 0，無錯誤；紀錄 `/tmp/predictive-user-scene.log`。舊副本全部 14 個未提交資產／場景檔逐一 cmp 與交付副本相同。

## 最終回歸紅燈：凍結，不交付
1. 原目標：保留 NavMesh 尋路，新增當前完整碰撞姿態的 3 秒預判與接觸後調整，做到可試玩；目標使用者、Windows 單人遊戲定位與動機均未改變。
2. 最小安全閉環：新 core、recovery、corner、movement 已獨立 RC 0，但既有繞建築及部分可達終點尚未全部通過，不能以新單測綠燈宣稱可交付。
3. 分類：最終 `enemy_navigation_smoke` RC 1 是 B／原 P6 的 L1 直接回歸；Tank1 stuck 距 71.232 m，Tank2–4 arrived；部分可達終點 stuck 距 14.620 m，A9 兩項失敗。紀錄 `/tmp/predictive-validation-final-enemy_navigation_smoke.log`。不是新增驗收，不能略過或弱化。
4. 延後：全域新尋路器、未來瞄準／玩家動態意圖、任意地形、FPS SLA 等仍不納入。效能修正不是加入上述義務的授權。
5. 仍有直接 blocker：停止 production/test 修改，保留失敗現場；僅完成既定唯讀診斷與回歸證據，待範圍檢討及使用者裁決下一個封閉修正。Windows 編輯器維持原可試玩副本，不切到失敗版、不提交為完成。

## 使用者核可後的封閉續修（2026-09-11）
使用者明確回覆「繼續，直到我可以測試為止」，核可針對 A8／A9 繼續修正、驗證與通過後切換編輯器。定位與動機維持不變；沒有增加產品功能或放寬碰撞要求。
- A8：實跑已證明 20 ms watchdog 耗盡造成零命令／無進展。只消除重複幾何運算與查詢工作，不提高上限、不減少完整形狀與掃掠。
- A9：先對既有部分可達場景留下 waypoint／command／predictor／recovery 的直接 trace；不假定與 A8 同因，依證據修正。
- 允許修改既有 predictor／controller／navigation 的直接缺陷；不修改正式測試門檻、使用者地圖、資產、索敵、射擊、導航半徑。新機制或公開語意改變須另行裁決。
- AC：既有 navigation 單次 RC 0，四車 arrived ≤3 m，partial_end 且連續五秒停止；原九組測試維持通過。使用者街區場景實跑後，安全切換 Windows 編輯器供 F6 驗收。
- 查詢／預測上限、兩次脫困預算與生命週期不變；不納入任何 L3 泛化。外部模型傳送仍未獲單獨授權，沿用本環境獨立驗證，不繞過權限。
- A9 trace 補證：後段 4096 次硬上限中 3983 次為 narrow 查詢。replan 後路線變長是觀察，尚不能證明需要「鎖定 partial endpoint」的新政策；此建議暫不採納。先以原生 AABB 運算取代腳本逐角迴圈，並在多 convex 部位範圍命中後，再以各 convex 的保守區段範圍排除無碰撞者。仍以完全相同的掃掠檢查驗證所有可能命中形狀，再跑原 navigation 裁決。
- 最佳化後確切 A8 原因：baseline tick 974、距 next 約 1.9 m，安全低速候選的 3 秒末端越過 next，score 為 -0.212；原地轉向因絕對 heading 得 +0.032 而提早獲選，實際 command=(0,-0.4)。不是物理 guard 阻止前進，也不再是 budget。紀錄 `/tmp/predictive-navigation-baseline-candidate-diagnose.log`；在使用者新地圖的先前成功重播不能取代此 baseline 證據。
- 鎖定最小修正：安全資格仍以完整 3 秒全形狀軌跡判定；只把安全候選的路線進展評分改為當下實際執行 delta 的同動力預測姿態，heading 用相對初始姿態的改善值。安全且正進展即可短路返回，停車不能只靠絕對朝向得正分；不改尋路／部分終點政策、候選集合、碰撞精度或脫困上限。
- 評分修正後原 navigation RC 0：四車 arrived，距目標 2.738／2.753／2.765／2.749 m；partial_end 距原目標 7.787 m 並通過五秒保持，紀錄 `/tmp/predictive-score-navigation.log`。
- P5 正確 fixture 證據：t=10–25 秒位移與速度皆 0，但安全 turn ±0.4 的角度變化不斷重設 recovery 進展窗；不是可繞單牆的有效行進，紀錄 `/tmp/predictive-p5-trace.log`。僅新增 observe 的 optional `allow_heading_progress=true`；navigation 在安全介入時傳 false，真實位置進展仍計算，正常路線原地轉向保留舊行為，接觸法線與真實車頭資料不變。正式測試及兩次上限不改。

## 最終驗證結果
凍結整合版獨立驗證九支測試全數 RC 0：predictive_driving、recovery、corner_recovery、movement、navigation、navmesh_gap、contact_response、motion_guard_wall、last_seen_target。報告 `/tmp/predictive-release-validation.md`，紀錄 `/tmp/predictive-release-*.log`。
- P3 左右各前進 17.905 m、19 次非 budget 介入、0 budget、無穿透；P5 恰兩次後 stuck，同目標取消不補額度。
- 四車分別 arrived 於距目標 2.738／2.753／2.765／2.749 m；部分路線回 partial_end，並保持五秒停止。
- fresh-context 程式碼複審 PASS，報告 `/tmp/predictive-release-review.md`。重複公開 set_target(same_object) 的冪等性列 backlog：目前正常 production 無重複呼叫入口，非本單新增義務。
- 使用者街區場景執行 180 幀 RC 0、無錯誤，紀錄 `/tmp/predictive-release-user-scene.log`；14 個使用者修改檔案與原副本逐一 cmp 一致。`git diff --check` 與 `node --check scripts/quality.mjs` 通過。
- 已知限制維持原 scope：不預測未來砲塔瞄準、玩家未來運動或任意地形；原生複審不冒充外部 Claude review。尚待使用者實際試玩驗收，不宣稱完整全專案 CI 或硬體 FPS SLA。
