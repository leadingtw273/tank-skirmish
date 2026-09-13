# AI review 修正驗證

## 核可與變更

- F1：事件成功確認時清除 `_failed_heading` 並還原 `_attempt_side`，新事件候選不繼承上一事件失敗方向；同事件未成功時仍保留過濾。
- F2：同 target 可見／失視切換保留目前脫困 phase、方向、計時與已用額度；後續路徑可預先更新，但不得中斷被保留 action，近距離目標也不得提前 arrived；安全交接後才採用導航。inspection／真正換目標／死亡／停用／換車維持原取消合約。
- F3：continuation 預測結果缺 safe 時0/0，trace `invalid_continuation_result`與`missing_safe`；合法 waiting 仍 waiting，safe=true、safe=false blocked/budget 保留原語意。

## 範圍與 frozen hashes

- Recovery F1 `4ff3204b93ba6769159af0031d6382e9ca88248580723079399f71f574344bf0`
- CombatAI F2 `1cce66a9e40a1c689d66804fc46a74e2e7aab804c351e261ecf414e2c1dc7d45`
- Navigation F2/F3 `d7d7469d124572c980b819e8d982bd98330e6b8907e05201deb927bd7faf7c76`

Controller／Predictor／使用者場景與 NavMesh hashes 均與修改前一致；沒有改三次額度、3秒＋0.5m確認尺度、16秒單次期限、候選角度或砲塔姿態規則。

## 測試證據

- F1 新跨事件回歸：舊production RC1，修後RC0。同事件排除失敗方向，新事件與full-reset控制組同四候選。
- F2 真CombatAI/Nav/Tank2/NavigationAgent/production predictor＋可控Vision：兩個可見切換方向×三 phase，共六組 metrics；近目標及後續路徑更新、inspection／disable／換車邊界通過。before 只有靜態取消證據，未重建引擎 before red，不宣稱完整輸入重播。
- F3 FakeTank/FakePredictor seam：保存before Navigation 的缺safe非零命令真紅RC1，final RC0；missing/waiting/true/blocked/budget皆驗。
- 未參與實作代理獨立重跑八案全RC0：visibility_continuation、continuation、episode、episode_lifecycle、travel_turret_pose、driving_reintegration、escape_handoff、enemy_predictive_driving。SCRIPT ERROR／ERROR／FAIL掃描皆空。
- 獨立報告 `/tmp/recovery-final-acceptance.md`；F1 `/tmp/recovery-history-fix.md`；F2/F3 `/tmp/recovery-continuation-impl.md`；可見性metrics `/tmp/recovery-visibility-final.log`。

## 使用者實測驗收與交付狀態

使用者已完成人工驗收：可見／失視切換中的脫困延續、三次事件額度與安全交接、缺 safe fail-closed，以及既有砲塔／搜索行為皆依本次有限驗收核對。此紀錄是已實測驗收，不等同全套自動化、所有地圖或所有 renderer 環境皆無錯；PR 尚待合併。

Linux有限矩陣已通過。Windows正常場景PID42676、遊戲RC0，log `/tmp/travel-pose-windows-20260913-151606.{out,err}.log`。F4自啟PID49120，frame107收到標記後持續120個physics frames，遊戲RC0且TRACE_ROTATION_WINDOWS PASS；log `/tmp/trace-rotation-windows-20260913-071657.{out,err}.log`。

F4 session `2026-09-13T07-17-02-304953` header核對本文件三個finalhash與未變scene。仍有已知Texture RID／RenderingServer退出錯誤，因此F4 wrapper因stderr ERROR回RC1，不描述為乾淨退出。保留原編輯器與街區，可F6重新試玩，異常F4。

上述 F1–F3 驗收時，既存 enemy_combat 射擊測試紅燈與 renderer 退出訊息尚未處理；enemy_combat 後續結果見下節。仍不宣稱所有地圖都不會卡住。

## 收尾追加：射擊測試情境修正

使用者另核可釐清並最小修復上述 CI 阻擋項。乾淨提交快照中，原案例重新啟用 AI 後會追擊，砲口由 `(54.11342, 1.713215, 7.96995)` 移至 `(52.75985, 1.713215, 6.71814)`，不再維持固定世界擋板的前提；原案例 RC1，並非已證實穿牆射擊。

僅調整 `enemy_combat_smoke.gd`：隔離射擊案例的車身速度，保留物理更新及冷卻；90 幀逐幀驗證擋板首命中、視野暢通與零射擊。失視案例改驗最後目擊世界位置不追讀隱藏玩家，取代已被追擊砲塔回正規格淘汰的「全程 yaw 不變」；保留失視零射擊與重新可見恢復射擊。

修後單案 RC0，獨立 diff review 確認未弱化阻擋規則。遊戲程式未改。完整 CI 與合併狀態另以最終交付紀錄為準；renderer 退出問題不受此測試修正影響。

同輪完整 CI 接著發現 `enemy_corner_recovery_smoke.gd` 的 concave 失敗分支缺一層縮排；修正後確認舊 1200 幀視窗會在第三次倒車中提前結束。只將觀測窗對齊既定 `MAX_ATTEMPTS * ATTEMPT_SECONDS`（48 秒，另給三個切換幀），不改遊戲期限或額度。修後左右凹角皆 `blocked / attempts=3 / penetrated=false`，凸角皆完成轉向、前進及交接，單案 RC0；獨立 diff review 確認所有安全斷言保留。

本機完整 CI 前段已通過至 enemy_recovery；修正 corner 後採單案及剩餘項目接續驗證，不冒稱最終快照已在本機一次全套通過。最終完整 gate 以 GitHub 同 Head 的 quality 結果為準。
