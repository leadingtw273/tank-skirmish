# LEA-134 發射手感續調（2026-10-07）

本輪讓四款正式剛體車開砲時有可見砲管退縮與共同車體反作用，玩家鏡頭 kick 從 0.5m 降到 0.2m。分支 `feat/lea134-firing-feel-adjustment`，基線為 PR #128 已合併的 main `679decd21d6d3a2b38e237330cd995ebe320a8cb`／tree `c912a8afe76ade1d0551335614b82bdf6b7384ec`。原透視工程與人驗 accepted 已閉包；本輪手感人驗 pending。

## 裁決與授權

沿 [LEA-134](https://linear.app/leadingtw273/issue/LEA-134) 的新輪，關聯已完成的 [LEA-148](https://linear.app/leadingtw273/issue/LEA-148)；保留 134 舊正文與歷史，不復活取消的 LEA-151。砲管動畫與降低鏡頭是本輪明示延伸。

leadi 選「加強視覺後座，保留原本移動與瞄準規則」及「降到約40%，保留短促回饋」；2026-10-07 授權正常合併／複審，並補充「提前核可第二模型相關複審操作，直接做到讓我可以實測手感」。符合原 gate 的正常開發與 review 可續行，優先交付本機試玩候選。平台必要檢查與私素材邊界保持。

指定 Short `https://www.youtube.com/shorts/JP9b5E_G-QY` 的 26–28 秒右上藍車未取得影格，cookie-free 取證遇 429／bot gate 後停止；不能宣稱看過、量測或精確復刻。Gemini 影片第二意見缺席；依文字目標與本機可觀測動作驗收。

## ADR 與參數

「機械姿態」為真剛體、離線部位幾何、VisualRecoilPivot／TurretPivot／GunPitchPivot／MuzzlePoint 與原瞄準、碰撞、ShotEvent 權威。「可見反作用」僅動畫 HullVisual、TurretVisual、GunVisual 三根，使用同一世界反作用繞當下 stable_world_center，回推各自當下 parent pose；GunVisual 再沿當下機械射向退縮。世界公尺不受匯入 scale 影響。

hull 機械 anchor 查詢先移除本輪 HullVisual render 變換，再沿原 legacy 剝離；其他機械 pivots／marker 不動畫。成功 fire 凍結原事件並發出原通知後才觸發；cooldown 不觸發，新 fire 取代舊反應，回快取 rest，死亡／換車／退出清理。正式 rigid 不復活舊整車 Tween；非 rigid 原相容路徑保持。

| 行為 | 幅度 | 峰值／回正 |
| --- | --- | --- |
| 砲管退縮 | 0.45m | 0.04s ease-out／0.24s 平順回正 |
| 三根共同位移／後仰 | 0.22m／1.4°；水平射向端抬起 | 0.05s／0.28s |
| 玩家鏡頭 | 0.2m（原 40%） | 原 0.2s 平方衰減、零 roll |

四車共用初值，Inspector「剛體坦克開砲視覺反作用」可調與停用 A/B；鏡頭在共用 GameplayRuntime CameraRig。原 impulse、mass、移動、瞄準、碰撞、散布、冷卻、彈速、傷害、AI、地圖、光照、視野、素材、特效生成點與真懸吊皆不改。

## 固定 AC 與驗證

| AC | 有限可判定結果 |
| --- | --- |
| F1 | 四車有效 fire 保留原單彈／事件與一次可見反應；cooldown 不重啟。砲管相對砲塔退縮，車體正確反向位移／抬起；重觸有界、回 rest 無漂移。 |
| F2 | 固定同當下真姿態，在 0.04s 砲管峰值、0.05s 車體峰值及 0.16s 回正中段 A/B；機械 world muzzle／方向、全部 part shapes、瞄準結果、ShotEvent、impulse 次數／設定相同。機械 pivots 不動畫。 |
| F3 | 真主圖／訓練場玩家 kick 0.2m，0.1s 為 0.05m，0.2s identity；敵車不晃玩家。原 Camera3D、跟隨、前視、zoom 保持。 |
| F4 | 四車固定／轉動砲塔、靜止／行駛、正前／側向隨真 pose 更新；換車、死亡、重生／復原、退出清理舊反應。真可見透視幾何、灰殘骸與煙保持。 |
| F5 | 有限測試、既有 smoke、完整 quality／diff-check 真通過；最新 HEAD 非作者 fresh-context 驗收／獨立來源 review。235 原 UID 與 586 ignored 私素材 metadata 保持、不提交／外送；手感人驗另列。 |

新直接入口 `res://tests/firing_visual_recoil_smoke.gd`（pinned Godot 4.7.1、headless、固定 60fps）包含四車三方向峰值 A/B、worldmeters、冷卻／重觸／死亡／自然 render 回正，以及兩個真場景鏡頭。有限基線紅燈 actual exit 1／ERROR 0，9 個直接需求缺口；候選新 core actual exit 0／ERROR 0。

既有 rigid integration、四車 runtime／aim、part geometry、smoke、aim cursor、combat boundary、六個透視入口（tank／enemy occlusion、partial visibility／combat、enemy combat、aim cursor）及 documentation exports／region wreck cleanup 均作者 actual exit 0／ERROR 0；diff-check 通過。這些不是非作者圖形 A/B、獨立來源 review、完整 quality 或人的 accepted。完整入口仍為 `GODOT_BIN=<pinned 4.7.1> bash scripts/ci.sh`。

## 試玩與保留邊界

候選先由非作者按 F1–F4 做同 HEAD 真 viewport A/B 與來源 review，再由 root 依既有 guarded FF 正常交付 Windows 主圖 F5／訓練場 F6 試玩。最新版本、實際 quality／平台 gate 與人驗結果在交付時讀回，不預填 PASS。

586 私素材只依既有 lock 清單作本機 ignored 輸入，235 原 UID metadata 保持；來源普通 PR／合併依已核可輪次與真實 gate，不 bypass。新 Head 網路私 CI 仍需 exact PR／Head／run／attempt 授權，PR #128 grant 已耗用，不能冒用；網路私 CI 不是本機 preview 的前置。未授權外送素材／截圖、公開發行或修改 protected settings、project.godot、workflow、asset lock。


## 2026-10-08 首發 FX 同步預初始化

leadi 回覆「可」，核可進場時先初始化發射特效，並比較真首發與後三發。本輪沿 LEA-134、分支 `fix/lea134-firing-fx-prewarm`，基線 `acdedad63df538256b18d79e799aa43fd48e5117`／tree `f971f91b16edc28d256b3e9ff5d202cdb29cba92`。sealed plan SHA-256 `8a65f598397faebbb0cd50d45bcba38c79c13e66925638db78229096109c2a27` 經原生隔離計畫審查 approve／0 blocker；跨模型外部審查曾被平台拒絕，未重試或外送來源、素材。原開砲手感與建築過渡的人驗 accepted 保留，本輪首發改善人驗 pending。

CombatRuntime 在 ready 容器檢查後、註冊 shot source 前同步建立一次純 flash、smoke、javelin VFX、impact wrapper。暫時父節點與四個 wrapper 進樹前即隱藏；controller 設 one_shot／停用 autoplay 後同步初始化、播放並立即 free。smoke 使用本次複製的 process material，impact 沿既有 scale helper；沒有真正戰鬥 Projectile、射擊／命中 handler、計時器或延至玩家可操作影格的節點。正常換車只重新接線；每發仍用原材質複製、尺寸、restart／play 與清理，砲管 0.45m、車體 0.22m、鏡頭 0.2m 與原 duration 保持。

本選項只提前部分 CPU 首用工作。隱藏 FX 未繪製，不能宣稱 GPU draw pipeline 全部預熱、首發尖峰消失，亦不能以 headless／fixed-fps 當性能證據；不新增 await 屏障、輸入／AI gate、loading UI、SubViewport、pool、logger 或磁碟／引擎 cache 管理。

| AC | 本輪有限判定 |
| --- | --- |
| A1 | ready 不發 shot／impact，不改 HP、cooldown、pending physics、recoil、camera，不生成真 Projectile；預初始化全程不可見、無聲，無 FX／燈／decal／timer 殘留。 |
| A2 | 每 CombatRuntime 一次；四車共用四種 FX，換車不重做，主圖／訓練場原組裝與 source 接線保持。 |
| A3 | 正式每發的原 call、material、scale、restart／play、傷害／瞄準／impulse／cooldown 與 0.45／0.22／0.2 保持。 |
| A4 | 同 Windows 原生 GPU／renderer／viewport／helper 下，一首發與三暖發全部有效；記 startup、同步與逐 frame wall time、pipeline counters、impact 時序及原 FX。 |
| A5 | 分開報同步成本與 render 尖峰；若未改善或只有部分改善如實記錄，不盲加架構或測量矩陣。 |
| A6 | M／N2／N1／old、既有 refs、236 UID、586 ignored 私素材 metadata 與原 Windows userdata 保持；只提交明列 source／測試／文件。 |
| A7 | 最新封存 HEAD 非作者 fresh-context 來源與相關實跑驗收；無 blocker 後由 root guarded 正常 FF 至 M，供 Windows F6 人驗。 |

直接作者入口為 pinned Godot 4.7.1 的 `--headless --path <repo> --script res://tests/combat_boundary_smoke.gd`；擴充既有 smoke 觀察四個不可見 wrapper、同步釋放與 ready 前後 HP／cooldown／pending／recoil／muzzle／camera、shot／impact，以及 source 重新註冊不重做。另跑既有 firing visual recoil、combat／projectile 相關有限入口與 source／diff-check；作者四入口 `combat_boundary_smoke`、`firing_visual_recoil_smoke`、`smoke`、`enemy_combat_smoke` 均 actual exit 0／ERROR 0，完整 CI 未執行。`smoke` 留 WARN 1，來自既有 camera invalid ShotEvent fixture 的非有限 Vector3；其餘 WARN 0。新 combat assertions 套 exact 基線 production 出現 actual exit 1／ERROR 1 的四 wrapper 缺口，候選還原後通過。首次候選缺 road PNG import mapping 的 raw exit 0／ERROR 297 不算 PASS；只在自有工作樹 import 一次後修正，import 本身 raw exit 0／ERROR 4 為受限 sandbox editor TCP listener，完整 log 保留。

Windows 原生量測與 fresh-context 驗收尚 pending；後續同 HEAD 封存 artifact、Linear 真實讀回是結果權威，不將作者自驗稱獨立 PASS。交付後 Godot 開 `project.godot`，主圖 F5、`res://src/maps/training_ground/training_ground_playtest.tscn` F6；先看啟動無特效，再實際一首發＋三暖發，觀察四車正常 FX、手感與 startup 成本。尚未 guarded FF 前，正式 M 保持基線。私素材不提交／外送，新網路 CI、push／PR／merge 仍依各自真實授權及平台 gate。

作者保全讀回：原 M／N2／N1／old 的 HEAD／tree／source／status／refs／原 caches 與 Windows userdata 未改；候選 236 原 UID、586 私素材的 bytes／mode／uid／gid／mtime 與原輸入一致，沒有新增 generated UID。作者 logs／checks／guards 留於本機 `agent-team/tmp/tank-firing-prewarm-20261008/writer/`；這是作者有限證據，不能替代 A4／A5 性能或 A7 fresh 驗收。
