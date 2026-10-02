# LEA-176 收斂範圍與最終驗收（2026-10-01）

## 最新範圍裁決

leadi 明確要求：「上下坡部分先移除好了，這部分後續單會在著重處理」。

本紀錄為現行範圍，取代本單舊計畫中的沿坡升降及經坡道上下橋要求。舊文件與失敗原始紀錄保留作歷史，不代表失敗已修好。上下坡、坡橋驅動與完整橋坡預測效率在 2026-10-01 曾移交 LEA-178；2026-10-02 後續坡橋候選及物理試作已取消，本單保留四車路面／橋面本身接地、離支撐落地、不吸頂、控制回歸及手工布局保存。

## 收斂後驗收結論

**PASS，可依現行範圍結案。** 最後一輪由 fresh-context 子代理驗收，並以現行來源 SHA 對齊今日實跑證據；不是實作者自驗，也沒有改弱斷言。正式物理程式未改動、未換後端。

| 現行 AC | 實際證據 | 判定 |
|---|---|---|
| 四車有效路面接地 | 四車接觸40個斷言；現行原生 GodotPhysics3D | PASS |
| 四車真橋面本身接地與前後慢行 | 原 Bridge1 資產橋面；雙側全程支撐，底部相對橋面間隙0.0384–0.0391m，高度波動≤0.00031m，各方向移動>0.55m | PASS |
| 離支撐落地、不吸頭頂橋面 | 四車完整離1m平台後落地及頭頂橋面不吸附，逐case原始log；來源與現行SHA一致 | PASS |
| 路面／橋面支撐不誤當牆 | 四車AI台階／道路24案；四車真橋面完整choose直通；高牆每車60/60拒絕 | PASS（有限案例） |
| 保留已接受的控制及防穿牆／脫困 | 四車前進／倒退／原地轉向／行進轉向／中立制動20案例260樣本；最高速雙向防牆8案；固定砲塔瞄準、玩家wallguard、Tank2窄口與出口轉角verified recovery | PASS（既有回歸範圍） |
| 保存手工主地圖布局與既有未提交成果 | 原7,502個檔案SHA逐一比對，0變更、0缺失；九份物理／profile來源SHA一致 | PASS |

沒有宣稱四車所有瞄準、脫困與導航排列全部覆蓋。基準程式完全未變，因此依現行SHA可重用今日既有有限回歸結果，不重跑未變程式以累積偶然PASS。

## 測試結果解讀

今日18組既有回歸為16組PASS、2組保留紅：
- legacy_feel的6個FAIL對應已撤回的舊±20%手感門檻，參見 lea-176-yaw-inertia-result.md 的開頭撤回說明；不為過舊門檻而削弱已接受慣性。
- escape_handoff的2個FAIL是舊CharacterBody已知hull／gun辨識baseline，不當作現行四車剛體驗收證據，也沒有宣稱已修好。

真橋20案例原始矩陣18PASS／2FAIL，其中Tank2／Tank3上橋失敗保持原樣；兩車未上橋，因此下橋未驗。這些項目因使用者最新範圍裁決移出本單，**不是把FAIL改成PASS**。

## 歷史移交項目與最新接續狀態

以下 1–3 保留當時診斷與未實作事實，相關後續坡橋候選已於 2026-10-02 取消，不是當前待辦。

1. 四車有效上下坡與經坡道上／下橋；保留Tank2／Tank3持續輸入仍倒滑的有限反例。
2. 坡向重力超過既有motor／滑退制動上限的診斷與候選。候選僅有計畫及Claude第二輪審查PASS，尚未實作、未驗修正效果。
3. 真Ramp1／Ramp2完整三秒predictor碰到現行20ms時間閘；四車20個短段production query雖clear，不能替代完整查詢或導航效果。
4. LEA-178 原 TurnSpace v6 AI 已由 leadi 人工驗收，正式道路與 src 素材剩原高度 25%，Windows 四角加 NE／SW repeat 六案通過；見 [LEA-178 正式 25% 道路驗收](lea-178-quarter-road-acceptance-20261002.md)。原高度 Windows 西南角反例保留為歷史，後續坡橋、懸吊、實體履帶及相關試驗產出維持取消。

## 可重跑證據位置

共同工作產物根：/home/markchou/project/agent-team/tmp/lea176-resume/
- final-ac-audit-20261001/runtime/acceptance.md、acceptance.json：18組既有回歸與精確命令。
- final-ac-audit-20261001/bridge/acceptance.md、acceptance.json：四車平台落地、不吸頂及坡橋原始反例。
- bridge-completion-20261001/reduced-scope-acceptance/acceptance.md、acceptance.json：fresh-context收斂驗收與四車真橋面新增實跑。
- bridge-completion-20261001/baseline-flat.json、flat-probe.gd、flat-commands.sh：四車20案260樣本。
- bridge-completion-20261001/ai-probe/acceptance.md：正式query支撐、高牆control與完整Ramp查詢限制。
- bridge-completion-20261001/SLOPE-DEFERRED.md：坡向修正未實作的明確狀態。

本次正式專案僅新增此結案文件；沒有修改物理、車型曲線、地圖布局或任何既有未提交內容。本單結案不代表已commit、merge或部署。
