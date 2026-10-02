# LEA-176 階段整理與 LEA-178 交接

日期：2026-10-01。leadi 已裁決停止繼續擴大原單，將新主世界的有效尋路、路肩通過及移動效率另開下一單。

新單：[LEA-178 — 正式主地圖 AI 與 25% 道路](https://linear.app/leadingtw273/issue/LEA-178)。2026-10-02 leadi 已人工驗收 AI，正式道路及 src 素材高度剩 25%，Windows 四角加 NE／SW repeat 共 6/6 通過；本輪範圍與收尾證據以 [LEA-178 正式 25% 道路驗收](lea-178-quarter-road-acceptance-20261002.md) 為準。

## 這次收束的邊界

|工單|保留範圍|狀態|
|---|---|---|
|LEA-177|主世界道路、建築素材、布局、道路靜態碰撞與擺放工具|Linear 已完成|
|LEA-176|四車路面／橋面本身接地、離支撐落地、不吸頂與既有控制回歸|已按收斂範圍驗收結案；見 lea-176-final-acceptance-20261001.md|
|LEA-178|主地圖 AI 路線、轉角、路肩通行與移動效率|使用者已驗收；正式道路及 src 素材剩 25%，Windows 六案回歸通過；後續坡橋、懸吊與實體履帶試驗已取消|

LEA-176 原文明確排除完整履帶懸吊、多輪剛體模擬與 AI 尋路重寫。2026-10-02 leadi 取消後續坡橋、懸吊與相關 demo 嘗試及產出；後續已接受原 TurnSpace v6 AI，並完成正式道路 25% 與四角回歸收尾。

## 已完成且有證據的階段成果

1. 四車現行剛體接地／接觸操控已整合，有平地、空中、單側、正反向路肩及真道路矩陣、戰鬥與後座回歸；leadi 曾於9/23確認四車玩家物理手感通過。見 `lea-176-rigid-variants-result.md`、`lea-176-unified-rigid-checkpoint.md`。
2. AI 的四車制動量測、制動預測校正與近遠分層已有程式及固定回歸；保留完整車身／砲塔／砲管形狀。見 `lea-176-braking-measurement-result.md`、`lea-176-layered-prediction-result.md`。
3. 訓練場窄口追擊及出入口角落修正已有程式、Windows實跑與使用者驗收；效能只能按固定案例／版本判讀，未宣稱所有場景60FPS。
4. 主世界手駕與 AI benchmark 已建立，不需重建場景或重新量測輪組。Tank2手駕約60秒：原出生點直接跨最近道路，從中央菱形上方入口進入並停穩。後續四角基準為120秒。

## 新單接手時的原高度歷史量測與限制

下表保留原版本量測與舊反例；現行 25% 正式版與六案回歸以 [LEA-178 正式 25% 道路驗收](lea-178-quarter-road-acceptance-20261002.md) 為準。

|項目|已驗證內容|限制／未完成|
|---|---|---|
|TurnSpace v6|固定headless四角＋NE／SW repeat共6/6；四角114.30／80.37／80.82／72.03秒，7支smoke通過|同版Windows可視卡住反例仍存在，不能稱實際遊玩穩定通過|
|道路／路肩對照|SW可視有路平均98.23s、無路60.18s；路肩高度1與.25為93.90s與61.85s|有無道路同時改導航與接觸等因素；只支持有限案例，未決定修改正式地圖|
|局部原高度通行|原車直上fixed／AI成功，斜進fixed成功，保留雙repeat資料|斜進AI與轉角仍有20秒失敗；隔離fixture不是完整主世界|



## LEA-176 原範圍的收尾對帳

2026-10-01 已依使用者裁決的收斂範圍完成四車路面／橋面本身接地、離支撐落地、不吸頂及控制回歸對帳，fresh-context 驗收 PASS；見 lea-176-final-acceptance-20261001.md。完整坡橋要求的歷史移交與後續取消不重新擴入原單。

既有 `escape_handoff` 等 baseline 紅測按原 AC 判斷關聯並保留；不藏紅測，也不因整理階段順便擴新機制。LEA-176 已依收斂範圍驗收結案，相關歷史反例保持原始狀態。

## 接手清單

正式目錄：`/home/markchou/project/tank-skirmish-worktrees/lea-177-main-world`。保留全部既有未提交變更，不重做磁碟上的程式與進度。

|位置|用途|
|---|---|
|`docs/lea-176-development-status.md`|歷史開發與正式程式現況入口；按日期／版本判讀|
|`docs/lea-176-layered-prediction-decision.md`、`lea-176-layered-prediction-result.md`|AI分層與制動語意、有限驗收|
|`/home/markchou/project/agent-team/tmp/lea176-resume/corners-opt-20260930/CURRENT.md`|主世界四角、路肩、可視反例及隔離實驗索引|
|`…/stage-handoff-20261001/scope-evidence.md`|逐項原範圍／新範圍證據對帳及原文件行號|

本輪原 TurnSpace v6 AI 已由使用者接受，正式道路及 src 素材高度剩 25%，Windows 四角加 NE／SW repeat 六案通過，詳見 [LEA-178 正式 25% 道路驗收](lea-178-quarter-road-acceptance-20261002.md)。既有四車、訓練場、射擊、砲管碰撞與效能成果保留。後續坡橋、懸吊、實體履帶試驗與 demo 產出已取消並清除；未將隔離原型套入正式車輛。
