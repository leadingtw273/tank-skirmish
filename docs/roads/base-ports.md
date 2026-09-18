# Base 道路吸附端點

`src/world/roads/base_snap_points.json` 是 base_demo 右 Alt 道路吸附的唯一資料來源；每個端點以本地 GLB 的實際開放端面中心表示，座標在模型 local space，`outward` 為從道路向外的單位向量。資料涵蓋 base pack 的全部可連接道路，另加入 parking pack 的 `Road3_Crossing`（zebra crossing）兩端。

端面以 `scripts/roads/inspect_ports.gd` 讀取已匯入 GLB 的頂點與包圍範圍交叉驗證；曲線／分岔的值依端面方向回推，沒有把曲線直接視為 AABB 的極值。`Road11_Y_Splitter` 的斜向端面中心為 `(+/-7.75736, 0, 13.75736)`：從檢出的外緣角 `(+/-12, 0, 18)` 沿斜向內退一個半路寬取得。

`Road6_End` 僅有入口端，封閉端不是可連接道路口。lamp、tree、barrier、cone、traffic light、bush 等 base 非路網裝飾不適用，故不列入資料表。

驗證命令（不使用 editor import）：

```sh
XDG_DATA_HOME="$PWD/artifacts-local/xdg/data" \\
XDG_CONFIG_HOME="$PWD/artifacts-local/xdg/config" \\
XDG_CACHE_HOME="$PWD/artifacts-local/xdg/cache" \\
/home/markchou/.cache/tank-skirmish/toolchains/godot/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64 \\
  --headless --audio-driver Dummy --path . --script res://tests/base_ports_smoke.gd
```

此 smoke test 會實際載入各 GLB，檢查 JSON schema、完整模型集合、各模型端口數、地面端面與單位方向。檢視端面資料時可改執行 `res://scripts/roads/inspect_ports.gd`。
