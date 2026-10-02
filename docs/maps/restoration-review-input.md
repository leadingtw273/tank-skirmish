# LEA-177 整合唯讀複審資料

## 原核可範圍與使用者

leadi 在 Windows Godot 手工編輯主世界。舊 /tmp worktree 遺失，本單依既有素材及參考截圖重建，不宣稱還原原始 transform。使用者核可連續實作與本單第二模型複審。
AC：長期保存；主地圖／訓練場分開；Ghost Town 類路網中心對稱、缺口接合、紅圈兩處淨距加倍；道路/建築/坦克展示可複製；原素材不改；付費素材不公開。
不改 AI/載具行為；坦克接地/坡道/橋面行駛屬 LEA-176。沒定案的建築與草地布局不擅自生成。

## 已採用架構

- 專用長期 worktree，基線 e1b9c5b（含已合併 AI）；原 checkout 的使用者修改不碰。
- `assets/AtomicRealmModularRoads` 保存 8 ZIP 來源；8 包 CRC/雜湊和原 byte 獨立驗收通過。優先 GLB，只有 3 個獨特缺失模型從其他格式轉 GLB，另 25 個拼字別名已有來源；原檔不變。
- 兩張偽裝 PNG 的 PSD 轉出真正 PNG 到 src 衍生區，原檔不變。
- `src/world/roads`：客製幾何、含碰撞模組與接點資料；`src/samples/roads`：8 包和客製展示。目前 598 個 model/variant 模組，StaticBody3D + 視覺相同 transform 的 trimesh。
- 真45° Curve2 保持原 Road1 路肩和UV，沿弧按12m紋理周期映射，最後片段裁切而非拉長虛線。
- 三款緊湊Y：Road11縮短主幹至z3；Road12 L/R同時裁兩個支路，以實際端面中心為Snap，12m寬度有triangle-plane數值驗證。Road12 visual/collision下沉0.015，邏輯安裝點y0。沒有負scale或加長型版本。閉環展示僅使用標準12m直路，有限大小／左右案例，不承諾任意梯形都可精確閉合。
- 主路圖上半部旋轉180°建立下半，54路口、72連接；緊湊Y後138段直路。缺口用12m標準段加最後裁短段，不扭角度。原地板1920×1920，兩側平行中心距27.92m，路寬12m，淨距15.92m=2×7.96。
- 只有候選檔才允許重產 populated 路網；發布主圖前另存舊主圖。交付後不自動重產使用者手修地圖。
- 右Alt近點吸附，方向誤差8°、半徑1.25m；多選僅整體平移並排除所選內部目標，父子同選只移動最上層。無吸附按鈕／內外模式。Undo在原生release後idle排程，避免原生動作蓋過外掛提交。
- 建築102款來源（finished26/base18/parts32/materials26），938完整配色模組與碰撞；完整一份102款、各群組展示、同款13色。Blender 2.79 Diffuse轉Principled才可匯出glTF貼圖，已修此實際反例。4坦克展示引用原完整scene，只有展示父容器停用處理。

## 證據與尚待人驗

已通過：source獨立CRC/bytes/拒覆寫測試；road生成598 failures0；曲線幾何3tests；base端點14模型34點；building材質938/13色測試0failure；training_ground/training_range/map960回歸；road solver與真EditorUndoRedoManager隔離整合測試。
曾發現且修正：缺marker使路口驗收失敗；Road12 snap安裝平面不一致；建築GLB白材質；建築預覽camera把target當direction造成灰畫面。最終主路幾何与building fresh驗收正在進行，未以自驗冒稱fresh PASS。
Godot實際GPU截图已能顯示道路A貼圖與同款13種建築材質。原生GUI拖曳右Alt/群選與使用者對參考圖的主觀相似程度仍待人驗；不把solver測試冒稱這兩項通過。

## 保存與邊界

生成器、catalog、純引用scene、測試/doc納管；原包、大型衍生模型/碰撞與嵌網格wrapper在本機忽略，不公開push。原8ZIP已有獨立長期來源庫；交付前建立完整含ignored素材的離線專案archive與Git bundle，驗讀archive必要路徑與checksum。不能只靠Git checkout復原素材。
本次僅刪除本代理誤寫到agent-team的兩個重複trace檔；刪前全量比對SHA一致，正確worktree副本保留。

## Review 要求

只找上述已鎖定AC的直接矛盾或具體遺漏。把 findings 分為本單 blocker／後續 backlog／忽略；假設的並行生成、崩潰、未來素材相容性不擴成新AC。不做法律論文、不要求公開付費素材。這是重建整合code-stage review，不重開已裁決規格。
本文件是唯一傳送資料，不含原始素材、憑證或完整原始碼。只回review，不改檔、不呼叫其他代理。
