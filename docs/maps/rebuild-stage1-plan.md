# LEA-177 第一階段：道路素材與展示恢復

## 已鎖定前提

使用者：leadi 在 Windows Godot 手工製作主世界；類比：既有模組化道路與 sample 工作流。
定位：遊戲專案的長期資產；動機：恢復可複製擺放的道路與建築，重作主世界，而非重新設計 AI。
基線 e1b9c5b，長期工作目錄 lea-177-main-world；原 checkout 的修改不動。
參考圖已保存於 docs/maps/references，commit 1d0c472。

## ADR：碰撞與載具責任

狀態：2026-09-18 使用者已採用。
背景：道路靜態形狀與坦克路面接地是不同功能，前次摘要混淆兩者。
決策：LEA-177 包含道路 StaticBody3D 與靜態網格碰撞；LEA-176 負責接地、坡道、橋面行駛。
否決：將道路碰撞一起推遲至 LEA-176，與原工單前置條件不符。
影響：展示可複製完整道路模組，但不能宣稱坦克已能上下橋。

## 本階段範圍

1. 驗證本機 8 個 ZIP 的 SHA256 與 CRC，禁止執行壓縮包內程式。
2. 原包原樣保存在長期本機來源庫；記錄來源、雜湊與檔案清單。不得公開推送付費原檔。
3. 原素材置於 assets/AtomicRealmModularRoads，保留相對引用與來源內容，不在此客製網格。
4. 衍生道路模組置於 src/world/roads，展示置於 src/samples/roads；生成工具置於 scripts/roads。
5. 以 GLB 為優先匯入格式；缺少 GLB 的資產另列清單，不假稱全包完成。貼圖變體需確認材質對應，不將全部貼圖盲套到每個模型。
6. 每包獨立展示，模型與合法配色排列、標名，可選取完整模組複製；包含靜態碰撞。
7. 保存生成腳本與測試；原素材與衍生付費網格不推送公開倉庫。先查授權，再決定遠端保存方式。

## 非本階段

不改主場景入口、AI、坦克、訓練場；不製作客製 Y 字路、吸附或 Ghost Town 布局。
後續依既有核可順序處理地圖分類、客製路件與吸附、主路網、建築與坦克展示。

## 固定驗收條件

- 8 包各自來源雜湊與 CRC 通過；原始來源未覆寫。
- 報告列明每包 GLB 與缺少 GLB 的資產數、合法變體數及授權狀態。
- Godot 能無遺失引用載入生成模組與展示；實例為可複製 PackedScene。
- 實例包含與可見網格對應的碰撞；共享幾何不改變來源。
- 各展示在 XZ 平面不重疊，有預覽相機；Godot 實跑並截圖。
- 既有 src/main.tscn、訓練場與載具程式雜湊不變。
- fresh-context 驗收與本機 checkpoint，人工驗收前不結案。

## 澄清紀錄

- 道路靜態碰撞納入本單？答：可以。接地/坡道留 LEA-176。
- 目標、類比、長期資產與自用編輯動機仍依既有對話，沒有因此更改。
- 術語沿用 StaticBody3D、sample、主世界；沒有新增專案專用術語。

## 狀態

計畫已於 2026-09-18 經 Claude Opus 單次唯讀複審；以下為主代理裁決與補充。
素材匯入尚未開始。付費授權未確認前不得公開素材。

## 複審裁決與可重現驗證

1. 採納來源基準補充：8 包使用 2026-09-18 首次盤點的 SHA256 為本機保存基準，不冒稱官方簽章。CRC 已通過；來源庫逐包 cmp 與 Downloads 相同。匯入時把各包 SHA256 與 ZIP entry 清單保存到來源 manifest。
2. 採納重載測試：生成節點須正確設定 owner；保存 PackedScene 後使用忽略快取方式重新載入，比對可見 MeshInstance3D、StaticBody3D、CollisionShape3D 數量與變換。模擬複製到另一場景、保存、重開；不只驗生成中的記憶體物件。
3. 採納基線明確化：此階段對照 e1b9c5b，保護 src/main.tscn、src/ai/、src/actors/tank/、src/world/training_ground/、src/player/、src/camera/、project.godot；由 git ls-tree 列出實際存在的完整檔案清單，驗收 git diff 對這些路徑為空。
4. 素材保存採最小方案：原包已另存 /home/markchou/project/tank-skirmish-local-assets/AtomicRealmModularRoads。執行階段先將 assets/AtomicRealmModularRoads 與生成的付費網格/碰撞加入忽略規則，生成腳本及純引用場景可納管；新增階段不執行任何 git push。檔案在 repository 內不代表已公開，故 reviewer 的「一 commit 就違規」不採納；不建立 pre-push 框架。
5. 授權報告落在 docs/maps/road-source-inventory.md，逐包記錄授權檔位置與已查證/未查證狀態；未查證不是虛構通過。本階段本機使用使用者提供的包，不把不公開推送擴成完整法律研究。
6. 靜態碰撞使用逐可見網格 trimesh，套用相同變換；以三角面與變換對應驗證，碰撞層沿用既有世界障礙設定。不把載具接地測試混入本階段。
7. Linux Godot headless 作載入與碰撞測試，實際 Godot 渲染檢查展示；Windows Godot 供 leadi 人驗。截圖與驗收記錄保存長期工作目錄，不依賴 /tmp。sample 每包一個場景，共 8 個。

分類：上述 1/2/3/4 為原驗收的執行細節補強，不是已發生的程式缺陷；5 為文件明確化；缺 GLB 轉檔與跨機還原屬後续工作。未發現需要改變本單目標的 blocker。
