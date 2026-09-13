# 卡住事件三次額度

使用者核可：每次獨立卡住事件最多三次；真正恢復正常追擊後事件結束，下一次卡住重新三次。短暫移動、重算路線或切換狀態不補額度。三次失敗停車，目標明顯改變才重試。延續現有單人訓練場載具 AI，不改路徑／姿態／物理策略。

## 鎖定合約

- Recovery 的 MAX_ATTEMPTS 改為 3。attempts 是當前卡住事件使用次數，不是整段導航累計。
- handoff 仍可立即返回 normal 以繼續行駛，但不歸零額度。
- 以獨立 confirmation window 確認事件結束：normal、原始 nominal movement > .05、沒有 controller contacts、predictor contact=false 且 intervened=false；連續至少 3 秒且從確認起點實際水平位移至少 .5m，才結束事件並清 attempts。沿用既有時間與位移尺度，不共用 stuck detector 的計時器。
- confirmation 起點不得用 escape advance_origin；從 handoff 當下位置或下一個有效確認幀開始。任一不合格幀／hold／取消動作／重新算路打斷確認窗，但保留事件與已用次數。轉向、倒車、只切 phase 不構成成功。
- 同一 target 的可見／失視、generation 改變、路徑更新，均不得重置事件。genuine target replacement、停用／死亡／换車維持完整清理；重複 set_target 同 instance 不得洗額度。
- 首次 terminal stuck 時鎖定當下導航目標位置。之後同 target 的新目標須相對鎖定位置水平距離 >=3m 才解鎖，generation 改變不算；終止期間不覆寫鎖定位置。hidden 仍僅使用 last-seen，不能讀隱藏玩家現址。
- 一般路徑更新不得補額度；已終止非 stuck 的 arrived/no_path/partial_end 可依既有路徑重試規則處理，但不能藉此洗未完成事件。
- CombatAI 刪除 blocked-goal 欄位與 3m retry 分支，由 Navigation/Recovery 統一管理；CombatAI 仍管理目標、作戰距離、武器姿態。
- 使用既有 trace dictionary 增加 episode active／confirmation／locked stop goal 診斷，不改 recorder schema。

## 範圍

Production 只改 src/ai/tank_combat_ai.gd、tank_navigation.gd、tank_recovery.gd。不改 Predictor/Controller、NavMesh、使用者街區、guard、車速、砲塔策略、單次脫困動作與期限。既有兩次常數／相關精確斷言與測試時間上限可因核可三次更新，其他安全條件不得弱化。

## 有限驗收

E1 handoff 不立即補滿；3 秒與 .5m 兩條件均成立才結束；不足任一條件不清 attempts。
E2 intervention/contact/hold/零或負需求、route refresh、可見失視、generation、取消動作均不補額度。
E3 同事件 1/2/3 後停車；未完成確認又卡接續累計；確認後別處卡從 1 開始。
E4 stop goal 首次鎖定；<3m/generation/y 變化不解鎖，==3m 解鎖且新事件；hidden 不偷讀玩家。
E5 真 target replacement／停用／死亡／換車完整清理，同 target 重送 preserve。
E6 travel pose、driving reintegration、escape handoff、last-seen、predictive、enemy movement 有限回歸。舊碼「額度不清、只有兩次」行為先紅測，不以缺 API 代替。
E7 未參與實作代理獨立驗收；Windows 短場景/F4 核對新 hash，已知 renderer 退出錯誤另列，不宣稱全套無錯。

原 enemy_combat blocked-muzzle assertion 已在精確舊碼重現，非本次修復範圍。不得新增 planner 或調整避障方向。若前提無法落實，停手報具體差異，不擴大本單。
