# Host-managed settings

現役管理使用 [AgentCollab 入口](../AGENTS.md)。代理不得在未明確核可的工作中自行修改 root、`.github/` 或 `.agent-team/`；受控設定與素材／CI 安全邊界仍有效。2026-10-05 管理切換的明確例外只涵蓋八個管理入口與必要管理說明，見 [本輪授權](agent-collab/ITERATION.md)。

## Host 管理的檔案

- `project.godot`：主場景、renderer、viewport、autoload、InputMap、physics layer 與引擎 feature
- `.github/workflows/ci.yml`：CI 觸發條件、權限、Godot 安裝與 required job 名稱
- `.gitignore`、`.gitattributes`：repository-wide 行為
- `.agent-team/project.json`：保留的 legacy Agent Team registration 產物，不是現役管理授權來源

工單若確實需要變更上述設定，主代理先核對本輪是否明確授權；未涵蓋時留下具體缺口並由有權限的設定負責人裁決。已核可的單一、可審查變更可依本輪自主續行，不逐 Task 重問；禁止改寫 CI gate、挪用私有素材授權或複製設定到其他位置假裝完成。

## 可在已核可輪次內演進的內容

- `src/`：場景、GDScript、Resource、遊戲素材與 runtime 設定
- `tests/`：headless smoke 與結構驗證
- `scripts/`：CI 子程序、素材下載／轉換與本機圖形驗收工具
- `docs/`：設計、素材 provenance、授權快照與驗收說明

第一階段不使用第三方 addon。若未來確定採用必須位於 `addons/` 的工具，應先另做安全性與 admission policy 裁決，不在玩法工單內順手加入。
