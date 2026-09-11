# LEA-174：索敵優先序與最後目擊位置 — 實作計畫 v1（本機修正版）

## 狀態與權威

需求已由 leadi 逐題核可並記錄於 Linear LEA-174（3453fb32-8a34-4cef-8d8b-b2c1a7b91368）。原稿已完成一次跨模型複審；依 leadi 同意，後續修正僅在本機進行，不再外送複審。leadi 已於 2026-09-11 核可實作、在 Windows Godot F6 回覆「驗收成功」，並於架構 review 後明確要求「可以，收尾」。實作與本機驗證已完成，正式合併仍須通過同一 Head 的 CI 與既有 review gate；不啟動無人 Job。

基準為 Tank Skirmish main `a8feb7cf101339f9e20b472279fe12ded7fc0ac7`。LEA-173 已合併並完成驗收，不重開；砲塔雙向選路已取消，不復活該方案。

## Context／四問覆核

- 目標使用者：leadi 在 Windows Godot 親測的單人坦克遊戲；未新增多人、運維或外部服務使用者。
- 類比：既有戰鬥 AI 的最後已知位置記憶；不是通用 AI、感測或搜尋框架。
- Identity：產品優先 Tank Skirmish，優先清楚可玩的行為。
- 動機：短暫目擊後反應合理，並保留未來觀察者移動時仍可指向同一地點的位置語意。移動追蹤本身不在本單。
- 依本次澄清覆核，上述前提與既有產品定位不變；本單是既有 AI 決策的局部增量。

## 已鎖定行為

1. 優先順序：當前實際可見敵人 ＞ 受擊側查看 ＞ 最後目擊位置。可見沿用 Vision 的範圍與遮擋結果，不以紅色預覽代替。
2. 最後位置是最後看見玩家時的穩定車身中心世界座標，不是方向、相對向量或選中的部位瞄準點。只露出炮管亦記車身中心。
3. 失視後凍結位置，不追讀隱藏玩家的位置；不設遺忘倒數。轉向該位置並保持；觀察者若改變位置，仍重新計算看向同一世界座標。
4. 失視時只瞄準，不請求開火；重見後沿用目前部位選點、砲口對準及 first-hit 開火閘門。
5. 失視期間觸發既有受擊側查看時，取消舊位置意圖，查看後不自動返回。看得見玩家時不被受擊側查看搶走；再次看見可建立新記憶。
6. 沿用完整瞄準：砲塔水平、砲管俯仰與固定砲塔車身輔助轉向；不向前移動，保留機械限角、死區與碰撞守門。目標位置不可達時不承諾強行對準，不新增選路。
7. 敵車自身死亡、目標更換／死亡、戰鬥停用時清除記憶；重生、換車或恢復戰鬥不能恢復已清除記憶。

## 最小資料與責任

- 只在 `src/ai/tank_combat_ai.gd` 擁有兩個私有值：最後目擊世界位置 `Vector3` 與「目前有可用記憶」布林。不得用 Vector3.ZERO 判斷有無記憶，世界原點是合法位置。
- 此布林同時代表可執行的舊位置意圖；受擊查看或 lifecycle 清除後不保留另一份可復活的歷史目標。沒有新增 Node、Resource、enum 狀態機、計時器或 registry。
- Vision 仍只提供當前可見性與穩定中心；不把最後目擊記憶寫回 Vision。Tank controller 仍只執行既有瞄準／碰撞，不認識記憶。
- 共用一個小型私有瞄準 helper（如需要），依序呼叫既有 `aim_turret_at` → `aim_gun_pitch_at_target` → `_apply_hull_aim_assist`，因車身輔助會讀取水平瞄準產生的狀態；可見分支保留原開火判定，記憶分支必定 return，不能穿透到 fire。
- 保留既有 `_inspection_direction` 名稱與受擊查看語意，避免破壞既有測試的欄位讀取。

## 每次 physics 更新的順序

1. `_can_operate()` 不成立：清除記憶與受擊查看、停止輸入，return。涵蓋有效性、存活與戰鬥停用；不能先對失效節點求中心。
2. 一次 `visible_target_points(target)` 查詢。非空：另以 `vision.call("target_world_position", target)` 取得穩定車身中心更新記憶，清除查看意圖，沿既有可見部位選點／完整瞄準／開火流程執行。不可使用 `visible_points[0]` 作為中心：中心遮住時，第一點可能是可見部位點。此中心讀取不增加第二次可見性查詢；失視分支不得呼叫它。
3. 沒有可見點：若有受擊查看方向，執行既有查看；否則若有記憶，對保存的世界位置執行完整瞄準；否則取消瞄準。三者互斥，失視分支不發 fire。
4. 到達記憶位置方向後不刪記憶，持續將同一世界位置交給原瞄準入口，讓機械死區停止輸入，也容許觀察者移位後重新求角。不能以「已轉完」凍結成方向。

## 事件與 lifecycle

