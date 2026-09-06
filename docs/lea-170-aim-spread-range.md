# LEA-170：瞄準擴散與準確度靶場

## 開啟與試射

在 Godot 開啟 `src/world/training_ground/training_ground_playtest.tscn`，按 F6 遊玩目前場景。原本四台靶車保留；新增射擊走道位於它們旁邊，主靶為 10×10 公尺、每格 1 公尺。

沿地面 25／50／75／100 公尺線停車，固定瞄準十字靶心連射，再比較移動、原地轉向與停穩後的落點。距離自靶板正面量至地面線，不是即時砲口測距。鏡頭角度、滾輪上限和滑鼠前視距離不變；遠距時可拉遠並把游標移向靶子。

命中點會一直保留到這次遊戲結束，或射中 50 公尺線旁的 **2×2 公尺「清除彈著」靶**。清除靶不會毀損，可反覆使用。這不是新血量或計分玩法。

## 坦克參數在哪裡

開啟 `src/actors/tank/variants/tank1/tank1.tscn`（或 tank2／tank3／tank4），選最上層坦克節點，在 Inspector 找 **瞄準擴散**。四型保存相同初值，可分別微調；場景內的實例覆寫值優先於共用控制器。

| 參數 | 初值 | 用途 |
|---|---:|---|
| Aim Spread Base Degrees | 0.2° | 完全穩定時的最小半角 |
| Aim Spread Movement Add Degrees | 1.5° | 滿實際移動速度的額外半角 |
| Aim Spread Turn Add Degrees | 1° | 滿車身轉速的額外半角 |
| Aim Spread Cap Degrees | 2.5° | 基礎與兩種貢獻相加後的總上限 |
| Aim Spread Grow Degrees Per Second | 4°/秒 | 失準時擴大的速度 |
| Aim Spread Stationary Recovery Degrees Per Second | 1.2°/秒 | 靜止時收縮的速度 |
| Aim Spread Moving Recovery Degrees Per Second | 0.6°/秒 | 滿移動速度時收縮的速度 |

「半角」是炮管中心線到圓錐邊緣的角度，不是整個圓錐張角。移動與轉向按實際速度連續貢獻，停車不是瞬間滿準度；放慢時的回復速度介於兩個設定之間。這些是初版手感起點，不代表最終車型平衡。

每次開火只取樣一次方向，砲彈從實際砲口直線飛出。砲塔、炮焰、硝煙與後座仍沿實際炮管方向。現有紅白線表示瞄準中心，**還不是每發彈道或擴散 HUD**；動態圖樣留到下一階段。

## 靶場責任

`training_range.tscn`／`training_range.gd` 管主靶、清除靶、標線與彈著；`training_ground_playtest.gd` 把通用命中事件接進靶場。靶板沒有 HealthComponent／DamageReceiver，既有坦克靶與擊毀換車不受影響。

## 驗證

`tests/tank_aim_spread_smoke.gd` 驗公式、漸變、四型配置與固定 seed 的圓錐方向；`tests/training_range_smoke.gd` 驗幾何、碰撞與彈著清除；既有訓練場與戰鬥邊界測試驗完整接線。兩個新測試已列入 `scripts/quality.mjs`，視覺與手感仍需 leadi 人工驗收。
