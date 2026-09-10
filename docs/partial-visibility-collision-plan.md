# LEA-173 實作計畫 v2（兩輪跨模型審查完成）

## 目前狀態（2026-09-10，以本節為準）

- 交件核可：leadi 在架構整理與獨立驗收通過後核可集中提交及建立 PR，不含 merge／Linear 結案。以下「尚未提交」描述為本文件寫入時的本機驗收快照；後續 commit、PR 與遠端 CI 狀態以 GitHub 實際紀錄為準。
- 提交前架構複核未發現阻擋問題；leadi 核可先整理取樣上限常數及文件狀態。進度僅由本節維護，補充文件保留決策與歷史證據。本次整理已通過 baker 語法檢查、部位幾何 smoke、取樣邊界檢查（空集合拒絕、12 點接受、13 點拒絕）及 fresh-context 唯讀驗收；三項 Godot 檢查皆 exit 0，證據見 `/tmp/lea173-cleanup.5tOVPU/`。未重烘幾何或重跑完整 CI；尚未 commit／push／建立 PR。幾何衍生尺度重構及控制恢復流程不在本次範圍。
- Task 1 部位幾何與 Task 2 動作守門已實作並通過自動化驗收；後續車身接觸反應及三項修正亦通過獨立驗收，細節見 `tank-contact-and-turret-response.md`。砲塔雙向選路已取消，不在待辦。
- 使用者要求先確認多輪迭代的結構，再進下一個 Task。獨立結構審查確認資料、guard、接觸數學、controller lifecycle 責任可追蹤，無廢案 runtime 殘留，無阻擋 Task 3 的重構義務。
- Task 3 Vision／AI 已通過自動化測試、非作者獨立審查及使用者試玩驗收（2026-09-10）。Task 4 原網格版曾通過驗收，使用者試看後改採砲塔高度水平視野輪廓；新版已通過自動化、獨立驗收與 leadi F6 試玩驗收（2026-09-10：「可以 驗證通過」）；完整證據見 `horizontal-vision-preview.md` 末節，原 4m／2m 證據只作歷史。Task 5 已改採固定區域持續清骸，產品規則及技術計畫已核可並完成單輪複審，已通過本機自動化、完整 CI 與真畫面驗證（見 `region-wreck-cleanup.md`）；Task 5 已由 leadi 於 2026-09-10 回覆「驗收通過」，含綠色地板與對正追加，Gemini 四圖視覺複審已獲明確授權並通過，Task 6 集中 CI 與獨立驗收已通過，本單尚待提交／PR／merge 交件確認。
- `project.godot` 已依使用者核可還原成 Git 版本；當時接續前完整 `bash scripts/ci.sh` exit 0，輸出 `Tank Skirmish quality gate passed.`（`/tmp/lea173-body-fixes.I5Vweh/results/post-config-ci.log`）。Task 1/2 新 smoke 已於 Task 6 集中接入 CI 並通過，詳見下節集中驗證結果。
- 結構審查的非阻擋後續項：幾何頂點／半徑衍生資料來源收斂、AimPresentation 不可達 null fallback、PlayerController contact reset 重複片段。surface-point 上限已在本次整理改由 TankPartDefinition.MAX_SURFACE_POINTS 共用，數值維持 12，驗證已通過；尤其半徑來源變更需另驗既有 guard／接觸行為，不混入本次整理。證據：`/tmp/lea173-structure-review.md`、`/tmp/lea173-task6.eotk5K/architecture-review.md`。
- 以下日期化段落保留歷程；與本節進度衝突時以本節為準。產品行為仍依規格及已核可補充，不因狀態整理改變。尚未進行本單 commit／PR／merge／Linear 結案。


## Task 6 集中驗證（2026-09-10，已通過）

- leadi 在 Task 5 人類驗收通過後回覆「好繼續」，核可接續 Task 6。沿用既定單人產品、Godot 4.7.1、本機有限固定矩陣前提；本步只接 CI 與對帳證據，不重新設計玩法。
- 執行起點 HEAD：6e217ff1b5be247a7992c000b53d38c7a75eb1c7；Task 1–5 dirty 全保留。品質入口及狀態備份：/tmp/lea173-task6.eotk5K/。
- 封閉新增入口：tank_part_geometry_smoke、tank_motion_guard_fixture、tank_motion_guard_smoke、tank_motion_guard_wall_smoke、tank_contact_response_smoke、contact_review_regression_smoke、partial_visibility_smoke、partial_visibility_combat_smoke、vision_preview_smoke、region_wreck_cleanup_smoke。
- 只修改 scripts/quality.mjs 的執行清單，沿用既有串行 run、exit gate、Godot error scan 與 artifacts；保留所有原 suite 與 project.godot 保護。不得改測試斷言或產品程式以求綠燈。
- 排除模型 GPU 對照 probe、自動化 GPU 截圖框架、已取消砲塔選路；既有 GPU／F6 證據依 Task 1–5 最新裁決對帳，不把 headless PASS 當 GPU PASS。
- 本步完成條件：10 支入口確實執行且各產生有效通過 log、完整品質入口 exit 0、fresh-context 固定矩陣及差異範圍驗收；無新產品行為。PR／merge／Linear 待最終交件確認，不自動執行。

### Task 6 結果與交件狀態

- 正式 scripts/quality.mjs 僅新增 18 行，單一串行迴圈接入上述 10 支測試；既有 run gate、原 suite、錯誤掃描與 project.godot 保護均保留。沒有產品程式或測試斷言的本步新變更。
- 完整命令：GODOT_BIN 指定鎖定的 Linux Godot 4.7.1-stable，使用 /tmp/lea173-task6.eotk5K/ 下獨立 XDG 目錄，執行 node scripts/quality.mjs；exit 0，full-quality.log 末行為 Tank Skirmish quality gate passed。
- 10/10 新測試均產生本輪 artifacts/ci/<hyphen-name>.log（2026-09-10 22:11:58–22:15:08）：geometry、guard fixture 8 案、四車 runtime、牆面 16/16、contact H1–H5、contact review R1/R3、V1=38/V2=7、A1/A2、水平 preview、區域清骸。既有 enemy／training／combat boundary 等 suite 同輪通過。
- fresh-context 獨立驗收 PASS：逐份 artifact 內容與 mtime 核對，沒有舊 log 冒充；相對起點僅多品質入口 18/0 與本紀錄，HEAD 未變，git diff --check 與 node --check 均 exit 0。起訖 scope 存 status-before/after.txt 與 numstat-before/after.txt。
- 本步不改圖形，因此 GPU／F6 未重新執行；已對帳 Task 1–5 生效版本的既有模型對照、RTX 5090 真畫面及使用者試玩驗收，沒有把 headless 品質通過當作本輪 GPU 通過。
- Task 6 的集中驗證已完成；commit／PR／merge／Linear 尚未執行，待 leadi 確認集中交件。

## Task 4 新水平視野驗證結果（2026-09-10）

- 720 基礎方向與有限邊界補樣，每 physics frame 完整更新；RTX 5090 開放／建物／低高障礙 p95 3.529–3.577ms、max ≤3.886ms，四組像素比對皆零不符。
- fresh-context 獨立重跑 preview／training／A1A2／enemy 均通過；V1=38／V2=7、完整 CI exit 0（Tank Skirmish quality gate passed.）。CI 由主代理執行，獨立驗收者讀取結果；詳見新水平視野文件與 /tmp/lea173-radial-preview.6y18ze/。
- 紅色只代表砲塔高度水平視野，不預測整車被發現或炮彈命中；使用者已於 2026-09-10 確認驗收通過，Task 4 完成；此為 Task 4 收尾時狀態；Task 5 後續已核可並實作，最新狀態見文件頂部。