- `set_target`：沿現有切換入口先清掉記憶、受擊查看及瞄準輸入，避免把舊目標位置帶到新實例。
- `set_combat_enabled(false)`：同步清掉記憶與查看，停止輸入；true 只允許後續正常感測，不恢復舊記憶。
- `inspect_hit_position`：保留既有可操作、有效命中方向與當前可見性檢查。當既有受擊查看判定實際接受一個方向時，清除最後位置記憶，再存受擊方向。不要讀攻擊者或建立猜測位置；不擴改前方已在查看範圍內、無需轉向的舊判定。
- 自身或目標死亡／失效：沿 `_can_operate()` 的 physics 清除，以及目前場景已有的 target／combat 重綁入口，不新增死亡事件系統。

## 固定驗收矩陣

| ID | 有限案例與預期 |
| --- | --- |
| M1 | 真 Vision 短暫看到玩家但尚未對準，之後以遮擋或移出範圍失視：敵車繼續轉向當時車身中心；移動隱藏玩家不改保存位置，整段 0 次 ShotEvent。至少含炮管露出／中心遮住的保存中心案例。 |
| M2 | 已有記憶後移動觀察者到另一位置，用幾何期望方向驗證仍指向原世界點，而非舊角度；這是測試移位，不新增 runtime 移動 AI。 |
| M3 | 到達方向後多個 physics tick 記憶仍有效；再次看到玩家時更新中心並回到既有瞄準／fire gate。世界原點亦為有效記憶；無初始目擊時不得朝原點瞄準。 |
| P1 | 看得見玩家時受擊，仍採可見分支並更新記憶，不轉去受擊側。 |
| P2 | 有舊位置且失視時接受側後方受擊，轉向受擊側；查看完成不返回舊位置。之後再次目擊可建立新記憶。 |
| A1 | 四車沿既有完整瞄準入口：可旋轉車型砲塔／炮管、固定砲塔車型車身輔助，movement input 為 0；有限障礙／限角不被記憶分支繞過。 |
| L1 | 自身死亡、目標死亡、set_target 新實例／null、combat false 各自清除記憶；恢復存活／新綁／combat true 後在失視情況不再向舊位置轉向。 |
| R1 | 舊 enemy／partial-visibility-combat／training／contact 與碰撞基線不回歸；僅更新與本需求直接衝突的失視立即停轉斷言，其餘原 assert 保留。 |

驗證以真 Node／Vision／Tank 的有限行為為主，必要的 narrow spy 只驗證是否發出瞄準與開火請求，不用私有欄位值取代所有行為測試。測試可設固定姿態、位置及阻擋；不以刪除斷言取得綠燈。

測試前置條件：M2 幾何方向案例優先使用 Tank2／Tank3；移位後，觀察者砲塔軸心與保存位置的水平距離須大於 3 公尺，避開既有近距離瞄準死區。M3 的原點案例須以 `stable_world_center()` 驗證目標車身中心確實位於世界原點，不能只設定 target.position 為零；觀察者砲塔軸心同樣須距該點水平大於 3 公尺。固定砲塔覆蓋由 A1 負責，不調整產品死區。L1 死亡案例須先經至少一次 physics 更新完成清除，才測試恢復存活；不新增同一 frame 死亡／復活的事件機制。

## Task 1：有限紅測與 AI 實作

- 先新增 `tests/last_seen_target_smoke.gd`（必要 `.uid`），令舊版本在 M1/M2 有真實失視停轉／缺少位置記憶的紅燈；parse error、缺方法錯誤不算行為紅測。
- 最小修改 `tank_combat_ai.gd`，只引入上述資料、分支及清除。可見時的部位選點、射速、傷害與 first-hit gate 不變。
- 若既有 `tests/enemy_combat_smoke.gd` 包含失視必須立刻停轉的斷言，只替換該條為新語意；仍保留失視不開火與重見恢復。
- 新增的位置、優先序與 lifecycle 案例集中於新 smoke；原 enemy smoke 的已對準後失視、不開火及不跟隱藏目標轉動案例保留。不得預先放寬角度容差或弱化斷言；只有實際失敗且證明與本單 AC 直接衝突，才作最小相容調整。
- 串行執行新 smoke 與受影響的 enemy／partial_visibility_combat／training，再執行需要的碰撞回歸。
- 允許產品修改僅 AI 一檔；若需改 Vision／controller／場景 lifecycle，停止並回報具體前提差距，不自行擴檔。

## Task 2：CI 接線與獨立驗收

- `scripts/quality.mjs` 既有串行測試清單新增此 smoke，保留原 suite、error scan、exit gate 及 project.godot 保護。
- 固定 Linux Godot 4.7.1；語法檢查、新 smoke、完整 `bash scripts/ci.sh` 必須 exit 0 且無 Godot ERROR／SCRIPT ERROR。
- fresh-context 執行者逐條驗固定矩陣、scope 與測試沒有弱化，區分親跑與讀回既有證據；失敗只依原 AC 分類。
- 無新 UI 或美術，不要求新的靜圖視覺複審；仍交 leadi 在 Windows F6 實際確認短暫出現／消失及受擊優先手感。

