# Toolchain Bootstrap Runbook

本文件記錄目前已由 `scripts/bootstrap-toolchain.mjs`、
`docs/toolchain-lock.json` 與 offline contract tests 證明的操作合約。它不
授權下載未鎖定的版本，也不取代 Team Lead 對 host proof 的裁決。

## 範圍與責任

受管理的 tool ID 僅有：

| Tool | 鎖定版本 | 用途 |
| --- | --- | --- |
| `godot` | 4.7.1 stable | CI 的 headless import、scene-load 與 smoke 驗證 |
| `blender` | 4.5.12 LTS | 僅 host conversion / rendering proof；CI 不安裝也不執行它 |

CI 只執行 offline tests，接著驗證並使用 workflow 選定的鎖定 Godot。
`bash scripts/ci.sh` 可用 `GODOT_BIN` 指向經驗證的 Godot；未指定時，會由
下述 default resolver 找到鎖定的 Godot。它不會下載 Godot 或 Blender。

只有 host proof 在確實需要 Blender 時才可執行 Blender 安裝。二進位檔、原始
archive、下載快取、暫存目錄與 `.godot/` 都不得加入 Git。

## CLI read-back 與日常操作

CLI 的權威 usage（由 `--help` 輸出）是：

```text
--help | --check-cache --tool <godot|blender> [--cache-dir <absolute-path>] | --install --tool <godot|blender> [--cache-dir <absolute-path>]
```

先以不使用網路的 cache 檢查確認目標是否合法：

```bash
node scripts/bootstrap-toolchain.mjs --check-cache --tool godot
node scripts/bootstrap-toolchain.mjs --check-cache --tool blender
```

成功會輸出一行 JSON，包含 `state: "cache_target_valid"` 與
`network: "unused"`。這只驗證 cache root 與最終 target，**不**代表工具已
安裝或可執行。

在已取得 host proof 授權後，才安裝所需的單一 tool：

```bash
node scripts/bootstrap-toolchain.mjs --install --tool godot
node scripts/bootstrap-toolchain.mjs --install --tool blender
```

可用 `--cache-dir "$CACHE_ROOT"` 做單次明確 override；`$CACHE_ROOT` 必須是
repo 外的絕對路徑。請勿把真實主機路徑貼進 issue、commit、公開 evidence 或本
repo。CLI 不接受同時指定兩種 mode、未知 tool、重複 flag 或相對 cache path；
這類 usage error 會以 exit 2 結束。

安裝成功的 JSON 會是 `state: "installed"`（網路使用）或
`state: "existing_valid"`（未使用網路），並回報已驗證的 archive／executable
摘要。cache 或安裝失敗會以去敏 JSON 錯誤結束（exit 3），不得把失敗改寫為成功。

## Cache resolver 與 repo containment

未使用 `--cache-dir` 時，resolver 依序採用：

1. `TANK_SKIRMISH_TOOL_CACHE`；
2. `XDG_CACHE_HOME` 下的 `tank-skirmish/toolchains`；
3. host 預設 cache home 下相同的 `tank-skirmish/toolchains` 子路徑。

每一種來源都必須是絕對目錄。resolver 會解析既有祖先與 symlink；任何指向 repo
本身或 repo 子樹的 root／target、相對路徑、壞 symlink 或非目錄都 fail-closed。
它不透過 Git 猜測 cache 位置。各 tool 的目標再由 lock manifest 的
`cacheRelativePath` 推導，且不得跳出已驗證的 cache root。

## 安裝交易與完整性驗證

所有下載資訊都以 `docs/toolchain-lock.json` 為準：來源 URL、archive 大小、
archive digest、archive layout、executable SHA-256 與版本合約均是 pinned。
工具不接受「下載成功但 checksum 不同」或「可執行檔存在但版本不同」作為成功。

下載與 publish 依下列順序進行：

1. 在 cache root 的私有 UUID staging transaction 建立 download 與 tree；archive
   以私有權限建立。
2. 串流下載時同時驗證精確大小與 lock 所列 digest，並以 archive adapter 檢查格式、
   成員與可接受 entry type 後才解壓。
3. 驗證 staged executable 的 SHA-256 與版本合約，才可 publish。
4. 只在 staging tree 與 destination parent 同一 filesystem、destination 不存在時，
   以 rename 發布；跨 filesystem、已存在 destination 或 publish 錯誤一律停止。
5. transaction 結束時只清除本次 UUID staging 目錄；不碰其他 transaction。

