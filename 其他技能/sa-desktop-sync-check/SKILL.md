---
name: sa-desktop-sync-check
description: 使用 SA 客户端已有脚本同步共享配置、同步协议并生成 GDScript PB, 或执行 Godot headless 检查. 用于明确的客户端同步或检查任务, 仅执行请求的子流程. 不从 server 复制编辑器差异化导出的配置, 不默认生成服务端 Go PB, 不导出 Windows 客户端.
---

# SA / 客户端 / 同步与检查

复用 `sa.desktop` 已有同步和生成入口, 不另建复制或生成逻辑. 所有命令通过 Git Bash 执行.

## 工作目录与执行边界

- 当前项目的客户端仓库为 `D:/src/github.com/sa.project/sa.desktop`; `sa.project` 是聚合目录, 不是本 skill 的 Git 工作目录.
- 优先使用用户明确提供的客户端目录. 否则从当前目录向上检查 `project.godot`, 或检查聚合目录下的 `sa.desktop/project.godot`. 仍未定位时检查上述已知路径; 无匹配或有歧义时再询问.
- 将确认后的客户端根目录记为 `CLIENT_ROOT`, 后续命令均在此目录执行. 按请求检查入口: 检查客户端只需要 `project.godot`, 配置或协议同步分别需要对应脚本.
- 每个子流程开始前执行 `git -C "$CLIENT_ROOT" status --short`, 识别目标文件的已有改动. 不在聚合目录执行 Git 检查, 不要求检查 server 仓库状态. 已有改动若会被覆盖且未获授权, 先报告具体冲突.
- 同步源使用对应脚本中环境变量覆盖值或默认值; 环境变量未设置不等于源目录不存在. 先只读确认实际路径和输入, 不猜测其他数据源.
- 只执行请求的子流程. 完整同步与检查依次执行共享配置同步、协议同步及 PB 生成、Godot 检查. 普通配置同步不隐含编辑器 C/S 导出, 因为正式导出也会写入 server.
- 安装工具、联网下载、修改系统 PATH 或清理非本次产生的文件, 需具备相应授权. 同步和检查失败时报告原因, 不自动扩大为修改源配置、协议或生成器的修复任务.

## 同步共享配置

入口为 `./cp.config.from.server.sh`, 输入为 `SERVER_CONFIG_DIR` 对应的 server `config/`, 输出为客户端 `config/`.

唯一可复制清单由脚本的 `SYNC_CONFIG_FILES` 维护, 不在 skill 中重复维护. 指定文件时按原范围传参:

```bash
./cp.config.from.server.sh pet.yaml pet.sprite.yaml
```

用户要求全部共享配置时才不传参数:

```bash
./cp.config.from.server.sh
```

编辑器按 C/S 分别导出的配置不得加入复制清单, 即使两端暂时相同也不能复制. 技能、商店、武器和装备的运行配置通过对应编辑器正式导出流程更新; 同步脚本应拒绝这些文件, 不改用手工复制. 需要重新导出时查对应 `addons/make_*/README.md`, 并按用户明确要求调用正式入口. 来源不明时先查证, 不依据同名推断可同步.

执行后检查脚本退出码和 `git -C "$CLIENT_ROOT" status --short -- config`, 对照执行前状态确认本次变更. 复制成功只表示共享配置同步完成, 不等于业务配置校验通过.

## 同步协议并生成客户端 PB

入口为 `./cp.proto.from.server.and.gen.sh`, 执行链为:

```text
SERVER_PROTO_DIR/*.proto -> 客户端 proto/*.proto -> Godobuf -> proto/sa.pb.gd
```

“同步客户端 PB”即执行这条完整链路. 它读取服务端 `.proto` 源文件, 不依赖服务端生成的 Go PB, 不默认运行 `python 1.gen.py`.

运行前确认源协议、`proto/sa.proto`、`addons/godobuf/godobuf_cmdln.gd` 和 Godot 可用. 现有脚本会在检查 Godot 前复制协议, 因此必须提前确认工具, 避免缺少 Godot 时已发生同步.

```bash
./cp.proto.from.server.and.gen.sh
```

Godot 优先使用 `GODOT_BIN` 或 PATH 中的 console 版本, 可显式传入已确认的路径:

```bash
GODOT_BIN=/path/to/Godot_console.exe ./cp.proto.from.server.and.gen.sh
```

检查退出码、生成日志、产物非空, 文件头包含 `class_name PB` 和 `extends Node`, 并核对 `proto/` 本次差异. 不手工修改 `sa.pb.gd` 修补生成结果. 生成失败时先定位 Godot/Godobuf 首个错误, 不伪造产物或回滚用户改动.

## Godot 检查

只要求检查时不先同步. 在客户端根目录, 使用已确认的 `GODOT_BIN` 或 PATH 中的 Godot console 执行:

```bash
set -o pipefail
"$GODOT_BIN" --headless --editor --path . --quit 2>&1 | tee "$CHECK_LOG"
check_status=("${PIPESTATUS[@]}")
```

`CHECK_LOG` 在运行前设为本次独立日志路径, 使用临时目录或项目已有日志目录, 不覆盖已有日志. 紧接管道保存状态, 同时检查 Godot 和 tee 的退出码. 不仅依赖进程退出码: 检查本次完整日志中的错误和警告, 必要时先去除 ANSI 颜色码; 日志筛选命令只用于定位, 不以其退出码代替检查结论.

通过条件为正常结束、日志存在且非空、无错误、无警告. 任一错误或警告均判为检查失败; 工具或输入缺失则明确未完成检查. 该命令是 headless 编辑器加载检查, 不代表全部运行时测试通过, 不生成或验证 `sa.exe`、`sa.pck` 等 Windows 导出产物.

## 汇报

按实际执行内容报告命令、本次更新文件和结果. 使用 `🟢 成功`、`🔴 失败`、`🟡 警告` 区分已通过、失败和未验证事项. 分别说明共享配置已同步、PB 已生成或 Godot 检查已通过; 未请求的检查标明未执行, 不把同步成功当作检查通过. 失败后明确已发生的文件变更, 不静默掩盖部分结果.
