---
name: sa-export-weapon-item-yaml
description: 通过 Godot make_weapon 维护 SA 武器目录, 校验或导出已发布记录到 item.weapon.yaml. 用于武器目录编辑、发布状态管理和配置导出. 不处理普通 item.yaml, 不使用旧 Excel 导出流程, 不把编辑或校验自动扩展为导出和客户端同步.
---

# SA 武器目录维护与导出

使用项目内 Godot `make_weapon` 插件及其共享模型维护武器目录, 由同一导出器生成完整运行配置. 操作前读取 `sa.desktop/addons/make_weapon/README.md`, 当前字段和行为以项目实现为准, 不另建 Python 转换规则.

## 数据边界

- `server/docs/item.weapon.catalog.yaml`: 唯一编辑来源, 保存全部 `draft` 和 `published` 记录.
- `server/config/item.weapon.yaml`: 仅由已发布记录生成的服务端运行输出, 不直接修改或反向补写目录.
- `sa.desktop/addons/make_weapon`: Godot 编辑器主屏, 目录模型, 资源校验, 事务存储和确定性导出实现.
- `sa.desktop/assets/item/武器.<类型>.png/.tpsheet`: 实际帧预览和发布校验的资源来源.
- `sa.desktop/config/item.weapon.yaml`: 仅在用户明确要求时同步的客户端副本.
- `server/config/item.yaml`: 普通道具配置, 不在本技能修改范围内.

即使用户只修改一种武器, 导出仍完整生成 8 个运行分组, 不局部拼接生成文件. 旧 Excel 和旧 Python 导出流程已退出维护链路; 不恢复这些文件来完成日常编辑或导出. 若目录或插件缺失, 停止并报告缺失项.

## 编辑与主动发布

交互编辑使用 Godot 顶部的 `武器` 主屏. 搜索, 类型和状态筛选用于定位记录, 右侧结构化表单用于编辑, YAML 预览只读.

1. 按用户明确范围编辑, 新增或删除记录. 新武器保持草稿, 不因字段完整而自动发布.
2. `发布` 或 `撤回发布` 只修改内存中的目录状态, 不保存目录也不导出运行配置.
3. `保存目录` 写入唯一源数据; 删除在保存后才永久生效.
4. 目录没有未保存修改后, 使用 `导出item.weapon.yaml` 显式生成服务端配置. 编辑, 保存或发布本身不代表用户要求导出.

当前测试阶段允许修改已发布武器的现代 ID. 使用插件的引用扫描和二次确认, 报告影响位置; 不自动改写引用, 不生成 ID 别名或迁移存档.

## Headless 校验与导出

使用本机已安装, 符合项目版本要求的 Godot 控制台可执行文件. 下列命令中的 `godot` 需替换为实际命令或可执行文件路径, 命令在 `sa.project` 根目录通过 Git Bash 执行. 不为运行本技能擅自安装或下载依赖.

先只读校验并渲染候选:

```bash
godot --headless --path sa.desktop --script res://addons/make_weapon/headless/weapon_catalog_cli.gd -- --check
```

检查退出码, 完整日志和 JSON 摘要. 只有退出码为 0, 没有 `SCRIPT ERROR` 且 `ok: true` 时才算通过. 摘要提供 `records`, `published`, `draft`, `groups` 和候选的 `outputSha256`. `--check` 不会更新目标文件, 也不提供旧流程的 `config_changed`.

仅在用户要求导出或更新运行配置时, 校验通过后执行:

```bash
godot --headless --path sa.desktop --script res://addons/make_weapon/headless/weapon_catalog_cli.gd -- --export
```

CLI 只读取已保存到磁盘的目录, 不包含编辑器的未保存状态. 它与编辑器共享校验和渲染规则, 通过事务暂存, 重新解析, 源/目标指纹检查和失败回滚提交. `user://make_weapon_transaction` 是内部暂存位置, 不是持久备份目录, 不沿用旧 Python 流程的备份路径约定.

CLI 支持 `--catalog=<路径>` 和 `--output=<路径>`; 默认使用上述正式源和目标, 只有任务明确需要时才覆盖路径.

正式导出后:

1. 在 `server` 目录运行 `go test ./common/gameconfig`. 这是导出后的独立验证, 不是导出器内部步骤.
2. 再次运行 `--check`, 将 `outputSha256` 与 `sha256sum server/config/item.weapon.yaml` 的实际文件哈希比较.
3. 仅当用户明确要求客户端同步时, 在 `sa.desktop` 目录运行 `./cp.config.from.server.sh item.weapon.yaml`, 并核对两端文件哈希. 插件本身不自动同步客户端.

修改插件或导出实现时, 另运行共享核心测试:

```bash
godot --headless --path sa.desktop res://tests/test_make_weapon_core.tscn
```

## 数据约束与失败处理

- 保留所有草稿, 不把未发布或缺少发布必填项的记录当作旧流程的跳过行丢弃.
- 草稿可以不完整, 但已填写字段必须满足类型, 枚举, ID 区间与唯一性, 元素关系, 魔法耗蓝关系和最小/最大范围约束.
- 发布要求现代 ID, 名称和真实帧资源完整; 整表导出额外要求 8 个运行分组均非空. 资源缺失, 非法范围或重复 ID 必须明确报错, 不静默修补.
- `weaponType` 决定 ID 分组区间和派生 atlas. 稳定键 `legacy:<originalId>` 或 `custom:<sequence>` 不随现代 ID 变化.
- 目录的 `elementValue` 已使用 `0-10` 范围, 直接映射运行配置 `attribvalue`, 不再次除以 10.
- `legacyHitRight` 和 `legacyNeglectGuard` 保留原版 `hirt`, `neguard` 值. 非 0 时阻止发布, 不擅自清零或丢弃.
- `effectString` 由用户维护并映射 `effectstring`, 不根据其他字段自动生成或覆盖.
- 遇到外部修改, 保存失败或发布阻塞, 报告具体记录和原因; 不绕过共享模型直接改写运行输出.

最终报告本次修改范围, 8 个分组的总数/已发布数/草稿数, 实际导出目标, 哈希, 测试结果以及是否同步客户端. 只完成校验时明确说明未写入配置.
