# LEA-176 剛體平地轉向預測 — 2026-09-23

## 目的與範圍

修復看到玩家後轉向預測持續超時、零指令與誤入脫困。前次支撐點快取降低重複計算但不足；保留原紅測紀錄，不把直線越障通過當追擊已通過。

實測舊平地快速判定要求basis.y精確等於UP，剛體微小傾斜不符合；垂直速度判零也間歇失敗。即使將查詢姿態正交化，履帶碰撞幾何約低於地板8–12mm，使舊floor判定仍失敗。原始量測 `/tmp/lea176-flat-gate-probe.log`，不是實體穿模程度或新碰撞容差宣稱。

## 實作

- `rigid_flat_ground_prediction.gd`：每個既有segment先以四射線確認同一靜止水平Box；沿用既有逐子步速度、轉角與側滑，以已證明平面解析支撐高度／姿態。
- 整段所有形狀端點AABB加完整四元數轉角的保守外擴，涵蓋車身、砲塔、砲管；完整掃掠必須落在同一Box頂面內（轉回Box local驗證），且完整mask查詢不能命中其他shape。
- 同RID高牆也不是floor shape；動態、坡面、缺支撐、地板邊界、砲管碰地、未知幾何或超額均不能快速放行，回既有完整查詢。
- 固定目前砲塔／砲管snapshot，不額外預測未來瞄準；維持既有核可範圍。
- 只新增剛體查詢橋接與predictor可選分支；不改真實車體姿態／速度／推力、3秒時距、2cm旋轉子步、4096query／20ms上限或1cm地形辨識容差。
- 沒有跨幀保存世界碰撞結果。上一輪每車局部支撐點快取保留。

## 有效證據

- 修正前有效Linux／Windows真訓練場固定240幀皆179幀budget、yaw約0.1°，紀錄見前次 `lea-176-turn-budget-checkpoint.md`。
- `/tmp/lea176-flat-pursuit.log`：Linux exit0、240幀零budget、yaw29.70°、位移9.657m，PASS。
- `/tmp/lea176-flat-windows-pursuit.log`：Windows相同場景240幀零budget、yaw29.67°、位移9.712m，明確PASS；平均單次預測約7.93ms、最大14.583ms（此一次量測，不承諾所有場景上限）。
- `/tmp/lea176-flat-realpose.log`：以使用者trace中的敵我位置重建，240次零budget、yaw58.93°。該距離在作戰距離內，最後holding而非pursuing，屬正常停車面向目標；不是繞路追擊案例。
- `/tmp/lea176-flat-unit.log`：新平地測試exit0，含微傾斜正例與舊advance短段結果對照、同RID高牆、動態物件、地板邊、斜地面負例。

- `/tmp/lea176-flat-terrain.log`：四車24個地形案例全PASS、failures=0、exit0，無SCRIPT ERROR，原720frame／穿透門檻不變。
- `/tmp/lea176-flat-curve-tank{1,2,3,4}.log`：四車CURVE／CURVE_PARAMS與前次classification基線逐筆相同，各exit0。
- fresh-context驗收 `/tmp/lea176-flat-acceptance.md`：PASS；獨立重跑新flat與既有curb boundary皆exit0、無Godot errors，高牆／gun-only／同RID高牆維持blocked而非budget。

本輪可交付人工實測，仍需使用者確認；整張LEA-176未結案，隱蔽受擊查看非本輪範圍。僅承諾已列有限驗收，不宣稱所有障礙附近的效能皆已涵蓋。

## 複審與保存

使用者明確核可 `/tmp/lea176-rigid-flat-plan.md` 傳送Claude Opus唯讀review。有效結果 `/tmp/lea176-rigid-flat-review.jsonl`；採納Box local包含、完整姿態角／全shape半徑、mask／飽和與射線範圍檢查。未採「全段union不可再grow」的實作限制，因全段union加最大padding包含各子段grow的聯集；不新增未來砲塔擺動預測。

原檔備份 `/tmp/lea176-before-flat-proof.tar.gz`，SHA256 `8a45b0e7d8b01025b036beabd7a896041c9d9a705540f1539e55f575c7b79b2e`。原工作樹變更全保留；未修改地圖／素材、未提交／推送。
