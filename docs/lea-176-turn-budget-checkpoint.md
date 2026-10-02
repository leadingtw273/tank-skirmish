# LEA-176 轉向預測超時檢查點（2026-09-23）

## 現況：未修復，不可宣稱可驗收

使用者實測發現敵車看到玩家後卡頓、不追擊。先前24案為直線越障，不能代表真追擊轉向已驗證。Windows本次實際紀錄首見玩家後連續533次budget，預測約20ms／幀、輸出零，實際frame間隔約29ms；後續再次可見時重現。根據程式與trace，時間閘保守停車是直接原因，並非推力不足。

## 核可的有限修正

消除 `RigidPrediction.support_points` 每次重新掃描車身頂點的重複工作；每個 ContactTank 持有獨立唯讀局部點快取，bottom/step_height作key，derive重建幾何時清空。沒有快取世界碰撞結果、降低查詢精度、延長20ms或變更4096 query上限；沒有改施力或手感。

Claude Opus方案複審指出快取未必足夠、需明確失效與成功門檻。已採單車持有與有限實測；不因review擴成跨幀續算。計畫 `/tmp/lea176-turn-cache-plan.md`，裁決 `/tmp/lea176-turn-cache-decisions.md`。

## 證據

- 局部點測試 `tests/rigid_support_cache_smoke.gd`：四車與獨立原算法相同，height/bottom重算、幾何重建清除、車輛間獨立；`/tmp/lea176-support-green.log` failures=[]、exit0。
- Tank2 2000次support_points由48,394μs降至515μs（只證明此函式成本下降，不是整體遊戲加速倍數）。其餘三款也一致，`/tmp/lea176-support-before.log`、`/tmp/lea176-support-after.log`。
- 新真訓練場測試 `tests/rigid_training_pursuit_smoke.gd` 保留場景碰撞與正常AI、先等待導航同步，再一次性擺位；未替AI下指令或寫velocity。
- 固定AC：240frames、真可見且turn請求、實際yaw>=15°/位移>=2m、budget<5%且不連續30幀。未放寬。
- Linux修改前 `/tmp/lea176-turn-before-ready.log`：179/240 budget，yaw0.15°；修改後 `/tmp/lea176-turn-after.log`：仍179/240 budget、yaw0.15°；皆exit1。
- Windows前 `/tmp/lea176-turn-windows-before.log`、後 `/tmp/lea176-turn-windows-after.log`：皆179/240 budget、yaw0.12°、位移1.323m（主要是倒車脫困，不能當追擊成功）。Windows GUI exe shell返回0，但log明確FAIL，以斷言結果判紅。
- 初始測試兩次因導航首輪尚未同步而no_path，屬無效fixture，不能作產品基線；修fixture後才得到上述有效紅測。
- fresh-context 獨立驗收 `/tmp/lea176-support-cache-acceptance.md`：局部快取與高牆／砲管／同RID高牆負例皆exit0、無SCRIPT ERROR，可保留快取；整體追擊AC仍FAIL。
- Tank2既有直線地形六案 `/tmp/lea176-turn-terrain-regression.log`：exit0、failures=0，沒有以追擊紅測否定或取代原本已通過的有限案例。

## 收束

這輪快取本身正確但不足以解決L0卡頓／不追擊。停止追加產品演算法，不提高預算、弱化測試或跳過碰撞。下一步需裁決轉向預測工作量的優化方案；目前完整三秒轉向弧仍每幀重算。高牆／砲管防護、1cm辨識容差與共用物理參數均維持。

修改前兩產品檔備份 `/tmp/lea176-before-support-cache.tar.gz`，SHA256 `11fc578589f0b5088abbc5d49b1f8c0358bdc5a8ac793d217a0a0a1fe84d82d7`。未更動主圖、訓練場布局或素材；未提交、推送或結案。編輯器保持原本開啟，不重啟未儲存場景，不把紅測版本當修復成品。
