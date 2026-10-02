# LEA-176 四車型玩家剛體 — 2026-09-23 驗證結果

## 現況

使用者已核可 Tank1/Tank3/Tank4 每側驅動上限調為115200/134400/158400N，正式場景已套用。
固定矩陣與獨立驗收通過，可交付玩家四車試玩；尚待使用者人工手感驗收，LEA-176整張單未結案。
Tank2仍120000N，質量、最高速度、原意圖加速曲線、煞車、後座與主圖預設車型不變。AI與訓練場仍用舊控制器。

## 已通過驗證

- Linux四車contact矩陣 failures0：平地、空中、單側、21/50cm正反向、真Road雙側正反向、完整形狀/質量/懸吊與力上限。原720幀及-0.03m底部門檻未放寬。
- Linux固定砲塔8案 failures0：Tank1/4左右目標、手動釋放接回、單發後對準。各案900幀內連續60幀角差<=0.25度、yaw<=0.01rad/s。
- 四車隔離解析後座、休眠喚醒與同幀開火死亡保留衝量通過。
- 四車gameplay_runtime：唯一物理/health/動畫來源、控制/戰鬥/四點接地綁定、各車煙塵點、單發冷卻/self RID、自身不受彈傷、真實來彈死亡、死亡輸入阻止與殘骸換車均通過。
- 舊9套回歸通過：rigid contact/native budget/passive friction/feel contact/tread、player integration/contact、spawn group、training ground。
- 額外5套既有回歸通過：aim cursor、tank1 hull aim、travel turret pose、damage health、training range。
- Windows原生四車contact/aim/recoil/runtime及Tank2 integration皆exit0、failures0；補強死亡fixture後重跑recoil/runtime亦通過。
- Tank2固定輸入曲線與改版前逐字相同；主場景、地圖、project.godot、AI predictor與本輪前保護SHA一致。
- Fresh-context獨立驗收PASS：/tmp/lea176-force-fresh.md。範圍是本輪有限矩陣與實際runtime整合，不是任意地形、AI或人工手感驗收。

## 測試完整性說明

各車既有最大血量為Tank1=80、Tank2=100、Tank3=120、Tank4=60。最初暫存runtime探針假設全車100而出現假紅，已按既有車型資料修正，沒有改遊戲血量。
四車後座測試先前繼承Tank2的固定100傷害，無法證明Tank3已死亡；本輪改成最大血量傷害並新增health=0與_dead斷言，避免冷卻恰巧拒絕第二發造成假通過。未改舊Tank2測試。
除了上述新測試加強，contact測試僅更新三個已核可EXPECTED.drive值，其餘門檻不變。

## 試玩方式

主圖 src/main.tscn 預設仍Tank2。要試其他車型：選主圖根節點TankSkirmish，在Inspector的Startup Player Scene欄拖入以下場景，儲存後F6執行目前主圖：

- Tank1：src/actors/rigid_tank/variants/tank1.tscn
- Tank3：src/actors/rigid_tank/variants/tank3.tscn
- Tank4：src/actors/rigid_tank/variants/tank4.tscn
- 回到Tank2：src/actors/rigid_tank/player_rigid_tank.tscn

請測直行加速/鬆開慣性/倒車與換向/原地轉向/路肩跨越/射擊後座；Tank1與Tank4另測滑鼠瞄準帶動車身、手動轉向優先及放開後接回。
不新增選車UI，不更動訓練場既有換車流程。

## 證據與保存

Linux新矩陣 /tmp/lea176-force-final-*.log；額外回歸 /tmp/lea176-force-extra-*.log。
Windows /tmp/lea176-force-win-*.log（recoil以recoil-final、runtime以four-runtime為最終版）。
四車runtime已由暫存探針保存為 tests/player_rigid_variants_runtime_smoke.gd，保存時逐byte相同。
本輪數值修改前備份 /tmp/lea176-before-approved-force-20260923.tar.gz，SHA256 fbc4fa08de7700aded709299b34a1e00d25492f65e20c4ab642748ac93cf51d2。
仍有基線既存damage owner與alpha_multiplier警告；本輪未擴改VFX。未commit/同步Linear或宣告整張物理工單完成。

驗證後程式/測試/文件快照保存於 /home/markchou/project/tank-skirmish-local-assets/restore-points/lea176-four-player-validated-20260923.tar.gz（385條目），SHA256 b7d99178130ae90ba954b1ec1e592e4740f2cc1576e34453ef61d95df7b0623b。這是本階段程式快照，非含所有地圖/素材的完整專案備份；本句於封存後補入。