## 歷史：Task 4 格網版驗證結果（2026-09-10，不適用新版）

- **後續人類試看調整**：使用者要求解析度提高一倍，預覽預設格距已由 4m 改為 2m；AI 與每幀 4ms 初始預算不變。RTX 5090 三輪為 1077.293／1218.427／1269.778ms，GPU 像素矩陣 mismatches=0。此為試看版本，已超過原一秒更新目標；下列完整驗收與 CI 證據仍屬原 4m 版本，不冒稱 2m 也通過原效能門檻。截圖與 log：`/tmp/lea173-task4.OjNsCL/spacing-2m/`。
- 產品限共享 `tank_vision.gd` 核心、`vision_range_preview.gd`／shader、Encounter 既有玩家引用接線；新增 `vision_preview_smoke.gd`／uid，training smoke 僅將舊即時 uniform 斷言改為完整 published batch 驗證，其餘原有斷言保留。未改地圖、GLB、project.godot、AI 決策、controller 或傷害公式。
- 紅色代表目前玩家車型／世界朝向與砲塔、炮管姿態，搬至候選地表後任一部位可被發現；不是可射擊範圍。4m 格點、layer 128 地表、完整 bounds 保守剔除、中心優先 early return；排除觀察者與真實參考玩家，其餘車輛仍遮擋。R8 nearest、0 格透明、alpha 0.15，完整批次才交換 mask 與顯示位置／快照。
- 先紅後改：正式舊版的真 Vision 在固定掩體後為 false，但舊 analytic shader contract 仍為 true，`legacy-preview-red.log`／exit 1；另保存修改前 RTX 5090 真實畫面。這個紅測不是以缺少新 API 代替行為反例。
- 正式 P2 smoke exit 0：開放／掩體後／邊緣格與同姿態真 Vision 對照；四車、轉砲塔、重生等價新實例、動態遮擋增減、pending 原子交換、持續轉動不飢餓與更新計時。fresh-context 驗收者另行重跑 P2、training、Task 3 V1/V2 與 A1/A2，全部 exit 0。
- Task 3 回歸仍為 V1 38 案、V2 7 案；A2 遮擋時 90 ticks／90 queries／0 shots，解除後真 ShotEvent→Projectile→ImpactEvent→Health。training、enemy 及完整 `bash scripts/ci.sh` 均 exit 0，CI 末行為 `Tank Skirmish quality gate passed.`；新 smoke 集中 CI 接線仍留 Task 6。
- 真渲染使用 Windows Godot 4.7.1、Forward+／Vulkan、NVIDIA RTX 5090，非 Linux llvmpipe。一般視角、朝建築全景、開放遠扇全景的 GPU 像素矩陣皆 mismatches=0；開放遠扇含 240 個受驗遠距紅格。判讀排除被建物遮住與飽和白色網格的像素，排除數另列，不把它們當通過樣本。
- 正式訓練場實測單輪約 303–768ms；開放全景連續三輪為 316.165／400.854／418.175ms。每影格初始 deadline 為 4ms，量得 p95 約 4.4ms、max 4.646ms（單格離散查詢造成的小幅超出）；每輪約 22,074–35,125 rays。沒有減少部位或延長核可的一秒更新目標。
- 使用者明確同意外傳本次四張截圖後，Gemini 完成單輪視覺第二意見：未觀察到原 P1 的裁切／透明度／重疊加深缺陷；動態與 physics 真值另由測試判定，不從靜圖冒稱通過。
- 證據目錄：`/tmp/lea173-task4.OjNsCL/`；`p2-fourth.log`、四支 regression 的 `.log`／`.exit`、`full-ci.log`／`.exit`、`gpu-after-fifth.log`、`gpu-overview-second.log`、`gpu-overview-open.log`、`gemini-visual-review.log`、`fresh-acceptance.md`。HEAD 仍為 `6e217ff1b5be247a7992c000b53d38c7a75eb1c7`；Task 1–3 既有 dirty 修改保留，未 commit／PR／merge／Linear 結案。
- 人類驗收入口維持 `src/world/training_ground/training_ground_playtest.tscn` F6；請停止舊試玩再啟動，以載入新腳本。Task 4 人類確認前不啟動 Task 5。

## Task 3 驗證結果（2026-09-10）

- 產品變更限 `tank_vision.gd` 與 `tank_combat_ai.gd`：沿用既有部位表面點、逐點 range／LOS、中心可射時優先、每次 AI 更新只取一份可見點；最終仍通過真槍口方向／alignment／first-hit gate，沒有新增選點 cache 或另一套射擊管線。
- 正式 `tests/partial_visibility_smoke.gd`：V1 四車實際部位近／遠距共 38 案，V2 遮擋／範圍／邊界／自身排除共 7 案，`formal-new.exit=0`。
- 正式 `tests/partial_visibility_combat_smoke.gd`：A1 三種中心／替代部位選點；A2 真 AI 90 次更新、90 次 Vision 查詢、0 ShotEvent，解除槍口遮擋後由 AI 自行對齊，完成 1 次真 ShotEvent→Projectile→ImpactEvent→Health 扣血，射擊當刻 final gate 為真，`formal-combat.exit=0`。
- 舊 enemy smoke 僅相容多點視線所需的遮擋 fixture；固定玩家姿態後還原原 processing 狀態，遮屏依真射線交點建立且不接觸觀察車。原受擊查看、車身轉向、射擊、停止追蹤／開火、重生／恢復斷言完整保留，完整 CI 中的正式 enemy smoke 通過。
- Task 1 幾何、Task 2 guard fixture／runtime／16 案牆面矩陣、H1–H5 接觸與接觸修正、散布、combat boundary、training ground、固定砲塔瞄準皆獨立實跑 exit 0；完整 `bash scripts/ci.sh` exit 0，末行 `Tank Skirmish quality gate passed.`。紀錄目錄：`/tmp/lea173-task3.6PzF3q/results/`，完整 CI 為 `full-ci.log`／`full-ci.exit`。
- 核心舊／新版本對照仍保留：`core-baseline-red.exit=1`、`core-current-green.exit=0`。實作曾先於紅測套用，因此此為版本對照證據，不宣稱嚴格先紅後改。
- V1/V2、A1/A2、enemy fixture 皆由非作者獨立唯讀審查通過。受新代理名額限制，審查沿用既有上下文，並引用主線實跑紀錄，非 fresh-context 重跑。使用者於 2026-09-10 明確回覆「可以 驗收通過」，Task 3 人類試玩通過。
- 正式新 smoke 的集中 CI 接線仍屬 Task 6；本次已明確分別執行。結構審查既有 backlog 不在本 Task 擴修。

## 目標與鎖定前提

- 基線：Tank Skirmish `main`，`6e217ff1b5be247a7992c000b53d38c7a75eb1c7`；LEA-172 已合併、結案且 main CI 通過。
- 規格：`docs/partial-visibility-collision-spec.md` v1；C1–C3、V1–V2、A1–A2、P1–P2、R1 是固定驗收矩陣。
- 目標使用者／類比／Identity／動機覆核：維持 leadi 親測的 Windows 單人街區坦克遊戲；目的為掩體邊緣的碰撞與交戰可信度，不是通用物理／感測框架。
- 使用者 2026-09-09 已要求接續實作。本單仍採互動開發，完成可玩結果後交 leadi 驗收；不啟動無人 Job，不自動合併未經人類驗收的視覺結果。
- 原規格已完成逐題澄清與 glossary。先前 Claude 規格審查有有效 result，讀取的內容與現檔實質一致；以下是 Team Lead 的裁決，不是 reviewer 新增的需求。

