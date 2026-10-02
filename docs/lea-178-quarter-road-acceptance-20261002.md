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

本次 Git 收尾沿用 `feat/lea-177-main-world-rebuild`：初始提交 `1a943b25bda7a6d86176438d4fa3092c7eec353b` 封存 142 個必要來源，含已接受的 LEA-176 runtime／支撐依賴、TurnSpace v6、25% 道路生成規則、有限回歸與交接文件；主地圖保留先前 Ground 修正。收尾再納入 4 個已獨立驗收的 CI／入口測試合約與 19 個對應正式來源的 Godot UID，合計 165 個唯一來源路徑。其餘 110 個原有修改及 16 個診斷 UID 保留，不覆蓋主 checkout。來源逐檔清單見 `/home/markchou/project/agent-team/tmp/lea178-git-finish-20261002/final-source-manifest.json`；實際提交、PR、CI、審查及合併讀回以同目錄 `git-closeout-result.json` 為準。

新增 19 個正式回歸案例及原六案 AI 驗收維持有效。先前隔離測試提案未通過、沒有套用，屬歷史紀錄。GitHub 推送與 Claude 審查已取得 leadi 具體核准，PR 為 https://github.com/leadingtw273/tank-skirmish/pull/123。PR 首次 CI 在 Godot 匯入缺少素材時停止，尚未執行 enemy_combat_smoke；本機完整 CI 的舊測試合約失敗是另一份結果，不能據此撤銷已接受的 AI 尋路。

商用素材與 525 個 generated 道路資源依既有政策留在本機；Git 保存永久生成配方與 `docs/assets/local-ci-assets-lock.json` 的 586 檔路徑、大小、SHA。`scripts/restore-local-ci-assets.py` 先完整驗證固定 archive 與每檔，再還原忽略素材，拒絕不符清單、雜湊錯誤、非一般檔案、越界路徑與 tracked source 覆寫。乾淨 checkout 已完成實際 586 檔還原及 Godot 匯入（exit 0、零錯誤）。同一 `quality` job 改由受控本機隔離 runner 執行，所有既有 `scripts/ci.sh` 測試與錯誤掃描保留；私有素材不得上傳到 GitHub、審查服務或 artifacts。

本次 runner 為一次性官方映像的非特權 Docker 容器，沒有主機 home 或 Docker socket。啟動時只掛空的唯讀素材目錄；主機核對 GitHub 實際 run、attempt、source HEAD、quality job 與指定 runner 身分後才提供固定 tar。未核對的工作無法取得素材。完成後停止並移除本次精確容器與 runner，不建立常駐 runner 或新 Agent Job。未來 CI 執行仍需相同可信本機素材與受控 runner，沒有宣稱公開 fork 可存取這批素材。

既有測試只對齊正式 Rigid 載具根節點／donor 的責任與真實地板、遮擋、初始化取樣；原斷言與門檻保留。原 R8 殘骸清理區額外辨識正式剛體坦克，死亡、區域、場景祖先與 queue_free 條件維持。全部 smoke、正式 CI、精確 HEAD 的跨模型審查與正常合併結果，以 `/home/markchou/project/agent-team/tmp/lea178-merge-resume-20261002` 證據及原 `git-closeout-result.json` 的後續讀回為準；文件本身不代替實際檢查狀態。

## 證據範圍

結論涵蓋本次固定 Tank2、正式主地圖、四角及指定 repeat；不外推四車任意地圖或全面 60 FPS。Godot 在部分成功退場後記錄 TextureStorage RID leak／RenderingServer singleton null，保留原始 log 與分類；只有位於原 benchmark 成功 marker 之後的兩種精確退場訊息列為警告，SCRIPT ERROR、runtime ERROR、AI 失敗與原停穩門檻仍照原驗收阻擋。原道路套用驗收的 vendor PNG 非全量修改前 SHA、12 處隔離再生 fit UV 浮點差 advisory 保留，正式素材與重複 bake 的 UV 精驗未放寬。