## Task 3：人類驗收與工程交件

- leadi 試玩確認後，集中提交同一張 LEA-174／同一條 PR work line，依 same-head CI／必要 review／merge gate 交件。
- 本次「繼續」是計畫整理授權；正式實作、試玩及發布仍依當次使用者核可接續，不沿用 LEA-173 的已完成工單授權。

## 完整 allowlist 與非目標

- 產品：`src/ai/tank_combat_ai.gd`。
- 驗證：`tests/last_seen_target_smoke.gd`／`.uid`，必要相容 `tests/enemy_combat_smoke.gd`，`scripts/quality.mjs`。
- 文件：`docs/last-seen-target-plan.md`、必要更新原敵方 AI 行為文件及 Linear LEA-174。
- 不改：Vision、Tank controller、geometry、GLB、地圖、相機、VFX、傷害／Health、project.godot 或平台設定。不新增導航、多目標、搜尋倒數、全域 blackboard、通用狀態機、選路、crash／併發恢復。

## Dirty worktree 與執行前置

- preflight 原專案有 `project.godot` 本機差異（編輯器註解與移除一個已明列值）及 Python 快取，均不屬本單；不自動還原、不提交。
- 實作採從基準建立的獨立工作樹，將 AI 變更與完整 CI 驗證隔離於使用者仍開啟的原 Godot 專案。新工作樹只承接本單 allowlist，不把本機設定差異複製成產品基準。
- 人類試玩前明確交付新工作樹的 Windows Godot 專案入口；切換／合併回原工作樹仍須保留使用者尚未提交的設定，不以 reset 清掉。若使用者選擇原目錄試玩，先另行核對並取得設定處理裁決。
- Threat model 維持可信單人本機、固定四車、已鎖定引擎；不因未來移動理由新增導航承諾，不由 reviewer 增加未核可功能。

## 風險與停止條件

- 不能把每次碰到較高優先序解讀為日後自動恢復舊意圖；受擊取消與重新目擊重建必須分清楚。
- 不能用當前選中的可見部位點覆寫最後車身中心，或在失視分支重新讀 target 位置。
- 不以瞄準 helper 重構順便改可見分支開火語意；不必為幾行呼叫建立新跨檔抽象。
- 若有限原 AC 出現反例，修正同一義務並回歸；非目標建議留後續。實作若需要新架構或不同玩法，停止並交 leadi 裁決。

## 唯讀 preflight 證據

- 穩定中心：`tank_vision.gd:72-93` → `tank_controller.gd:230-232`，可以沿用而不改 Vision。
- lifecycle：AI `set_target:20-23`、`set_combat_enabled:27-31`、`_can_operate` 失效分支已有集中入口。
- 唯一直接相容變更：`tests/enemy_combat_smoke.gd:591-607` 固定砲塔失視即停斷言，改為本單位置記憶語意，保留不開火。
- 四車既有案例位於 enemy smoke `:220-230,389-398`；新 smoke 接線位於 quality `:264-280` 的串行清單。

## 複審意見裁決與限制

- 本單需修正：preflight 誤稱第一個可見點必為中心；M2／M3 fixture 必須避開既有水平 3 公尺死區。均已反映於本版，不改玩法或產品責任邊界。
- 採納既有義務的澄清：瞄準呼叫順序、保留 `_inspection_direction`、死亡清除的 physics 時點、統一新 smoke 名稱與測試歸屬。
- 不納入本單：無實際反例的非有限座標防護、額外 motion-guard 遙測機制，以及預先放寬既有測試容差；不把 advisory 轉為新 AC。
- 原外部複審的讀取範圍超過核可清單，已向 leadi 揭露；本版依其同意僅本機修正，未再外送，不能宣稱本版已獲第二輪跨模型 PASS。該修正階段未修改遊戲程式或 Linear；本次另經使用者核可進入實作。

## 實作與人類驗收結果（2026-09-11）

- M1／M2 在基準 AI 上取得真實行為紅測，實作後轉綠；完整 `bash scripts/ci.sh` exit 0，結尾 `Tank Skirmish quality gate passed.`，無 Godot ERROR／SCRIPT ERROR。
- 原生 fresh-context 驗收 PASS、無 Blocking：親跑 AI 語法檢查、新 smoke、partial visibility combat 均 exit 0；其餘 R1 讀回完整 CI 產物，不宣稱重跑第二遍完整 CI。
- leadi 在 Windows Godot 開啟本單工作樹訓練場後回覆「驗收成功」。產品程式與測試在試玩後未再修改；編輯器產生的 project.godot 本機差異不提交。
- 後續唯讀架構 review 無目前 AC blocker。Vision／AI／Tank 的感測、記憶決策、動作執行責任維持；換車與死亡的整合清除路徑已核對。
- 未來加入移動追蹤時，需處理 AI 的 movement=0、車身煞停及轉向命令所有權；這是後續功能的整合限制，不在本單新增導航或仲裁框架。