## 規格複審裁決與介面語意

1. 中心是優先的「瞄準方向／目標座標」，不是要求車體中心本身位於碰撞表面。砲彈沿此方向先接觸同車表面即為有效命中。穩定車體中心不隨選中部位改變。
2. 同車部位共用原 Tank CharacterBody3D／RID；物理查詢排除整個自己，沿用 ImpactEvent 的 collider == Tank 和同車 Health。不建立每部位 PhysicsBody、owner 尋找鏈或部位血量。
3. Tank1 沒有獨立砲塔 mesh，但已有 TurretPivot／GunYawAdapter；沿用既有觀察掛點，不能為了統一程式虛構砲塔。
4. Tank4 的既有上車體 mesh 必須有碰撞，但保持固定，歸入 fixed_upper_hull；不改為可水平旋轉的獨立砲塔，不降為不可命中的純視覺。
5. 可見但皆不可射時，瞄準穩定排序的第一個可見候選點，不開火；無新增掃描、追擊或破牆。這是既有 A2 的局部選點慣例，不新增產品義務。
6. 多敵共享預覽、無限薄牆數學 CCD、任意高速瞬移等不納入。只有原 AC 的有限可重現反例可阻擋本單。

## 技術方案與資料責任

### A. 同一套部位幾何，不複製戰鬥管線

- 新增專案內的 TankPartGeometry，擁有四車明列的 hull、left_track、right_track、gun、實際存在的 turret／fixed_upper_hull 描述。
- 每部位保存模型引用、所屬機械轉軸（hull/turret/gun）、局部幾何、凸碰撞形狀與有限表面取樣點。四款固定素材以專案內 `scripts/bake_tank_parts.gd` 預先生成受版控的部位資源；執行時只載入與綁定，不在換車／重生時跑凸分解。物理步驟只轉換快取點與形狀；不建立一般匯入插件或熱重建框架。
- 碰撞從指定部位 mesh 產生凸形狀；凹部使用 Godot 的凸分解，不拿整車 AABB 代替。每部位最多 16 個凸形狀（2026-09-09 使用者看過原型後核可，由初始 8 個上調）；正常外輪廓碰撞近似偏差目標仍為 0.05m。以四車三向外輪廓與炮管斜姿態的有限探針量測；未達標時先回報，不增加無上限分解或默默放寬誤差。
- runtime 探針確認四車 hull／左右履帶皆為有 Skin 的 MeshInstance3D，不能直接假定原始 Mesh.get_faces 等於渲染姿態。離線 baker 在已初始化的 Skeleton3D 中性姿態使用 bake_mesh_from_current_skeleton_pose 取得幾何，統一轉回機械局部座標；其 GPU 同步成本只准發生於離線生成。履帶動畫只動 TankTrack 骨骼，固定碰撞不逐履帶節變形；以動畫 0／25／50／75% 的外輪廓探針檢查 0.05m 目標，未達標回報，不自行加入 runtime skinning。gun／turret 依實際轉軸綁定；純視覺後座不參與。
- 表面點直接由該部位模型三角形／頂點取得；依前後左右上下極值與均勻分散點作固定排序，每部位初始上限 12 點；炮管保留口端、根端與中段兩側，不以整個細長炮管的 AABB 角點當可見點。C1/V1 若顯示此數量漏掉規格正常露出案例，再在本單固定案例內由 root 調整密度，不刪除該部位。
- 各 CollisionShape3D 都是 Tank 的直屬子節點，仍由原 CharacterBody3D 管理。現有根 `CollisionShape3D` 名稱可保留作第一個 hull shape，但其 `BoxShape3D` 型別不再是 public contract。
- 將舊中心的本地位置保存為獨立穩定值；TankVision.target_world_position 讀此中心，不能改讀任一移動部位或臨時 aim point。
- 機械 transform 使用 Tank root、TurretPivot yaw、GunPitchPivot pitch 與初始化的 mesh offset；排除 VisualRecoilPivot tween 位移、煙火與損傷純視覺姿態。碰撞不追隨視覺後座。
- 提供固定介面：取得當前部位形狀／世界 transform、有限世界表面點、穩定中心、所有部位保守世界 bounds，以及按候選 root/yaw/pitch 計算形狀 transform。資料均屬本車實例，不存舊玩家節點／RID。
- AimPresentation 的近車隱藏距離改用幾何 bounds／點集合，不再 as BoxShape3D；僅影響避開車體的長度計算，不改已驗收的準星樣式。

### B. 動作先檢查、通過才寫入

- 線性移動沿用 CharacterBody3D.move_and_slide；新部位 shape 全部參與原移動碰撞層，不引入新推車或彈力公式。
- 車體 yaw、砲塔 yaw、炮管 pitch 的現有入口先計算候選姿態，查詢後才套用。車體、砲塔、炮管仍保持現有順序；不新增全場 transaction 或物理排程器。
- 每次旋轉依受影響形狀最遠點距轉軸的半徑計算弧長，再分成外緣移動不超過 0.02m 的子步。每個子步都查，而非只驗最後姿態；在第一個被擋的子步前停下。
- 初始 shape-query 接觸容差 0.002m。物理阻擋沿用現有坦克 collision_mask（當前為 layer 1），不把僅供視線／彈道的地表 layer 128 誤作側牆；地表仍參與 Vision／Projectile 的既有 129 遮罩。
- 正常未相交姿態在碰撞前停下，反向應立刻可動。初始已有接觸／輕微重疊的判定方法如下，不能用「碰到過這個物件就整個忽略」放行往內轉：
  1. 對每個 query shape 用 intersect_shape 列完整接觸 collider/RID（上限取場景節點數）；排除自己。新出現的外部 collider 直接阻擋該候選子步。
  2. 已接觸的 collider 逐一比較：把其餘已列出的 collider RID 加入 query.exclude，使用 collide_shape(query, 256) 取得該 collider 的接觸點對。這不是把 collide_shape 宣稱為引擎 signed-depth API，而是使用文件定義的 query-shape／obstacle 表面點對。
  3. 有限深度代理為 max(distance(pair0,pair1))。保存原姿態 pair0 的 shape-local 材料座標；以候選 transform 投回，向外 normal=(pair1-pair0).normalized，計算該材料點的候選位移 dot normal。
  4. 有深度的既有接觸只允許最大點對距離不增加、且各舊接觸材料點不向障礙物內移動的候選；無位移／精確相切保持現況。接觸數量上限打滿或無法判定時不猜放行，回報 fixture 供 root 調整有限上限。每個接受子步都以其真實新姿態更新接觸資料；0.002m query 接觸容差不是每步可多穿入的額度。
  5. 僅在當前已有 overlap 的少數 shape 執行 contact-pair 查詢，開放場地只做便宜的 overlap 預檢。接觸 normal 判斷不能取代新障礙物檢查或逐旋轉子步檢查。
