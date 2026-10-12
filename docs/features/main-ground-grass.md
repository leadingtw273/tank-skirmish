# 2026-10-12 LEA-209 相機地面草串流

leadi 已肯定出生草樣式並核可相機可見地面＋外圍緩衝、16m 區塊、近密遠疏與固定位置。本輪由 `0fde8832717d3639567d430e9d1a407ffbe85cae` 沿同票實作；新視野功能的人員驗收仍 pending。

保留原出生 15,000 候選／11,820 株、seed117、Quad0.4×0.4／subdiv2、四形 atlas、Smooth alpha、wind(0.6,0.3) 及原材質。串流跳過出生 Rect2(-116,-115,25,24)，以全域0.2m整數格與固定hash生成抖動及atlas0–3；0.4／0.8m為同格子集。原 vendor shader／PNG bytes 不修改，新增自有 `stream_grass.gdshader`（UID `uid://c7uxgao5c2vxd`）僅增加穩定atlas及分層淡入／距離過渡；原240 UID 保持。

相機四角射線落於 y=0 的 convex polygon，32m外擴挑真相交16m區塊；bbox僅預篩。focus跨16m、zoom跨4m桶或視窗／basis變動才更新desired，儲存以focus格中心計算。近48m完整0.2m、48→64m平滑降為0.4m；可見polygon邊緣±8m再降為0.8m。dense預載至80m、mid預載可見外24m；草形／位置在返區與升密度時不變，新補株約0.35秒淡入，既有株保留epoch。

道路／建築原世界凸包外擴1m一次建立、16m bucket篩選，無per-grass physics。active≤400、cached≤64、出生＋active＋cached＋pending實存總株數≤750,000，超限先淘汰cache；過期job取消。每frame候選deadline2ms／最多2048候選，最多1次MultiMesh upload／6400株；upload及整frame實測另列，2ms不宣稱涵蓋不可中斷upload。base／mid區只訪問400／1600個對應子集候選。

既有 Ground/Visual 套同noise／palette／light配對底材，移除小SpawnGroundPatch，無新增重疊平面、地形或碰撞。原floor幾何、道路／建築材質、玩法／射擊／AI／透視／相機控制／照明保持；原586私素材與ignored CC0 atlas保持，沒有外送素材、PNG或source。

作者本機圖形／路徑／效能與兩原smoke證據在 `agent-team/tmp/tank-grass-stream-20261012/`；完整原始結果見 N9/candidate/final-benchmark.json、native-final.log 與兩smoke raw。作者證據不代替 fresh-context 或 leadi 人验；本輪不push／PR／網路CI／關票，正式目錄FF由root獨立验收後處理。

作者 exactsource 有限證據：WinGodot4.7.1／Forward+／RTX5090，1920×1080、關VSync且同相機／保留遮蔽視覺更新。最大視角stream steady frame median/p95/max=2.851/3.755/4.227ms；同版birth-only=1.958/2.887/3.109、off=1.639/2.103/2.453；原出生baseline=1.5195/1.980/2.304。8m/s固定相機路徑=3.984/6.380/8.530ms，候選CPUwork p95/max=2.001/2.013ms、upload=.595/3.136ms；frame為實際wall間隔，不當GPU獨立測量。

F1共922frame補齊5.805s（含startup首frame1.594s）、外區3.884s、返區4.150s，steady排除startup與截圖I/O。近區／外區／返區佇列均歸零；peak749809株、active275／cache64、候選peak1962／upload1；出生11820、stream出生重複／外界／排除反例均0。唯一效率校準僅將base/mid候選訪問6400改400/1600，位置／atlas不變；初輪raw保留。新point的epoch在publish寫入，旧point保留每cell實際epoch。

