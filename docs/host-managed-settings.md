# Host-managed settings

Agent Team 的 implementer 不得自動修改 root、`.github/` 或 `.agent-team/`。這是安全邊界，不是缺少權限的暫時錯誤。

## Host 管理的檔案

- `project.godot`：主場景、renderer、viewport、autoload、InputMap、physics layer 與引擎 feature
- `.github/workflows/ci.yml`：CI 觸發條件、權限、Godot 安裝與 required job 名稱
- `.gitignore`、`.gitattributes`：repository-wide 行為
- `.agent-team/project.json`：Agent Team registration 產物

工單若確實需要變更上述內容，team lead 應停止自動實作並留下明確 blocker，交由 host 做單一、可審查的變更。不要把設定複製到其他位置假裝已完成。

## 可由 Agent Team 演進的內容

- `src/`：場景、GDScript、Resource、遊戲素材與 runtime 設定
- `tests/`：headless smoke 與結構驗證
- `scripts/`：CI 子程序、素材下載／轉換與本機圖形驗收工具
- `docs/`：設計、素材 provenance、授權快照與驗收說明

第一階段不使用第三方 addon。若未來確定採用必須位於 `addons/` 的工具，應先另做安全性與 admission policy 裁決，不在玩法工單內順手加入。