- 上述比較已以一個有限 Box 牆原型驗證：old/out/in 最大點對距離 0.105074234/0.104198128/0.105950341m；材料點 normal dot 為向外 +0.000876087、向內 -0.000876087，均只 2 對接觸（max_results=32，未達上限）。正式四車與多凸部位仍須 C2/C3 實跑，不能把此原型當全車驗收。
- 旋轉被擋後 actual angular speed 依真正套用角度回寫，履帶與擴散不採用未實現的角速度；既有停止旋轉／死亡停用接口保留。
- 另量測真車最壞同幀 root/turret/gun 三軸動作、凸形數量與子步數的 guard query 計數及 p95/max；不能拿預覽 ray 微基準代替 shape-query 成本。確認新增物理工作未造成現有訓練場操作停頓後才交件。
- 在接入正式 controller 前，先以隔離有限 fixture 驗證長炮管中途掃牆、地板接觸、反向離開；沒有可重現 PASS 不把該演算法接入正式車型。

### C. 發現、選點與真實射擊分開

- Vision 共用一個「給定部位點與參考姿態」的可見性核心：逐點查既有 XZ 近圈／砲塔遠扇形，再查觀察掛點至該點的 3D 遮擋。
- 射線到候選點時，同一 target 的其他部位不是外部遮擋者。真車查詢只在目標本身或無外部障礙時視為此方向可見；虛擬預覽排除真實位置的參考玩家，不能留下第二台幽靈遮擋物。
- 保持 can_see(target) wrapper；AI 每物理步取得一次可見候選資料，不先 can_see 再重做全量取樣。受擊查看可沿用既有 wrapper。
- 中心可見且炮口到中心沒有外部遮擋時優先；否則按固定部位／點順序找可見又可射的表面點。全不可射時仍返回可見 aim point 與 can_fire=false。
- 最後開火守門仍用當下 muzzle_global_direction，AND 對準角、第一個真正命中目標 owner、既有射速。不能只靠「朝選點的理想線」便直接開火。
- 不改 ShotEvent、Projectile、ImpactEvent、DamageReceiver 公式或血量；增加真實砲彈命中露出炮管／其他部位的驗收。

### D. 原姿態相依預覽（歷史方案，已取代）

2026-09-10 使用者改採水平視野，新 Task 4 的實作／驗收唯一依據為 `horizontal-vision-preview.md`；以下格網與整車假想設計保留為歷史，不再約束新預覽。其他 Task 不受影響。

- 參考目標由 Encounter／PlayerRuntime 的既有 controlled_tank_changed 接線提供；使用當前玩家型號與姿態，換車／重生時更新引用。
- 每個預覽格點代表把參考車保留世界朝向、平移至該 XZ 並依地表高度放置；使用與實際 Vision 相同的部位點與範圍規則。
- 距離／角度仍逐部位點判斷，不在玩家中心離開圓扇時提前排除整車。預覽根位置的外緣可反映車體尺寸；不把可見炮管裁回舊單中心輪廓。
- 初始格距 4m，網格涵蓋視野半徑加參考部位最大水平延伸。先用參考 bounds 保守排除整車都在聯集外的格，再查中心；有一個可見點即 early return，不做剩餘射線。
- 每物理影格預覽工作初始預算 4ms；以完整參考姿態／觀察位置快照分批建下一張 R8 mask，完整批次才交換顯示，避免不同姿態的格點混成一張圖。顯示平面的 world origin、extent、mask 與 observer/reference 參數同批交換，禁止把舊 mask 套到新圓扇或平移至新原點。玩家／觀察車實例失效或切換時清除舊 mask；連續姿態更新採下一批，不因持續轉動而永遠取消重算。此快照不凍結整個 physics world；動態遮擋以有界更新週期重新查詢，不新增全場快照機制。
- 目標：本機既有訓練場完成一輪更新不超過 1 秒；記錄實際每輪時間、每影格 p95／max 與射線數。不得用拉長到不可操作的週期默認驗收；超標先回報量測與取捨，不擅自省部位或改紅色含義。
- mask 採 nearest sampling，0 格透明，不能因 bilinear 插值讓完全不可見格變紅。保留原 tint alpha 0.15 與單次聯集著色；不另繪未遮擋理論圓扇。
- 表面高度查詢用既有地表 layer 128；invalid ground 格不假造可放置位置。不新建導航或出生點保證。
- 預覽不得控制 AI 或射擊；禁用預覽後仍維持同樣交戰。編輯器如未有有效 physics space／參考車，安全隱藏，不冒充已裁切的理論圈。

## 先行量測證據（不是實作通過）

- 本機 Godot 4.7.1、現有訓練場、known building hit=true；隔離 probe 未保存任何遊戲場景或修改 repo。
- 1000 條射線：0.550／0.544／0.559ms；10000 條：8.721／8.477／8.551ms，平均 8.583ms。
- 8100 格 × 73 條的全量保守上限約 591300 rays，線性外推約 507ms／輪，故不能一次同步全部計算。
- 此數據未包含正式多形狀場景與 GDScript 表面點變換成本，也未量到保守範圍剔除／early-return 的節省；不能把外推當最終效能 PASS。
- 補充成本 probe：地表 mask=128 的 256／1000 次查詢皆 100% 命中 Y≈0，約 1.16–1.19µs／query。以舊車盒僅作成本估算的保守聯集範圍剔除，8100 格保留 2166 格（26.7%）；各 73 rays 粗估約 134ms／輪。正式剔除必須採新部位 bounds，不能沿用舊盒的 4.042m 半徑常數。

## 第一輪計畫審查修訂與四問覆核

- B1 採納：以直接 collide_shape 接觸對與材料點位移寫清楚有限比較方法，附原型量測；同幀中途 sweep 與初始 overlap 退出是兩項不同證據，不能混為一談。
- B2 採納其查證目的：四車 GLB 已有獨立部位節點盤點，再以 runtime MeshInstance3D／有效幾何讀回封閉資料來源；不因此增加新部位或更改 Tank4 能力。
- B2 runtime 證據：四車 hull 頂點數為 7782／6646／7011／14856，左右 track 各 1232；gun 為 246／282／336／880。Tank1 確實沒有 turret，Tank2／3 的 turret 為 2104／714 頂點，Tank4 固定上車體為 132；全部實際存在的部位 mesh 非空。初始化後 gun/turret 已在機械 pivot 下，hull/track 位於 Skeleton3D 下；離線烘焙是否符合動態外輪廓仍是 Task 1 驗收，不冒稱已通過。
- 重生首次同步、純視覺後座隔離、端點接地、mask 錨點與 shape-query 成本均併入既有 C1–R1 驗證；不新增無人框架、場景複製或瞬時全域一致性要求。
- 4m／一秒內完成一輪的有限預覽更新是待 leadi 裁決的初始體驗參數，並非已量測到正式實作達標。
- v2 四問覆核：使用者、類比、作品定位、動機全部維持 v1，沒有新的 actor／平台／產品義務。

## 封閉執行順序

每個 Task 開工前由 root 整理對應固定 AC／檔案 packet 並交執行層；新架構／介面衝突或超出下列範圍先升回 root，不自行擴寫計畫。

