# 脫困延續與缺少安全結果的處理

使用者已核可：同 target 可見／失視切換時繼續既有脫困，更新路徑留安全接回；砲塔照既有規則。Predictor 缺 safe 欄位時當幀停車並留診斷。F1 方向歷史修正已獨立完成。

## 範圍

只改 CombatAI 與 Navigation；可新增 tests/recovery_continuation_smoke.gd 與有限 fixture。不得改 Predictor、Recovery（已完成 F1 凍結）、Controller、scene/NavMesh、候選動作、三次額度、16秒期限、砲塔姿態、射擊門檻。這不是一般 planner 優化。

## F2 鎖定合約

- 明確區分 preserve episode 與 preserve action；CombatAI 僅 visible↔hidden 同 target 入口要求保留 action。inspection、真正換 target、停用／死亡／換車照原取消／reset，不一律把 clear(true) 升級。
- Navigation.clear(preserve_episode, preserve_action) 及其後 _start_goal 都不得重置被保留 action 的 phase、attempt/phase timer、heading、failed history 或已用額度；可打斷 confirmation window。
- 使用小型 action-preservation 旗標跨 route clear/start 傳遞；當 action 被保留後，同一次 action 尚未安全交接期間的後續目標／路徑更新亦不得取消它。旗標在安全交接、既有明確取消／full reset 或 stuck 時清除，不能流入未來新 action。
- 邏輯目標更新、NavigationAgent 提前算路均可，但 active recovery 必須在 drive 的 arrived/path finish 前取得控制；抵達與新路線採用留既有 handoff_ready/rejoin 名義評估。
- normal 狀態換路照常；保持同 target 的3次事件與首次停車目標>=3m解鎖規則。

## F3 鎖定合約

- 僅修改 continuation choose_escape_profile 結果入口。真正 predictor 結果缺 safe 時输出0/0，trace reason=invalid_continuation_result，記錄缺少 safe；保留原結果作診斷，不讓原 Recovery 命令透過。
- zero-heading 合成 waiting 顯式輸出0/0、reason=waiting，不標invalid。
- safe=true 原命令不變；safe=false 的 blocked/budget 等仍0/0且保留reason。braking/reversing/settling choose_recovery 原路徑不改。
- 診斷沿 _remember_trace/既有recorder dictionary，不改schema或額外系統。

## 有限驗收

V1 真CombatAI/Nav同target兩向可見切換，braking/reversing/turning分別保留phase/timers/headings/attempts；下一physics step持續原動作，非重啟。測試 seam 可供預測穩定，不宣稱物理回放。
V2 新目標在stopdistance內仍先完成active recovery；後續路徑更新不取消同action；安全handoff取最新目標；normal切換照常。
V3 inspection取消、set_target/disable/death/換車fullreset原語意不變；不改武器pose。
V4 缺safe但含非零movement/turn→0/0且診斷；waiting→0/0非invalid；safe true/false/budget有限矩陣。
V5 episode、lifecycle、travel、reintegration、escape handoff、predictive有限回歸；F1跨事件候選仍正確。先用原碼取得V1/V4行為紅，不以missing新API為紅。
V6 未參與實作代理獨立驗收、Windows/F4確認最新hash。既有renderer退出訊息分列，不修舊enemy_combat紅燈。

只做核可項目。需其他production／新政策則停報，不自行擴大；F2/F3以獨立case驗，不用F1通過冒充。