已存在的 destination 不會被覆寫。安裝前與取得 tool lock 後都會重新驗證既有
executable；通過就回傳 `existing_valid` 且不使用網路。既有目錄、digest、版本或
可執行檔驗證任一不符，即以 `install_invalid` 或安裝失敗停下，不進行覆寫式修復。

### Vendor redirect 規則

預設不跟隨 redirect。唯一例外是 Godot 的首次回應為 302、303、307 或 308 時，
可跟隨**一次**已鎖定型態的 HTTPS GitHub release-assets CDN URL：不得含帳密、
非預設 port 或 fragment，host 必須是預期 CDN，path 必須是預期 release-asset
前綴。第二跳必須直接得到 200；第二次 redirect 或不符目的地都停止。Blender 的
redirect 一律拒絕。

## Lock 與 fail-closed 停止條件

每個 tool 使用 cache root 下獨立的 `.locks/<tool-id>` 目錄鎖。競爭者最多等待
30 秒（每 250ms 輪詢）；逾時回傳 `lock_timeout`，不下載、不發布，也不刪除既有
lock。

**stale、未知 owner 或 metadata 不可信的 lock 一律視為 fail-closed。**自動流程
不得判斷它「應已過期」而刪除它。唯一會由流程移除的 lock，是本次流程成功建立、
且 release 時 metadata 與自己建立的內容完全相同的 lock。

人工復原前，操作者必須先向 Team Lead 提交下列資料並等待裁決；未裁決前不得刪
lock 或重試安裝：

1. exact lock path；
2. `metadata.json` 的完整 metadata（如 `createdAt`、`token` 或未知 owner 欄位）；
3. 與該 tool／cache root 相關的完整 process 清單與 PID（僅盤點，不終止 process）；
4. 為何判定它需要人工處理，以及是否仍可能有安裝 transaction 在執行。

同樣 fail-closed 的情況包括 cache containment／I/O 問題、非預期網路回應或
redirect、archive size 或 digest 不符、不安全 archive entry、staging 不符交易
形狀、executable digest／版本不符、destination race、跨 filesystem publish，及
任何未被明確驗證的錯誤。停止後保留去敏 evidence，交由 Team Lead 判斷下一步。

## CI 與 host proof 的分界

CI 入口是：

```bash
bash scripts/ci.sh
```

它會執行 toolchain lock、archive 與 bootstrap 的 offline tests，然後以 workflow
Godot 執行 `--version`、headless import 與 smoke。CI 也會驗證 Godot executable
digest 與版本合約，並掃描 `ERROR:`／`SCRIPT ERROR:`；任一項出現即失敗。CI 不做
live download、不安裝 Blender、不重跑 Blender conversion，也不以 headless 截圖
替代 host 視覺 proof。

Team Lead 在將工作標為 Ready 前，必須 read-back default resolver 可供 CI 使用的
Godot，或明確提供已驗證的 `GODOT_BIN` workflow override；做不到時，本單不得
Ready。需要 Blender 的 host proof 應在具圖形 driver／WSLg 的受控環境另行執行，
並將結果依既有素材與視覺驗收流程交由 leadi 裁決。

## 去敏 evidence 範本

可在 issue 或交接紀錄中使用以下格式；方括號的值為描述性值，不是本機路徑：

```text
time: [UTC timestamp]
command class: [check-cache | install | CI | host-proof]
tool: [godot | blender | none]
cache source: [default resolver | explicit override]
cache path: [REDACTED]
result: [exit code] [cache_target_valid | existing_valid | installed | failure code]
network: [unused | used | not applicable]
lock: [none | exact path supplied privately to Team Lead]
verification: [pinned archive digest / executable digest / version contract / CI checks]
artifacts committed: none
```

提交前必須移除：本機絕對 home/cache path、使用者名稱、私有目錄結構、signed redirect
query、archive 的暫存位置、完整 lock token，以及任何可能識別 host 的 process
command line。若 Team Lead 為人工 lock 復原而需要 exact path、metadata 或 PID，
這些內容只能在私下的裁決資料提供，不能寫入 public repo 或一般 evidence。

## 最小 read-back 清單

完成操作紀錄前確認：

- `node scripts/bootstrap-toolchain.mjs --help` 的 usage 與本文件一致；
- 兩個 tool 的 `--check-cache` 均可用於離線 target 檢查；
- 只有已授權的 host proof 使用 `--install`，且只安裝當下必要的 tool；
- cache 在 repo 外，沒有 binary、archive、cache 或 staging 被加入 Git；
- stale／unknown lock 沒有被自動刪除；
- `bash scripts/ci.sh` exit 0，且其使用的 Godot 已通過 lock digest 與版本驗證。
