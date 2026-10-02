# 轉向慣性校準（2026-09-22）

**已撤回，以下為歷史試驗，不代表目前版本或使用者定位。** 使用者實測認為此版手感過於刻意，明確要求回到調整前。已還原自動慣量及完整原controller，保留已驗收履帶動畫。先前「不是真實物理模擬」被使用者指出誤解其意思：希望保有物理慣性，不能為追舊速度／±20%而削弱慣性感受。本次不據此擴張成完整真實模擬新方案。

回退證據：controller與`/tmp/lea176-before-yaw-inertia.gd`逐byte一致；已移除0.25專用測試，備份在`/tmp/lea176-rejected-yaw-inertia-smoke.gd`；被拒絕的controller另存`/tmp/lea176-rejected-yaw-contact.gd`。獨立驗收見`/tmp/lea176-rollback-fresh.md`。

使用者已接受自訂慣量的主軸擺正、俯仰約1.1%差異及跨軸連動移除。目標是獨立Tank2手感接近舊主地圖，不是真實物理模擬；原本±20%比較情境／門檻未修改。

## 本次實作

- 首次有效 `_integrate_forces` 讀回自動主慣量並固定保存，無效時留待下一物理步重試，不在 `_ready` 假定已算好。
- 手感profile啟用才設定 `(auto.x, auto.y * 0.25, auto.z)`，值不同才寫入，不逐幀累乘。OFF設定 `Vector3.ZERO` 交回引擎自動張量；ON→OFF→ON驗證不累乘。
- 車重60000kg、重心、30碰撞形狀、120000N每側、摩擦、接觸施力與已驗收履帶視覺均維持。角加速補償仍讀實際生效慣量，不另加扭矩或硬寫速度。
- 使用 [Godot 自訂慣量API](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html#class-rigidbody3d-property-inertia)。保持X/Z主慣量數字不代表原張量反應完全不變，本次沒有這樣宣稱。

## 實際比較

| 指標 | 舊主地圖 | 本版 |
|---|---:|---:|
| 前進4秒速度m/s | 5.7251 | 5.4520 |
| 前進九成時間s | 1.55 | 1.6167 |
| 收油停止時間s | 1.4333 | 1.4 |
| 煞停距離m | 4.0496 | 3.7997 |
| 原地轉九成時間s | 0.28333 | 0.28333 |
| 原地轉1秒角速rad/s | 0.4 | 0.39293 |
| 原地轉放開停止時間s | 0.25 | 0.25 |
| 行進轉4秒累積角度rad | 1.5433 | 1.3496 |

`tests/rigid_tank_legacy_feel_smoke.gd` 全PASS；不是把期望值當實測值，程式從逐physics_frame的 `angular_velocity.y` 計時。原地17/60秒達到門檻符合既有nominal加速曲線。最大推力計算所得是能力上限，不是必須每幀用滿的常數加速。

## 慣量與回退驗證

- Auto主慣量約 `(271636.2,727211.2,521959.6)`，custom約 `(271636.2,181802.8,521959.6)`，Linux與Windows各自讀回驗證。
- 本車前向為-X，所以側傾／roll繞X、俯仰／pitch繞Z。body-local逆慣量張量同軸響應差：pitch約1.112831%、roll約0.000284%，均在核可的2%／0.1%內。這是引擎的力矩→角加速度係數，不只是比較Inspector數字。
- OFF完整auto tensor恢復、再ON回到首次custom值；左右轉與釋放停止都PASS。
- 外力擦撞造成的yaw旋轉也會更容易；本次不保證與舊版碰撞自旋幅度相同，不新增碰撞衝量補償。固定接觸矩陣之外的撞擊行為尚待人工觀察。

## 證據

- Linux手感：`/tmp/lea176-yaw-final-feel.log`，`LEGACY_FEEL failures=0`。
- Linux慣量／回退：`/tmp/lea176-yaw-inertia-smoke.log`，`YAW_INERTIA failures=0`。
- Windows：`/tmp/lea176-yaw-win-rigid_tank_yaw_inertia_smoke.log`、`/tmp/lea176-yaw-win-rigid_tank_legacy_feel_smoke.log`、`/tmp/lea176-yaw-win-rigid_tank_feel_contact_smoke.log`、`/tmp/lea176-yaw-win-rigid_tank_tread_visual_smoke.log`，全部exit0、failures=0。
- Fresh-context PASS：七套回歸、五檔保護與動畫／測試hash均通過，證據 `/tmp/lea176-yaw-fresh.md`。首次封包將動畫程式hash檔名寫得不夠明確，驗收誤比到smoke檔；補明精確路徑後確認兩者皆未改，是D類封包假紅，沒有放寬AC或修改程式迎合hash。
- Claude Opus唯讀review：`/tmp/lea176-yaw-inertia-review.jsonl`。採納初始化／切換／有效值驗證；不採納以推力上限推斷所有幀必須同加速度、Godot通用-Z前向代替本車-X等前提。側撞新矩陣／全油門道路新保證不擴入本次。

原全油門Road倒退side+1/-1兩案曾未過，本次未重驗；低速跨階PASS不能代表該問題已修。正式主圖、AI、坡面駐車、防翻、砲塔及其他車型仍未遷移，本次不宣告整張LEA-176結案。履帶視覺已人工驗收，本次轉向待使用者試玩。