兩原smoke `main_ground_visual_smoke.gd`／`map960_components_smoke.gd` actual exit0；原floor AABB／collider對齊與三点ray保持、無camera只生出生草。F1/F4/移动/缩放/外區/返區真圖、16frame跨focus格GIF及runtime rows在上述N9/candidate；camera transform／size與N9/baseline相同讀回true。圖形run runtime ERROR0／WARNING0，退出同baseline RID清理2 ERROR／1 WARNING另列；作者證據不代替fresh及新視野功能人驗。原生第二模型plan APPROVE／0 blocker，缺Claude/Gemini外送第二意見如實保留。

以下為前輪歷史，不能代替新版結果。

---

# 2026-10-09 LEA-209 出生庭院草場續修

leadi 新裁決：全地圖大量生成有效能問題；先只鋪主世界坦克出生的空地，草須自然綿延交接。沿同票修正，尚待本機獨立工程驗收與 leadi 實測，不沿用前版人驗或 CI 結果。

本版固定 `Rect2(-116,-115,25,24)`，實車出生 `(-108,0,-106)`；0.2m 格距、±0.08m 抖動、seed117，15,000 候選經既有道路／建築世界 XZ 凸包外擴1m排除。一次性單一 MultiMesh，移除全地圖底草、視野細節tile與每幀生成。Quad 0.4×0.4m、subdiv2/2、centerY0.2，原四形atlas／billboard及平滑alpha，wind(0.6,0.3)。出生patch的無碰撞PlaneMesh與草葉共用同noise／palette／原demo受光算法；其餘floor材質保持。

免費原source atlas只是新增一個ignored本機CC0輸入，原586私素材與239原UID保持；shader/PNG來源不修改，atlas不Git／不外送。正常來源分支 `feat/lea209-spawn-grass`，基線 `3e88ec173e30b452df43749230ad4aba2c2148b4`。本輪不push、PR、網路CI或關票；本機FF由獨立驗收後交付處理。

作者同source有限證據：WinGodot4.7.1／Forward+，15,000候選、11,820株、單一MultiMesh、生成7ms；草根出界0／獨立凸包重建排除反例0、無每幀process，共用noise／palette讀回true。F1／F4與32幀2.56秒wind已實拍，兩原smoke actual exit0且無ERROR/WARN；圖形runtime的WASAPI與退出RID清理訊息與基線相同。此為作者證據，獨立驗收與leadi人驗仍pending。

以下前版記錄保留作歷史，不當作本版PASS。

---

# 主地圖空地草皮（LEA-209）

