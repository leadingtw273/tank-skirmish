# LEA-176 候選剪枝檢查點

## 判定：局部規則已實作，實場效能 FAIL

2026-09-23。不得宣稱掉幀已修復或交付效能驗收。

產品僅修改 `tank_driving_predictor.gd` 的一般候選迴圈：評分提前，在已有完整安全 best 且兩分數有限時，略過不可能嚴格勝出的候選。原命令先驗、高分候選完整 probe、無安全 best 不剪枝、recovery 不剪枝、NaN/INF 不剪枝。3 秒、2cm、4096、20ms、實體碰撞與玩家參數不變。

## 證據

- Claude Opus 指定計畫唯讀複審完成：`/tmp/lea176-candidate-pruning-review.jsonl` 有有效 result、無 blocker。審查建立在計畫而非原始碼；要求分數純函式／嚴格 tie／probe 副作用核對。實作原評分只使用短步命令，不讀 probe 終點；probe 快取與 trace 僅屬當幀計算及診斷，沒有更動 actor 或 recovery 狀態。budget 結果可因省下計算而不同，不聲稱超時情況完全等價。
- `/tmp/lea176-pruning-red.log`：舊碼 exit 1，確實多驗無法勝出的低分候選。
- `/tmp/lea176-pruning-green.log`：新版 exit 0、`PREDICTOR_CANDIDATE_PRUNING PASS`。測試直接走原 `_choose` 迴圈，控制候選與 probe；涵蓋低分／同分、高分 unsafe、無安全 best、recovery、原命令與非有限分數。
- `/tmp/lea176-pruning-perf.log`：Linux 兩组 240 frame。previous-clear 平均 5.32ms、p95 7.89ms、budget 2/240；observed-budget 平均 18.01ms、p95 20.07ms、budget 134/240。exit 1，平均≤6ms／p95≤10ms／budget<5% 原門檻未達，不放寬。
- `/tmp/lea176-pruning-windows-perf.log`：Windows 問題位置平均 15.59ms、p95 20.07ms、budget 154/240，`RIGID_VISIBLE_COMBAT failures=2`；GUI executable 的 shell exit 0 不代表測試通過。
- `/tmp/lea176-pruning-first-budget-capture.json`：無用的 `(0.262,-0.4)` 已被略過；後續 `(0.262,0.4)` 因 left_track 碰撞拒絕，再後的 `(0,0.4)` 耗盡預算。說明不只單一無用候選耗時；未知 budget collider 不作幾何推論。

## 範圍收束

Fresh-context 有限安全／選擇規則驗收 PASS：`/tmp/lea176-pruning-acceptance.md`。pruning smoke、recovery_continuation、recovery_visibility_continuation 均 exit 0；獨立驗收者在 `/tmp` 隔離專案換回舊 predictor 後得到 exit 1，確認鑑別力。此 PASS 不包含效能，不抵銷上列實場 FAIL。

1. L0 原目標：敵車看到玩家時不嚴重掉幀，且正常追擊。
2. 最小安全閉環：保留完整碰撞安全和測試紅燈，保存此次可驗證的剪枝；不把局部正確當作效能完成。
3. L1：完整形狀／已驗手感／同款敵我物理一致。各次局部改善未能通過實場效能是直接 blocker，不是額外 AC。
4. 延後：額外地形／碰撞捷徑／新框架。不得持續堆疊特殊判斷或提高時間上限。
5. 下一步需重新裁決每幀多候選、每候選三秒細部預測的計算安排；本次未實作跨幀快取、非同步規劃或縮短時距。先停止追加產品修改，待新版有限方案裁決。

備份：`/tmp/lea176-before-candidate-pruning.tar.gz` 為此次前的產品檔；未還原或覆蓋使用者其他工作。
