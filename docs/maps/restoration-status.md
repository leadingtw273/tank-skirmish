# LEA-177 重建交付紀錄

## 保存位置與性質

工作樹：`/home/markchou/project/tank-skirmish-worktrees/lea-177-main-world`。
基線：`e1b9c5b`。原 checkout 與其使用者修改保留。
這是依參考截圖與現存來源包重建，不是找回遺失的原始場景；布局與尺寸仍需 leadi 驗收。

## 內容

- 主圖：`src/maps/main_battlefield/main_battlefield.tscn`；1920×1920 地面，只有重建道路，建築／草地容器留給手工擺放。
- 訓練場：`src/maps/training_ground/training_ground_playtest.tscn`；按環境、導航、遭遇、射擊場、除錯分類。舊城鎮封存於 `src/maps/archive/town_layout`。
- 道路：8 來源包、598 個模型／貼圖變體，含匹配的靜態碰撞。source bytes 不改；3 個缺 GLB 的獨特模型已轉檔。
- 客製道路：45° Curve2、三款緊湊 Y、內外接點；Road12 顯示／碰撞降低 0.015m，但接點安裝平面為 0。沒有恢復已捨棄的加長版本。
- 主路網：54 路口、72 邏輯連接、138 直路段。上半旋轉180°生成下半；左右紅圈按原估算7.96m淨距加倍為15.92m。
- 建築：102 款原始模型、938 配色模組與碰撞；分類展示、完整102款展示、同款13色展示。
- 坦克：4 個完整場景引用的 sample；只在展示父容器停用運作，複製個別坦克可繼承正常處理。
- 工具：右 Alt 最近且方向相容的端點吸附，多選整組平移；無舊按鈕與內外模式。

入口與複製方式見 `src/samples/README.md`。

## 實證

- 來源 fresh 驗收：8 ZIP CRC／SHA／抽取byte比對、路徑安全、冪等與拒覆寫測試通過。
- 建築 fresh 驗收：`BUILDING_LAYOUT_ACCEPTANCE failures=0`、`BUILDING_SAMPLES_SMOKE failures=0`；含938模組、碰撞一致、真實12色albedo、展示相機朝向、坦克原scene。
- 主路候選 fresh 幾何：`road_rebuild_acceptance: PASS`（54/72/138、實際Marker接縫、連通、中心對稱、1920地面、15.92淨距）。不是用產生器JSON自證。
- 全598道路與發布後主圖實跑：`road_rebuild_acceptance: PASS`，exit 0；完整log在 `artifacts-local/road-published-acceptance.log`，未略過catalog。
- 客製路件 fresh：`custom_final_acceptance: PASS`；四個閉環依實際Marker逐段相接，CW面向測試另以Godot PlaneMesh作控制組。實際渲染確認左右Y不再黑面。
- 訓練場：Training ground／Training range／960m map component／Enemy combat smoke validation passed。
- 完整導航：`ENEMY_NAVIGATION PASS`，四款坦克皆完成指定路線。首次120秒因測試最多含四次90秒行駛而不足；延長外部deadline、未改測試後正常完成。
- 吸附：solver、plugin parse、真 EditorUndoRedoManager 隔離整合均 PASS。
- Godot 實際渲染保存於 `artifacts-local`，包含主圖、道路展示、同款建築配色。

## 驗收限制與待辦

- 原生 Windows 編輯器的右 Alt、單選／多選拖曳與操作手感待 leadi 實測；隔離 UndoRedo 測試不取代原生 GUI。
- 圖像相似程度與重建尺寸待 leadi 確認；不是原 transforms 的逐位元恢復。
- 坦克接地／坡道／橋面行駛留 LEA-176，不以本次靜態碰撞宣稱完成。
- Road12 光影、閉環展示與全量道路驗收均已通過；畫面不是只靠固定print判斷。發布前舊主圖留在 `artifacts-local/main-before-publish-1789729332.tscn`。
- 整合 Claude Opus 複審報告尚未外傳：安全檢查要求針對具體檔案與目的地另行核可，已向使用者提出。

## 納管與離線復原

Git 保存生成器、引用場景、catalog、測試與文件。原始素材、內嵌幾何wrapper、衍生GLB／collision體積大且包含付費內容，採本機忽略與完整離線專案備份；不能只取 Git checkout 就宣稱可用。
原8ZIP另存：`/home/markchou/project/tank-skirmish-local-assets/AtomicRealmModularRoads`。
本次未執行 git push。本機 checkpoint：`c65f3e5`、`3ebfc83`。

完整備份目錄：`/home/markchou/project/tank-skirmish-local-assets/restore-points`。

- `lea177-20260918-190559.tar.gz`：包含原始素材、衍生模型、場景、生成器與測試；排除`.git`連結與可重建的Godot快取。
- `lea177-20260918-190559.bundle`：截至 `3ebfc83` 的完整Git歷史。
- `lea177-20260918-190559.tar.gz.sha256`：两者checksum重讀核對均為 `OK`；gzip檢查、必要路徑清單、Git bundle verify均通過（`LOCAL_BACKUP_PASS`）。

可用 `bash scripts/backup_restoration.sh <工程以外的絕對目錄>` 建立新備份，工具不覆蓋舊檔、不上傳任何資料。
Windows Godot 已啟動復原工程主圖（PID41584）；原工程PID4788未關閉。

清理僅涉及本代理誤寫到 agent-team 的兩個 trace 副本；刪前 SHA 與本工作樹版本一致，正確副本仍保留。該 trace 是前期參考，不是主圖生成來源；主圖以 `scripts/roads/build_main_roads.gd` 與實例幾何為準。