1. **部位幾何與相容接線（C1，R1 中的中心／換車）**：新增 `src/actors/tank/geometry/`、`scripts/bake_tank_parts.gd`、四車 variant 部位資料、base/controller 初始化與必要 uid。形狀只更換幾何，保留 owner／Health。更新 AimPresentation 的單盒讀取。以四車模型有限外輪廓探針與 runtime transform 驗證；先保持開放平地可操作。
2. **實體動作守門（C2、C3）**：隔離旋轉 probe 通過後接到三個既有姿態入口。改動限 tank geometry／motion guard／controller 與新碰撞測試，不改數值平衡／導航。真實既有建築四車平移、偏航、砲塔、炮管進退，以及不推彈其他車。
3. **Vision 與 AI（V1、V2、A1、A2）**：改 perception/tank_vision.gd、ai/tank_combat_ai.gd；新增參數化部位露出與真 Projectile 整合測試。不碰 UI 或傷害公式。保持受擊側查看中心語意。
4. **預覽（P1、P2；2026-09-10 新裁決）**：依 `horizontal-vision-preview.md` 改為砲塔高度水平射線輪廓；改 vision_range_preview.gd/shader、移除 Encounter 預覽玩家 reference 接線，替換兩個 preview 相關 smoke 斷言。有限 S1–S4 驗範圍／高度／殘骸／動態更新／效能與 GPU；不改 AI、Vision 或地圖擺位。
5. **區域清骸與重生整合（R1；2026-09-10 新裁決）**：依 `region-wreck-cleanup.md` 的 Z1–Z5／R1 與封閉 allowlist，實作可重用區域偵測及持續清除殘骸；立體範圍只在編輯器顯綠色；另依試玩追加提供遊戲中可見、對齊格線的綠色出生點地板。移除舊重生時清骸，補齊死亡車提前移除後的空綁／三秒重生／敵車切換接線，活車不額外處理，不預建其他區域效果。技術計畫已複審並獲使用者核可；重生與區域清除維持獨立，本機驗證與 leadi 人類驗收均通過（2026-09-10），Task 5 完成。
6. **完整驗證與人類交件**：新 smoke 接 scripts/quality.mjs；`node scripts/quality.mjs` exit 0，fresh-context 固定矩陣驗收；GPU 渲染驗證預覽與模型碰撞對照；交 leadi F6 試玩，於本單微調。PR／CI／merge 於人類定案後集中收尾。

Task 1～5 各自修改/新增的測試用 apply_patch；新生成幾何資源只限 tank geometry/variant 明確目錄。不得更新 GLB 原始模型、BinbunVFX、project.godot 或訓練場建築／靶位以求測試通過。若其中某檔真為必要介面變更，先由 root 說明，不讓執行者自動越界。

## 回歸與驗收證據

- 固定工具：Godot 4.7.1-stable；本機正式場景 `src/world/training_ground/training_ground_playtest.tscn` F6。
- 既有 `enemy_combat_smoke.gd`、`combat_boundary_smoke.gd`、`training_ground_smoke.gd`、其餘 quality suite 保留；每步跑相關 smoke，集中交件再跑完整 quality。
- C1/V1 四車依實際部位參數化；Tank1 不含 turret，Tank4 upper hull 不作可旋轉砲塔。不得只測中型、只測車體而稱全四車通過。
- C2 記錄每個阻擋案例的起訖與中途姿態、實際外緣步長，緊接反向退出；不是只驗最後 transform。
- A2 至少一個真 ShotEvent→Projectile→ImpactEvent→Health 命中替代部位案例。
- P1 必須看到 GPU 渲染截圖／實跑，不以 shader uniform 或純 headless PASS 取代；P2 使用固定少量開放、掩體後、邊緣格點比對同姿態的實際可見性。
- R1 驗證近圈受擊查看、中心→命中點、四車切換與 AI 目標、3秒中央重生、2秒免傷；清骸以新固定區域的 Z1–Z5 為準，區內即清、區外保留，含死亡車早於重生被移除的正常流程。
- 每輪報告必列 exact HEAD／dirty scope、命令／exit、未驗證項與 blocker/backlog 分類；不將暫存 probe 結果誤稱正式實作驗收。

## 停止／升級界線

- 原規格 C1–R1 的可重現反例是真 blocker；不以效能或引擎限制默默削弱炮管、履帶、轉動阻擋或紅色語意。
- 如撞牆退出需要改玩家可見操作語意、部位 fitting 無法達約定有限探針誤差、預覽超過預算，先回報具體數據與最小選項，由 root／使用者裁決。
- 不修 Core、不建立新 Job、不做多人／當機恢復／通用 CCD、不刪使用者場景配置、不把 reviewer advisory 變成新驗收矩陣。

## 官方技術依據

- PhysicsDirectSpaceState3D 的 cast_motion 是位移查詢，已相交形狀會被忽略；intersect_shape 不使用 motion。不能將單次終點 overlap 說成旋轉 sweep：https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html
- 動態凹模型可由多個凸碰撞形狀組合，並有成本取捨：https://docs.godotengine.org/en/stable/classes/class_convexpolygonshape3d.html

## 第二輪審查裁決

- Claude 有效 result：success、is_error=false、terminal_reason=completed；B1、B2 皆已關閉，沒有直接 blocker。
- 採納：保留接觸對比較與 runtime mesh／skin 烘焙方案；正式車型證據仍依 Task 1、2 的原 AC 驗證。
- 後續 backlog：接觸深度與材料點條件的獨立性額外案例，不新增本單完成條件。
- 審查當時未驗證：正式四車碰撞、AI、預覽 GPU 與整套 quality；當時只有文件與隔離探針。最新實作狀態見下節。

## Task 1 執行證據與停止點（2026-09-09，尚未完成）

- 已實作四車部位資源、離線 skin 烘焙／凸分解、Tank 直屬 shape、機械姿態與後座隔離、穩定中心及 AimPresentation 相容接線。未開始 Task 2～6。
- 修改前 `node scripts/quality.mjs` exit 0。修改後基本部位 geometry smoke、`smoke.gd`、`training_ground_smoke.gd`、`tank_variant_refactor_smoke.gd` 各 exit 0；尚未重跑完整 quality，也未完成 Task 1 全矩陣驗收。
- 輪廓 probe exit 1。Godot 原生 source triangle body、Tank shape、獨立 stored convex 與即席同設定分解對照證實：Tank1 hull 凸形跨過模型空隙，提早約 1.579497m 命中。座標、skin、序列化與 triangle ray 誤差已排除；0.05m 目標未達。
- 已修正分解 API 屬性並驗證設定：max_concavity=0.002、resolution=100000、max_convex_hulls=8、max_num_vertices_per_convex_hull=64。四車總 hull=21/21/32/26，各部位仍不超過8，但不能據此宣稱輪廓合格。
- 有限自然分群盤點：四車 hull 連通三角群=53/49/43/78；Tank1 按五個現有 mesh surfaces 分解需31個 hull，可保留已確認的最壞空隙，但超出8個上限。這不證明所有可能的8個分組都不可行，也不證明31個能通過完整矩陣。
- 當時停止點：不再盲調參數或擅自放寬精度／上限。專用有限分塊、替代離線生成，或提高凸形上限的取捨交使用者裁決；替代方案均尚未驗證。
- 詳細獨立診斷：`/tmp/lea173-task1-fit-diagnosis.md`。測試 log：`/tmp/lea173-task1-{baseline-quality,bake,mesh-collision-probe,tank-variant,training-ground,smoke}.log`。

## 使用者核可接續：車型專用有限分塊（2026-09-09）

- 使用者在白話釐清碰撞外殼／分塊／烘焙後明確核可此方向。先以 Tank1 驗證，再推廣至其餘三車；仍屬 Task 1，不啟動 Task 2～6。
- 採模型幾何導出的、固定車型專屬分區；不改 GLB／runtime 戰鬥管線，不將部位或模型細節直接刪除。離線產出原格式的凸形資源。
- 先保留每部位最多8個凸形與0.05m有限輪廓目標，不承諾未量測的分組能通過。明確分組規則以 Tank1 隔離 prototype 與原生物理對照結果決定，不再盲調整車凸分解參數。
- 基本接線與既有回歸證據保留；補齊原矩陣的逐部位、正常炮管斜姿態與履帶相位檢查，不刪已失敗射線來換取綠燈。

