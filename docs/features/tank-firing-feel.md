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
