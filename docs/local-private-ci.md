# 本機素材 CI 操作交接

道路／建築的 586 個本機資源由 `docs/assets/local-ci-assets-lock.json` 固定路徑、大小、SHA 及 archive SHA。素材不進 Git，也不使用 GitHub artifact 或 cache 保存。GitHub `quality` 保留完整原測試與錯誤掃描，另外執行本機素材／runner 合約測試。

## 準備本機輸入

需要 Linux x86_64、Docker、Python 3、可操作此 repo Actions runner 的 `gh` 登入，以及持有授權的素材 archive。固定 archive 放在 repo 外：

```text
~/.cache/tank-skirmish/local-ci-assets/quarter.tar
SHA-256 7490a4277e526600951c0ea7a6e32027825c3c51e6c81bba83761944167a3847
```

這是原始封存 archive；任意重新打包會改變 tar metadata 與 archive SHA，不能把新 tar 當同一版輸入。使用前比對版控 lock，日後素材版本變更時另行更新 lock。archive 本機權限為 0600，不放在 repo、Docker build context 或測試 artifact 內。來源與驗收保留在本機交接紀錄，不依賴 tmp 作唯一保存位置。

從當前 checkout 建置 runner，並取得實際 image ID：

```bash
docker build --tag tank-skirmish-private-ci:local \
  --file scripts/ci/Dockerfile scripts/ci
docker image inspect tank-skirmish-private-ci:local --format '{{.Id}}'
sha256sum scripts/ci/Dockerfile
```

Dockerfile 固定官方 base digest，補齊 `libfontconfig1`，沿用內建 Node 24，最後使用 `runner`。每次建置讀回自己的 image ID；launcher 不硬編碼某部機器的 image ID，也不承諾不同日期的 apt 套件能產生逐位元相同 image。建置 context 只需 `scripts/ci/`，不得加入素材或憑證。

## 驗證啟動器

```bash
python3 tests/local_ci_assets_test.py
```

預設只使用合成輸入與 mock API，不連 GitHub、不啟動 Docker、不讀私有 archive。矩陣包含一般 Python 與 `python -O` 的完整還原驗證、精確 PR／main 身分、錯誤 job／runner／fork、非 root image、token 只送 stdin 及清理。`quality` 會執行同一命令。

要驗證實際 586 個輸入時，必須明確指定本機 archive：

```bash
python3 tests/local_ci_assets_test.py \
  --archive ~/.cache/tank-skirmish/local-ci-assets/quarter.tar
```

沒有指定 archive 時不會宣稱已驗證私有內容。測試 scratch 預設放在系統暫存目錄並自動清理；需要保存合成測試紀錄時，可用 `--output` 指定新的 repo 外目錄。

## 執行指定 PR CI

先核對 PR 的來源 repo、HEAD、Actions run ID、run attempt 及 workflow。一次只指定一個已授權的版本，不能因為有登入就替任意工作開放素材。

```bash
python3 scripts/ci/run-private-quality.py \
  --pr <PR_NUMBER> \
  --head <EXACT_40_HEX_HEAD> \
  --run-id <EXACT_ACTIONS_RUN_ID> \
  --image <LOCAL_SHA256_IMAGE_ID> \
  --archive ~/.cache/tank-skirmish/local-ci-assets/quarter.tar \
  --output /tmp/tank-ci-<RUN_ID>-<ATTEMPT>
```

`--output` 必須是不存在的新目錄。launcher 先確認 run 的 workflow、HEAD、PR、來源 repo 與 attempt，再用 host GitHub API 核對實際 quality job 指派到自己的 runner ID／name，之後才原子釋出 archive。runner 的唯一 host mount 是 initially empty 的唯讀 gate；沒有 host home、Docker socket 或 host `gh` 憑證。容器使用 cap-drop ALL、no-new-privileges、4 CPUs、8 GiB，runner 是 `--once --ephemeral`。

合併後同版 main CI 使用相同命令但省略 `--pr`，指定實際 merge commit 與 push/main run。launcher 另外核對遠端 main SHA。每次私有素材授權只涵蓋使用者指定的工作；這份文件與版控 launcher 不代表對未來工作的一般授權。

## 結果與清理

完整測試約需 16～18 分鐘，job budget 30 分鐘；每個遊戲測試原門檻不變。`result.json` 必須是 `status=success`，GitHub 實際 run／job 也必須 success，不能用 mock 或程序 exit 0 代替。

啟動器保存 image ID、Dockerfile／lock SHA、assignment、run 結果；結束時先列全量容器，核對固定 container ID／owner 後清理自己的容器與 runner。gate 內的本次 archive 複本會先列清單，再精確移除；原 cache archive 不變。結果中的 `container_removed`、`runner_removed`、`asset_gate_removed` 必須全為 true。留下的是 metadata 與 log，不是素材複本。

若其他 job 誤派到此 runner，素材不會釋出，launcher 會清理自己的 runner。fork workflow 可修改自己的 YAML，job-level `if` 不是授權邊界；而 skipped job 對 required check 會報 success，因此不加入會弱化 quality 的 skip。此流程保證未驗證 assignment 拿不到素材，不宣稱阻止所有不受信任程式進入空容器。較廣的 runner-group／fork 政策需另行設定，沒有在本次改 repo 全局權限。

官方說明：[pull_request 的 workflow 來源](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)、[job 條件與 skipped check](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions)。

## 本次審查建議處置

- CI 啟動器、Dockerfile 與本文件納入版控；image／Dockerfile／lock 的實際身分封存。
- 素材還原使用明確例外，`python -O` 也保留所有原檢查。
- fixture 的四個重複函式移至 static helper；原數值、呼叫順序與斷言保持。
- 三元式的 Node3D 轉型加括號，避免只套用於 else 分支。
- 重生／換車 snapshot 驗的是進樹當下的初始化狀態；後續原 live controls、滿血、AI、相機與 R8 清理／重生／保護檢查保持。沒有新增等待後仍要靜止的產品義務。
- fork 誤派的限制以上述 assignment 與空容器邊界說明，不用 skipped success 偽裝完整 quality。
