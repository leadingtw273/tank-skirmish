# Tank Skirmish

一款以 Godot 4.7 製作的固定斜俯視單人坦克遭遇戰遊戲。

目前只進行第一階段：建立不可操作的沙漠邊境小鎮靜態場景，以驗證素材、比例、道路配置、正交鏡頭與自動化管線。玩法、AI、HUD、音效及匯出包均不在本階段範圍內。

## 專案配置

- `src/`：Godot 場景、GDScript 與實際使用的遊戲素材
- `tests/`：Godot headless smoke／結構驗證
- `scripts/`：CI、素材轉換與本機自動化工具
- `docs/`：設計、素材來源、授權與驗收文件
- `artifacts/`：本機或 CI 產出的驗收證據（不進版控）

引擎固定為 Godot `4.7.1-stable`。CI 只做 headless import、scene-load 與結構驗證；正式 1920×1080 畫面由具圖形驅動的 WSLg 本機自動化產出。

## 本機快速驗證

```bash
GODOT_BIN=/path/to/Godot_v4.7.1-stable_linux.x86_64 bash scripts/ci.sh
```

Agent Team 可自動修改 `docs/`、`scripts/`、`src/` 與 `tests/`。Root 設定、`.github/` 與 `.agent-team/` 是 host-managed protected regions；需要變更時必須升級給 host 處理。