### Tank1 正式資料驗證停點（2026-09-09）

後續裁決：使用者已明確回覆「接受」履帶整圈平滑外殼。此處停點保留為歷史證據；接續執行下節的新履帶合約。

- 已產生 Tank1 車身 8 組原始幾何凸形、炮管單一原始頂點凸形；其他三車未套用本輪分組。烘焙 exit 0，`parts=4 hulls=25`；每條履帶仍保留原 8 個形狀。
- 隔離 prototype 的 48 條射線通過，僅代表該矩陣；不能宣稱車身／炮管正式驗收通過。
- 正式 `tank_part_geometry_smoke.gd` exit 0；`tank_part_mesh_collision_probe.gd` exit 1。Tank1 車身逐部位側向誤差約 0.091m，炮管中性射線誤差 2.465091m、斜姿態 0.072568/0.122558m，仍不符合既定精度。保留全部失敗，不宣稱 Task 1 完成。
- 履帶半週期的原生射線有漏撞／多撞；最近三角形距離量測約 0.094～0.098m。動畫中性與半週期表面最近距離另量到 0.113232255m，顯示逐履帶節完整表面與固定外殼的 0.05m 雙向貼合要求不相容；此幾何結果不等同有限射線驗收全部不可能。
- 停止繼續修形狀或放寬測試，待使用者裁決履帶採整圈平滑外輪廓、還是保留逐節動畫貼合需求。車身／炮管的現有失敗另外保留；不因履帶取捨自動豁免。
- 證據：`/tmp/lea173-tank1-semantic-bake.log`、`/tmp/lea173-root-semantic-geometry-smoke.log`、`/tmp/lea173-root-semantic-collision-probe.log`、`/tmp/lea173-task1-track-phase-separation.log`。本輪 root 正式實跑是獨立驗證 pass，並非 fresh-context 最終驗收。

### 使用者核可：履帶平滑外殼（2026-09-09）

- 使用者接受履帶整圈固定平滑外殼，保留可見轉動動畫，節片間小縫隙不再穿透；未豁免車身、炮管、砲塔等其他部位精度。
- 固定實作：每條履帶取原始 skin mesh 在動畫 0／25／50／75% 的三角頂點聯集，離線建立單一凸形，保留原機械座標。不得使用整車 AABB、改原素材、增加 runtime skin bake 或每幀重建碰撞。
- 有限驗收：保留原 390 對射線及其來源位置；履帶與整車案例的履帶部分改對照上述獨立生成的平滑 reference，5cm 門檻不變。非履帶部位仍對照原 mesh。原始節片三角形差異保留為診斷資料，不再將已核可忽略的縫隙當成 blocker。
- 驗證履帶每部位一個固定形狀，四動畫相位不改變該形狀與機械 transform；surface visibility samples 仍取實際中性 mesh，不拿空隙中的碰撞面冒充可見表面。
- 先重烘 Tank1；其餘三車待 Tank1 正式案例收斂後再套用。現有車身與炮管反例仍需修正，不啟動 Task 2～6。

### 使用者追加核可：炮口封閉（2026-09-09）

- 使用者明確表示「炮口也一樣」。只將最前端炮口內孔視為封閉碰撞面，畫面素材不變；炮管外側輪廓仍遵守 0.05m 有限射線門檻。
- 正式 reference 保留原始炮管三角形，僅在炮口外緣所在平面補面；不得直接用正式凸形當 reference，也不得將整根炮管改成任意平滑包絡後豁免所有誤差。
- 原始未封口三角形的差異保留為 advisory；neutral／可達 yaw+pitch 的既有射線端點與其他部位的驗收維持原樣。
- Tank1 唯讀拓撲資料已有 10 個軸向截面；接續先驗證按實際管徑轉折分成 5 個實心凸形，避免跨越炮管頸部凹處。這是有限候選，未通過正式相同射線前不宣稱完成。
- 拓撲覆核修正：第 8 號截面實際屬於內孔底部（只連接第 0 號炮口）；外壁直接連接第 7／9 號截面。因此不把內孔底部誤當外壁頸部，正式分組採 [0..3]、[3..4]、[4..7]、[7..9] 四段。原始外壁頂點不變，僅碰撞封閉內孔。此候選對原本 15 條中性／斜姿態及反例射線全部通過，最大差 0.000062704m；仍須正式完整 probe 接入驗證。
- 車身側面原反例的局部對照證實 c04 單獨凸形與原 mesh 差約 0.000065m；c02／c09／c14 都不命中該射線。將 c04 與附件分開；低平台 c15 合併至低車身群（高度低於原反例），仍完整覆蓋全部 53 components、總共 8 群，天線 c16 維持獨立。接續以完整正式矩陣確認，不以局部對照代替最終驗收。

### Tank1 子里程碑已驗證（2026-09-09）

- 正式 Tank1：車身 8 形狀、左右履帶各 1、炮管 4，合計 14；90 組原有限射線全部通過，最大 first-hit 差 0.000173m（限制 0.05m）。履帶縫隙與炮口內孔的 raw 差異仍列 advisory；沒有刪掉原射線。
- fresh-context 驗收結果 `limited Tank1 PASS`；幾何／owner smoke 通過；確認沒有 runtime skin bake／逐幀重建形狀。證據：`/tmp/lea173-tank1-probe.log`、`/tmp/lea173-tank1-geometry-smoke.log`。root 重跑的既有 variant-refactor 與基本 smoke 亦 exit 0。
- 已將相同履帶生成規則套用至 Tank2／Tank3／Tank4（各自烘焙 exit 0）。其餘車型的車身／炮管／上部結構仍在逐一收斂；Task 1 四車整體尚未完成，不啟動 Task 2～6。

### 四車履帶與炮管子交付已驗證（2026-09-09）

- 四車共八條履帶的四相位獨立 reference／固定形狀檢查皆通過；證據 `/tmp/lea173-all-tracks-accept-logs/tank_part_mesh_collision_probe.log` 與同目錄 geometry smoke。原始節片差異保留 advisory，不改可見動畫。
- 四車炮管各 12 條正式 neutral／yaw+pitch 射線皆通過獨立驗收；形狀數依序 4／5／7／8。Tank3 保留既有分解形狀，沒有套用未通過的試驗候選。證據 `/tmp/lea173-all-guns-accept-probe.log`、`/tmp/lea173-all-guns-accept-geometry-smoke.log`。
- 炮口 reference 使用各車原始 mesh 加前端封口，不使用正式凸形充當 reference；Tank3 炮管前向是 local -Y，其餘三車為 -X。外側仍為原 0.05m 門檻，原未封口差異保留 advisory。
- Tank4 炮管以八組實際側壁建形狀，台階兩側分開。其 `get_faces()` 會將鄰近原始頂點合併，實測 raw input 為 12 components／26 截面、cache faces 卻為 8／27；正式 authoring 因而直接讀 surface indices。截面分類用 `is_equal_approx` 辨識同平面噪音，所有原頂點原值保留，不做 snap。
- Tank4 fixed upper 改為兩個連通構件分別分解、合計四形狀；正式六向 reference 通過（`/tmp/lea173-after-upper-formal.log`），未另宣稱這是 Task 1 最終 fresh-context 驗收。
- 未完：Tank2／Tank3／Tank4 車身與 Tank3 砲塔仍保留原始 FAIL；其他內部接合空洞是否可封閉尚待使用者裁決，沒有套用新的例外。390 組原有限矩陣仍在，Task 1 不標完成。
- 全套 quality 查到 legacy enemy side-hit fixture 用 `stable_center + X*3` 射向新幾何的空氣處；native ray miss、HP 不變，已定位為測試相容問題，僅修改該 fixture 取得實際可命中表面點，不改 runtime 傷害／AI 行為。