leadi 要求主地圖建築與道路間的小空地，以及建築群外露地面補草地，並於 2026-10-08 選定「偏自然的灰綠草地（建議）」。工單為 [LEA-209](https://linear.app/leadingtw273/issue/LEA-209/主地圖建築道路間與街區外空地補草皮)，人驗 pending。

## 2026-10-09 demo 密草與風動續輪

leadi 提供兩段 BinbunGrass demo，要求接近連續密草與成片風動。本輪從本機 `cc21ff8` 的隔離 W／`feat/lea209-grass-demo` 續修；封存計畫 SHA-256 `d872296f3f79bfd31431ea526cadae9faedabd71a1310291d686b82c9ac7b314` 經原生隔離 plan review approve／0 blocker，root 明確 GO。沒有 Claude／Gemini 外送或可確認的跨模型結果。

原 1920m floor、403320 株／225 個 128m 底草 chunks、388 個道路／建築 world-XZ 凸包外擴 1m 排除與 seed 保持。相機中心射線落地點附近另有 32m／0.5m 格距、jitter±0.2m、Quad0.8×1.0m 的 9×9 detail tiles；最多81 tiles／331776候選，每幀1024候選且最多一次4096株buffer提交，跨32m才調整有界佇列、優先中心、離區釋放與取消過期工作。根部保持1m floor inset，無相機的直接地圖 smoke 只留底草。初始化允許分批補齊，沒有碰撞／踩壓、每株節點或玩法變更。

自有材質使用原來源 shader 的 wind_velocity=(1.2,0.6)，獨立256px seamless wind noise／FastNoiseLite frequency0.08；灰綠palette為(0.25,0.34,0.20)至(0.40,0.48,0.30)，alpha_mode2與原shape保持。Base／detail保守bounds含風位移；PNG、來源 shader、UID、scene、相機、光照、道路／建築素材保持。

本機作者有限證據保存在 `agent-team/tmp/tank-grass-demo-20261009/`：同正式相機F1/F2/F4、外區(400,400)、四個秒級風動PNG、真render連續風GIF、移動frame／batch成本、返回buffer一致與全detail根排除／inset讀回。首輪fixture提前等待及次輪DONE字串format ERROR原raw保留；修正只在本機驗證fixture，不改AC或玩法。最新兩原smoke、renderer runtime／既有2ERROR+1WARN shutdown分類以本輪actual receipts為準。這是作者有限工程證據，沒有完整gameplay／跨硬體性能承諾、GitHub／CI／關單或本輪人驗accepted；fresh與root guarded本機交付另讀回。


## 本輪 BinbunGrass 草株

leadi 明確指定使用 BinbunGrass；本輪基於已本機交付的灰綠草底 `07249fea5327c5efb05b0ea868d0f16ce626dcea`，隔離分支 `feat/lea209-binbun-grass`。v2 計畫與有限外觀校準均經平台原生第二模型 approve／0 blocker，依 root 明確 GO 實作，最新候選仍待 fresh-context 與 leadi 親測。

主圖 GrassField 引用自有 `main_grass_field.gd`／`binbun_grass_material.tres`，真實使用既有 `assets/BinbunGrass/texture/grass_basic_02.png` 與 `assets/BinbunGrass/shader/grass.gdshader`，原素材與 shader bytes 保持。自有 palette 產生草叢間低飽和灰綠色差；billboard 開啟、atlas 關閉、random_variation=0、wind_velocity=(0,0)、alpha_mode=2、cast_shadow 關閉。保留原灰綠不透明草底；草株使用來源 shader 的 alpha 行為。

全圖 ±960m 以 3m 全域格一次生成，最多 409600 候選，再歸入 128m／最多 225 個 MultiMesh。固定 seed117；內格各軸 jitter±1.4m，每軸首末格仍±0.5m，根部距地圖邊緣至少 1m。Quad 為 0.6×0.9m、center_offset.y=0.45m、根部 y=0.01m，維持來源 2:3 比例。道路與建築 Mesh local AABB 八角經完整 world transform 投影為 XZ 凸包後外擴 1m；AABB 僅作 chunk／點預篩。沒有逐幀生成、每株節點或新增 collision。

最終作者原生 Godot 4.7.1／Vulkan Forward+ 真實生成 403320 株、225 chunks、388 排除 footprints，單次啟動生成 255ms（不是 FPS 效能承諾）。07249 草底 baseline 與最終草株四視角使用相同相機：F1／F2／F3 沿下方歷史設定，F4 為 F1 相同 basis／位置、size25 近景。四圖 actual exit0、runtime ERROR0／WARNING0；退出後同 baseline 的 2 ERROR／1 WARNING renderer cleanup 訊息完整保留。原 `main_ground_visual_smoke.gd` 與 `map960_components_smoke.gd` 最終同版 actual exit0／ERROR0／WARNING0；後者僅歷史元件回歸。

本機驗證入口為 `tank-main-grass-20261008/binbun-{baseline,final}` 的原 PNG、raw log 與 receipts；初輪點陣圖保留於 `binbun-candidate`。正式相機／環境、Ground geometry、道路／建築、導航、射擊／移動與原 238 UID 保持；唯一新增 script UID `uid://coqwynwbywgp7`。獨立驗收與 guarded 本機交付由 root 接續；道路／台階入口與車體在作者圖可辨，遠景草葉縮放觀感與整體自然感仍待 leadi 親測，沒有新增完整 quality／效能矩陣。

以下保留上一輪平面草底證據。

基線為已合併 PR #129 的 `main 590c80177125bd8f86acc273954d5f3d4b1d9d2d`，tree `1519636493b8e5a16d4cb13aa652a9f943f4131d`。本輪計畫 SHA-256 `23f12db1f907d7ec30f95bce28258f409c2a43678ac656c14eb0756f85c1220b` 的平台原生隔離第二模型審查 approve／0 blocker；Claude 外送審查被平台拒絕，沒有有效 Claude 結果，不重試外送。

## 平面草底歷史：有限實作與保持條件

GroundMaterial 改用專案自有不透明 `ground_grass.gdshader`。兩個灰綠色與 `patch_size_meters` 可在 Inspector 調整；預設 12m 主斑駁與其 3 倍頻率的柔和細色差。座標取 `MODEL_MATRIX` 轉換後的世界 XZ，色差固定於地面，保留一般 PBR 受光／陰影與 roughness 0.92。

Ground 尺寸／transform／collider、200 道路、170 建築、Navigation、坦克遮蔽與射擊／移動、正式相機及 Environment 原 source 資料保持。這是平面草皮，不新增草株、風動、透明 pass 或地形位移，也不改既有私有素材。新增 shader companion UID 為 Godot 生成的 `uid://cb2d0xawr4aql`；237 原 UID bytes／metadata 與 586 ignored 私素材 metadata、原快取與正式來源保持。

## 平面草底歷史：固定驗收點

| 視角 | 驗證相機 | 檢查 |
| --- | --- | --- |
| F1 出生街區 | rig XZ=(-108,-114)，原斜俯視、size100、1920×1080 | 出生旁小空地草底，道路、人行道與入口可辨識。 |
| F2 中央街區 | rig XZ=(0,0)，原斜俯視、size100、1920×1080 | 中央建築與道路間草底，原建築淡出後仍有完整底面。 |
| F3 全街區 | (0,320,0.01)，正交俯視、size320、1500×1200 | 建築群外露地面草底，原路網輪廓與入口空間可辨識。 |

固定相機僅位於本機驗證 fixture，正式相機未改。用 Godot 開啟本輪工程交付的 `project.godot`，F5／`res://src/main.tscn` 即可親測；配色與自然場地觀感仍待 leadi。

## 平面草底歷史：作者有限證據與限制

Windows 原生 Godot 4.7.1、Vulkan Forward+／RTX 5090 的 baseline／candidate 同視角三張 PNG 均保存成功，兩段 CLI actual exit 0；擷取 runtime ERROR0／WARNING0。兩段在 `GRASS_CAPTURE_DONE` 後均出現同樣 2 ERROR／1 WARNING 的 Texture RID leak／ImageTexture renderer shutdown 訊息，raw 留存，不稱整份 log 無錯誤。

原 `res://tests/main_ground_visual_smoke.gd` actual exit 0／ERROR0／WARNING0，visible／collision AABB 對齊且三點 ground ray 命中 y=0。原 `res://tests/map960_components_smoke.gd` actual exit 0／ERROR0／WARNING0，僅為歷史元件回歸。主 scene 去除唯一 Ground 材質區與新增 resource 引用後，基線／候選 bytes 一致；其他原產品 source bytes 保持。

作者本機證據存於本輪 `tank-main-grass-20261008/{baseline,candidate,preparation}`，含實際命令／退出碼、renderer／相機 receipt、PNG SHA-256、原 UID／素材／快取守衛與 scene 不變式。初輪新增 UID 尚未進入 copied cache 的 text-path fallback WARNING 已保留；最終沿原 sky 的 path-only resource 引用，新增 companion UID 保留，最新 runtime WARNING0。

作者自驗不代替 fresh-context 驗收。本輪沒有執行完整 75 命令 quality／新網路私素材 CI、PR、push、合併正式來源或外送 PNG／素材；候選獨立審查與正式本機交付由 root 後續核對，人驗仍 pending。
