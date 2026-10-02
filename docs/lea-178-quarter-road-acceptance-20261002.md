# LEA-178：正式 25% 道路與 AI 尋路驗收

2026-10-02 leadi 已人工確認「AI 尋路系統驗收通過」，並同意補齊四角回歸、工單與交接同步、版本整理。

## 範圍與正式成果

本單涵蓋主地圖 AI 路線選擇、轉角調整、路肩通行與移動效率。沿用 TurnSpace v6、原 Tank2 物理及完整車體碰撞，正式來源位於 `/home/markchou/project/tank-skirmish-worktrees/lea-177-main-world`。後續坡橋候選、關節懸吊、實體履帶與相關隔離 demo 已取消；四車路面／橋面接地及控制回歸屬 LEA-176，主地圖布局及素材擺放工具屬 LEA-177。

道路高度剩原來的 25%，正式主地圖 200 個道路實例、341 個 reusable 道路場景、184 個共用碰撞資源同步調整，共 531 個來源路徑。`src/world/roads` 中這些道路場景可直接放置，無需 runtime 高度 wrapper。生成器保存 25% 配方並識別已縮放來源，重新生成及重複 bake 不會縮成 6.25%。XZ、材質／UV、原 node basis／scale、indices 與 LOD 維持。

## Windows 正式地圖回歸

原 `corners120-benchmark.gd` 未修改；native Windows Forward+、1280×800、60 Hz、原 Tank2 的 30 個碰撞 shape。每案使用有效起點與原導航烘焙，必須在 120 秒內抵達中央 3 m 範圍，連續 60 ticks 維持 arrived、速度不超過 0.1 m/s、角速度絕對值不超過 0.02。六案皆 exit 0、fixture valid、無 failures 或 building hit，來源凍結 SHA 保持。

|案例|結果|抵達並停穩|碰撞 shape 數|原始紀錄|
|---|---|---|---|---|
|NW|通過|61.28 秒|30|NW.json|
|NE|通過|66.00 秒|30|NE.json|
|SW|通過|61.40 秒|30|SW.json|
|SE|通過|61.00 秒|30|SE.json|
|NE-repeat|通過|71.10 秒|30|NE-repeat.json|
|SW-repeat|通過|61.28 秒|30|SW-repeat.json|

六案證據根：`/home/markchou/project/agent-team/tmp/lea178-quarter-closeout-20261002`；摘要 `matrix-summary.json`，逐 tick 結果與原始 engine／stdout log 保留。`matrix-source-freeze.json` 固定含原 benchmark 的 599 個凍結路徑；`independent-matrix-acceptance.json` 由 fresh-context 驗收者直接核對原始結果。

原始正式西南角單輪為 61.3167 秒 PASS，見 `/home/markchou/project/agent-team/tmp/road-quarter-production-20261002/production-ai-sw.json`。原高度 v6 的 headless 6/6 及 Windows 西南角舊反例保留為歷史，不代替這次 25% 六案紀錄。

## 幾何、生成與保存驗收

既有 fresh-context 驗收通過 342 個正式幾何案例（主地圖 Roads 加 341 個素材）：mesh／collision XYZ 誤差為 0，shadow 最大 XZ 誤差 0.00763 mm、Y 誤差 0.000477 mm。35 個隔離重新生成輸出及 341 個重複 bake 通過；531 個最終來源逐檔 SHA read-back 通過，原非道路來源及 Git 歷史保持。

證據：`/home/markchou/project/agent-team/tmp/road-quarter-production-20261002/production-result.json`、`fresh-acceptance.json`、`geometry-acceptance.json`、`generator-independent-acceptance.json` 與 `final-source-readback.json`。

## 工單與版本收尾

AI 已由使用者人工接受，原四角加 NE／SW repeat 矩陣已補齊 6/6，本機交接與版本審查材料已整理。leadi 已明確核准送至 Linear LEA-178 的具體摘要、標題及完成狀態；工單已更新為「已完成」，標題為「新主世界地圖：AI 尋路、25% 道路／路肩與移動效率」，完成時間 2026-10-02T06:27:31.105Z。實際遠端讀回確認核准摘要完全相符，原高度階段的歷史描述完整保留。前兩次自動核准拒絕紀錄保留作歷史；本次核准與同步證據為 `/home/markchou/project/agent-team/tmp/lea178-quarter-closeout-20261002/linear-approved-request.json`、`linear-approved-sync-result.json` 與 `linear-final-readback.json`。本機驗收及文件讀回見 `fresh-acceptance.json`、`docs-apply-result.json`。

本次 Git 收尾沿用 `feat/lea-177-main-world-rebuild`：封閉範圍為 142 個必要來源，含已接受的 LEA-176 runtime／支撐依賴、TurnSpace v6、25% 道路生成規則、有限回歸與交接文件；主地圖保留先前 Ground 修正。其餘 110 個原有修改保留，主 checkout 的使用者修改不覆蓋。來源清單及逐檔 SHA 見 `/home/markchou/project/agent-team/tmp/lea178-git-finish-20261002/root-sealed-commit-plan.json`；提交、PR、CI、審查及合併的實際讀回以同目錄 `git-closeout-result.json` 為準。商用來源與 525 個 generated 道路資源依既有素材庫政策留在本機，Git 保存永久生成配方；本機重建驗證搭配 586 檔必要資源 overlay，不宣稱單靠 Git checkout 自含全部素材。先前 patch／snapshot 版本材料保留為歷史。

## 證據範圍

結論涵蓋本次固定 Tank2、正式主地圖、四角及指定 repeat；不外推四車任意地圖或全面 60 FPS。Godot 在部分成功退場後記錄 TextureStorage RID leak／RenderingServer singleton null，保留原始 log 與分類；只有位於原 benchmark 成功 marker 之後的兩種精確退場訊息列為警告，SCRIPT ERROR、runtime ERROR、AI 失敗與原停穩門檻仍照原驗收阻擋。原道路套用驗收的 vendor PNG 非全量修改前 SHA、12 處隔離再生 fit UV 浮點差 advisory 保留，正式素材與重複 bake 的 UV 精驗未放寬。