### 內部空洞與裝飾簡化裁決（2026-09-09）

- 使用者核可直接填滿被其他零件遮住的車身／砲塔內部接合空洞；可見外輪廓仍維持 0.05m，不填平外側凹槽。
- 使用者追加車身裝飾細節不需要碰撞。天線、小把手、螺栓等裝飾只保留顯示；碰撞及可命中表面點排除它們，不自動把所有小構件／輪組當裝飾。
- 固定驗證射線與主要部位保留；參考由原始模型明列的主要構件與封口面建立，原始未簡化差異保留紀錄。不得改用正式凸形作獨立 reference 或用放寬外側門檻取得通過。
- 仍在 Task 1；不啟動 Task 2～6。上節「內部接合空洞尚待裁決」已由本節取代；此處是核可範圍，不是宣稱實作／驗收完成。
- 全套 quality 在 enemy combat／damage health 通過後，停於 `tank_aim_spread_smoke.gd:199` 的第二發射擊散布斷言，單獨重跑同樣失敗；原因未定，不歸因於精度。證據 `/tmp/lea173-task1-quality-after-compat.log`、`/tmp/lea173-aim-spread-recheck.log`。

### 簡化實作進度（2026-09-09）

- Tank3 砲塔改為四個原始連通構件各一凸形；原始底部十個共面邊界點建立獨立封口 reference。neutral／yaw 共 12 條射線通過 fresh-context 驗收；可見外側仍為 0.05m，沒有把正式凸形當標準答案。
- Tank1 車身省略 c16 天線（44 triangles），其他 52 個構件保留，車身由八形狀減為七形狀。表面取樣從保留構件重選；獨立驗證天線中段 raw mesh 命中、正式碰撞 MISS，原 90 條射線仍通過。上述兩項的證據在 `/tmp/lea173-simplification-accept/`。
- 依實際三角面圖作產品取捨：輪罩小外掛塊、細肋與細格柵省略獨立碰撞需求。Tank2 排除 c05–08／c15–34，共 448 triangles；Tank3 排除 c01–02／c04–05／c13–28，共 240；Tank4 排除 c13–20／c25–64，共 480。不是以構件大小作自動刪除規則，其他主要車殼、輪組、履帶與可見模型保留。
- 三車 baker 對原始 triangle／component counts 及省略 triangle count 做固定素材檢查；只把保留的 source mesh 送原本凸分解並取樣，不修改可見 mesh。四車烘焙 exit 0：`/tmp/lea173-all-decoration-bake.log`；上述三車裝飾省略的最終獨立驗收另記。
- 三車中央上方的模型是封閉凹穴／內部接合區，不全是有開口 rim 的洞；不能為了取得封口任意切掉外側面。Tank2–4 車身外側仍有原本的貼合差異，本節不宣稱 Task 1 整體完成。
- 散布假紅已定位為測試把四台坦克疊在原點，物理解算推開後增加移動散布；只在加入場景前按 X=0／100／200／300m 分隔測試車，保留原散布斷言與 runtime。單測 exit 0：`/tmp/lea173-aim-spread-after-fixture.log`。裝飾全車重烘焙前的完整 quality 已 exit 0（`/tmp/lea173-task1-quality-after-isolation.log`）；重烘焙後完整回歸另記。

### 簡化子交付驗證結果（2026-09-09）

- 重烘焙後完整既有品質回歸通過：`node scripts/quality.mjs` exit 0、`Tank Skirmish quality gate passed.`；證據 `/tmp/lea173-task1-quality-after-decoration.log`。
- 最終 fresh-context 有限驗收 PASS：三車裝飾省略與 12 個保留結構取樣點皆通過；Tank1 天線、Tank3 砲塔封底、四車炮管／履帶均無回歸。證據 `/tmp/lea173-decoration-accept/tank_part_mesh_collision_probe-rerun.log` 與同目錄 `tank_part_geometry_smoke.log`。
- 取樣點驗證曾混用未蒙皮局部頂點與蒙皮後點；改為在同一世界座標域對照獨立原始蒙皮 reference。沒有改碰撞資源、放寬 `is_equal_approx`、變更 0.05m 門檻或縮減 390 條原射線。
- 明列未完：原 probe 整體仍 exit 1，Tank2／3／4 主要車身 whole／neutral 外輪廓仍超過 0.05m；不是本次簡化已完成就等於 Task 1 完成。不啟動 Task 2～6。

### 驅逐坦克車身子交付（2026-09-09）

- 使用者核可每部位上限由 8 調至 16；validator 與 baker 共用同一常數，16 接受／17 拒絕已獨立驗證。12 個表面點及 0.05m 有限輪廓門檻不變。
- Tank4 hull 由 1 個整體凸形改為 15 個離線分塊：中央車殼 2、兩侧外框各 2、三個結構蓋件各 1、兩側輪罩各 1、前後輪群共 4。c65 艙蓋、外框及所有輪組保留；不修改可見模型。
- 外框按其實際面板／凸緣約 0.08616m 的階差向內平移半階差（各約 0.04308m），作有限精度近似；分段採原車殼／外框台階。獨立原始 reference 不平移，原射線位置與判定門檻不改。
- 裝飾追加排除頂部細把手及細管：c04–11、c13–20、c22、c24–64，共 2048／9222 triangles；保留 7174 triangles。baker 與獨立 probe 使用相同明列清單，12 個表面點只從保留的原始結構取樣。
- 正式烘焙 exit 0：hull 15、整車 29 shapes。fresh-context 最終正式資源驗收：Tank4 原 96 對射線全部通過，最大誤差 0.043081m；四車 geometry smoke exit 0。renderer 為 Vulkan llvmpipe，不宣稱實體 GPU 效能結果。證據：`/tmp/lea173-t4-formal-bake.log`、`/tmp/lea173-t4-final-accept.K4S4Z1/tank4-formal-runtime.log`、同目錄 `geometry-smoke.log`。
- 與烘焙前資源的語意比對僅 hull 改變；炮管 8、履帶各 1、固定上層 4 均相同。Tank1–3 資源 SHA-256 不變，Tank4 原始 GLB 與 Git 基準一致；runtime 沒有增加烘焙或凸分解呼叫。證據：同驗收目錄 `semantic-compare.log`。
- 本節取代前節 Tank4 車身未達標的狀態；Tank2／Tank3 車身候選仍未正式整合，四車整體 probe 尚非全綠，Task 1 不標完成，不啟動 Task 2～6。

### 驅逐輪組重複碰撞移除（2026-09-09）

- 使用者檢視預覽後核可移除四個前後輪群凸形。獨立幾何包含檢查確認左右原始輪組各 8496 個點，以及每個輪群凸形的全部頂點，均包含於對應履帶凸形；最大超出量為 0。故移除不改變整車碰撞聯集，輪組不是改列裝飾。證據：`/tmp/lea173-wheel-coverage.IpdosX/wheel-track-coverage.log`。
- 正式 hull 由 15 減至 11，整車由 29 減至 25；僅移除最後四個重複形狀。前 11 個凸形／transform、12 個表面點及其他部位完全不變，原模型不變。舊資源備份：`/tmp/lea173-t4-before-wheel-removal.tres`。
- fresh-context 驗收正式 11 塊資源：Tank4 原 96 對射線 exit 0，最大誤差 0.043081m；四車 geometry smoke（含 shape index／同 Tank owner）exit 0；前後資源語意比對 exit 0。證據：`/tmp/lea173-t4-wheel-final.XtmtKw/tank4-96.log`、同目錄 `geometry-smoke.log`、`semantic.log`。7174／2048 結構參考及 0.05m 門檻不變。
- 前一版 15 塊正式資源完整 `node scripts/quality.mjs` 已 exit 0（`/tmp/lea173-t4-formal-quality.log`）；本次移除後重跑上述受影響的幾何、命中與輪廓驗收，未宣稱再跑一次完整 quality。
- 已重開四車預覽，驅逐標示 HULL 11／FIXED UPPER 4；截圖 `/tmp/lea173-t4-eleven-preview.png`。本節取代前節的 15／29 計數，其餘 Task 1 未完範圍不變。

### 重型裝飾欄杆移除與車身子交付（2026-09-09）

- 使用者看過重型 shape 11 的誤差定位預覽後，明確裁決 c09–12 四條欄杆為裝飾件：保留可見模型，碰撞與表面取樣排除。原始 4390 triangles／43 components 不變，總排除由 240 增為 840，保留 3550；此分類不是自動刪除其他結構。
- 正式整合重型分塊車身，移除候選中獨立欄杆凸形後為 15 shapes（整車 28）。保留下方裝甲、兩側翼板、輪罩及其他結構。翼板按原始面板折線分段；12 個表面點只從保留的原始結構取樣。
- 遮蔽內部接合穴的 reference 使用原始 c00 roof-rim 12 點建雙面封口，不使用正式 convex 作 reference。原 102 對射線、0.05m 門檻不變。
- 正式 bake exit 0：`/tmp/lea173-t3-formal-rail-bake.log`。fresh-context 最終正式驗收 PASS：102 對最大誤差 0.038925m；geometry smoke PASS；非 hull 與舊備份語意相等（gun 7、turret 4、履帶各 1），Tank1／2／4 資源 SHA-256 不變，Tank3 GLB 與 HEAD 相同。證據：`/tmp/lea173-rail-accept/formal-tank3-collision.log`、`formal-geometry-smoke.log`、`formal-semantic-compare.log`。
- 舊正式資源可由 `/tmp/lea173-t3-before-rail-removal.tres` 回復。已更新暫存預覽，截圖 `/tmp/lea173-tank3-rail-removed-preview.png`；未修改正式場景或可見模型。
- 本節取代重型車身未達標狀態。Tank2 候選仍只在暫存目錄通過，尚未正式整合；暫存四車 390 PASS 不代表正式四車全綠。Task 1 整體及 Task 2 轉動阻擋尚未完成。
- 正式重型更新後完整品質回歸 `node scripts/quality.mjs` exit 0，輸出 `Tank Skirmish quality gate passed.`；證據 `/tmp/lea173-t3-rail-quality.log`。

### 中型正式整合與四車輪廓回歸（2026-09-09）

- 中型 hull 正式採 12 塊：中央 c04 按原始結構 X=-0.793183207511902／2.12868547439575 分三塊，其餘核可構件分組保持不變；turret 以原始 Mesh.get_faces 的 11 個連通構件各一凸形。原始 4272 triangles／49 components、448 排除／3824 保留不變。僅重烘焙 Tank2，整車 30 shapes。
- 中型獨立 reference 沒有新增封口；先前從候選 convex debug mesh 取六面得到的 neutral PASS 不作有效來源證據，也未整合。正式結果對照原始保留結構，沒有提高 0.05m 門檻或縮減原矩陣。
- 正式四車 390 對射線通過：Tank1 90／0.000173m、Tank2 102／0.045663m、Tank3 102／0.038925m、Tank4 96／0.043081m；geometry smoke 通過。證據 `/tmp/lea173-task1-final-accept/mesh-probe.log`、`geometry-smoke.log`。
- 正式烘焙 `/tmp/lea173-t2-formal-bake.log` exit 0；完整 `node scripts/quality.mjs` exit 0，`Tank Skirmish quality gate passed.`，證據 `/tmp/lea173-task1-final-quality.log`。中型舊資源備份 `/tmp/lea173-t2-before-formal-integration.tres`。
- 使用者已核可順序為先正式整合中／重型，再做炮管碰牆轉動阻擋。隔離旋轉八項固定案例已由 fresh-context 重跑 PASS／exit 0：`/tmp/lea173-rotation-fresh.log`；此隔離證據不是正式四車 Task 2 驗收。Task 3–6 仍未開始。
- 最終 fresh-context 驗收總判定 PASS：390 對／geometry smoke／T2 語意比對各 exit 0，僅中型 hull／turret 改變，gun／履帶與備份相同；Tank1／3／4 SHA-256 精確不變、GLB diff count=0、runtime 無烘焙呼叫。額外證據 `/tmp/lea173-task1-final-accept/t2-semantic.log`。Task 1 部位幾何階段至此完成；本節取代上方各歷史停止點，並非 LEA-173 全單完成。
- 使用者於重型欄杆子交付後回覆「可以 繼續」，依既有核可順序開始 Task 2。封閉實作 packet 保存在 `/tmp/lea173-task2-closed-packet.md`；先在隔離快照接三個旋轉入口並做真車建築案例，尚未套用正式控制器。

## Task 2 正式整合與獨立驗收（取代前節尚未套用狀態）

- 已正式接入車身 yaw、砲塔 yaw、炮管 pitch 的候選姿態查詢守門；每步外緣弧長上限 0.02m、query margin 0.002m。只套用已接受的旋轉角度並回寫實際角速度，平移仍沿用 `move_and_slide`，不改控制數值、AI、導航、幾何資源或傷害。
- 新增 `tank_motion_guard.gd` 與三份測試：`tank_motion_guard_fixture.gd`、`tank_motion_guard_smoke.gd`、`tank_motion_guard_wall_smoke.gd`。三份新測試目前獨立執行；接入品質入口仍依原計畫留於 Task 6。
- 正式 fresh-context 驗收六測均 exit 0：8 個固定守門案例；四車 60Hz 空地／近牆／真接地／同幀三軸量測／另一車不受新增推力；既有建築四車 × 平移、車身偏航、砲塔旋轉、炮管俯仰 16/16 格阻擋及緊接反向退出；另有 geometry、aim spread、Tank1／Tank4 固定砲塔輔助回歸。日誌 `/tmp/lea173-task2-formal-fresh/`。
- 牆面矩陣每格確認起點無重疊、候選與實際姿態一致、純查詢終點會碰牆，再以正常公開控制推進與反向；重型砲塔使用合法 80°→90°、重型側向炮管 20°→0°、驅逐砲塔 -6°→0°。沒有放寬遊戲限角、碰撞門檻或削弱斷言。
- 完整既有品質回歸 `node scripts/quality.mjs` exit 0，最終輸出 `Tank Skirmish quality gate passed.`，證據 `/tmp/lea173-task2-formal-quality.log`；`git diff --check` 通過。獨立接線核對無 blocker，候選查詢先於節點寫入，受影響 shape 範圍與接觸刷新符合封閉 packet。
- Task 2 程式與自動化驗收至此完成；尚未宣稱人類試玩通過。Task 3～6 未開始，LEA-173 全單未完成；本階段未 commit、開 PR、merge 或更新 Linear 完成狀態。
