---
name: sa-make-enemy-group
description: 检索 SA 8.0 原版敌人组或任务敌人, 整理 AI、成长属性和敌群录入方案, 经用户确认后按现有配置规则直接发布 YAML. 用于为新任务准备敌人数据; 不用于创建宠物、角色、技能、任务、奖励或场景配置.
---

# SA 原版敌人组录入

## 目标

把用户提供的任务名、地图、NPC、敌人名称、原版组号或敌人 ID 等模糊线索, 收敛成用户确认过的敌人集合, 再按项目已有校验、派生和序列化规则直接发布可供任务引用的 YAML 配置.

原版资料和 8.5 源码始终只读. 8.0 数据决定具体记录, 8.5 源码仅解释字段语义. 不把当前项目配置反推为原版事实.

## 检索阶段

1. 先运行 `scripts/inspect_original_enemy_group.py` 搜索原版组名、敌人名和模板名. 脚本从 `gmsv/setup.cf` 解析当前启用的 `groupfile`、`enemyfile` 和 `enemybasefile`, 不硬编码带 `1` 的文件名.
2. 线索涉及任务、地图或 NPC 时, 再使用 `rg` 只读搜索 `server/docs/任务` 和 8.0 `gmsv/data/npc`; 涉及地图区域遇敌时才查 `encount.txt`. `encount.txt` 中引用的是 `groupfile` 的组 ID, 不是现代敌人组 ID.
3. 向用户输出编号候选, 至少包含原版组 ID/名称、敌人 ID/名称、模板 ID/名称、等级范围和证据位置. 此时不要修改任何配置.
4. 必须让用户选择或确认具体敌人. 线索唯一也要明确复述选中的敌人集合并取得确认, 不能把模糊命中直接当最终选择.

常用命令:

```bash
python scripts/inspect_original_enemy_group.py --client-root /d/csa_8.0 --query '线索'
python scripts/inspect_original_enemy_group.py --client-root /d/csa_8.0 --group-id 88
python scripts/inspect_original_enemy_group.py --client-root /d/csa_8.0 --enemy-id 294 295 --format json
```

脚本返回 `0` 表示成功且有结果, `1` 表示搜索无匹配, `2` 表示参数、文件或引用错误. 不把后两者混为一谈.

## 方案阶段

用户确认敌人后, 阅读 [references/editor-fields.md](references/editor-fields.md), 按其中映射整理三类数据. 输出每名敌人的:

- 原版敌人 ID、名称、模板 ID、模板名称、等级范围、生成数量/权重、掉落和来源行.
- 完整 `tacticsOption` 及解析后的 `at/gu/ma/es/wa/rn`; 每个非零技能权重对应的当前已发布技能 ID 和名称.
- 元素、六项抗性、暴击、反击、稀有率、捕获难度、初始值、升级点来源和基础体力/腕力/耐力/速度.
- 当前 `pet.yaml` 或 `character.yaml` 外观候选及证据, 以及拟复用或新增的 AI、成长属性.

先检查依赖:

- 宠物优先用 `pet.yaml enemyId` 精确匹配原版敌人 ID; 人形或其他角色按原版名称、模板图像号、角色及动画配置交叉核对. 多个候选必须让用户选择.
- 找不到对应的已发布 `pet.yaml` 或 `character.yaml` 数据时立即停止, 告诉用户应先创建哪只宠物或角色数据. 不创建临时外观, 不直接改这些配置.
- `wa0..wa6` 必须通过原版模板技能槽和当前技能 RAW 的 `legacyId`/来源证据映射到已发布技能. 缺少可靠映射或技能尚未发布时停止并列出缺口, 不删掉该动作, 不换成普通攻击.
- 掉落道具若要录入, 必须映射到当前已发布道具. 映射缺失时把“暂不录入掉落”或“先创建道具”作为待确认项, 不直接使用原版道具 ID.

去重规则:

- AI 仅比较运行字段: 有序技能 ID/权重、`targetScope`、`targetSelection` 和可选 `targetRandomRollMax`. 与某个已发布 AI 完全一致时复用.
- 成长属性仅比较 `elemental`、`attribute` 和 `growth`; `panelReference` 是编辑器派生值. 与某个已发布成长属性完全一致时复用.
- 只复用已发布条目. 草稿、删除条目或仅名称相同都不算可复用.

为所有新增或最终引用的数据生成一张录入清单, 并要求用户一次性确认:

- AI ID、名称、技能及目标策略. 建议名称为 `[任务][任务名]敌人显示名`.
- 成长属性名称和全部数值. 建议名称为 `原版模板名[任务][任务名]敌人显示名`; ID 由成长属性 RAW 的 `nextId` 分配.
- 敌人组 ID、名称、Boss/普通组、成员顺序、外观、显示名、成长属性、AI、等级、数量/权重、捕获和掉落. 建议名称为 `[任务][任务名][阶段]`.

用户没有确认具体敌人、三个名称或最终录入清单时, 不修改配置.

## YAML 落地

最终确认只授权清单内的数据. 不要求打开 Godot 或使用 `computer-use`; 直接维护 YAML, 但必须把项目已有规则代码视为权威约束, 不能绕过校验或自行放宽格式.

修改前必须:

1. 读取 `make_ai`、`make_growth_attribute`、`make_enemy` 的文档模型、校验器、序列化器和对应 README, 确认当前字段、允许值、运行投影及跨表引用规则.
2. 检查目标 RAW、运行配置和待用 ID 的当前状态. 现有改动属于用户, 必须在当前内容上增量修改; 目标 ID、`nextId` 或同名记录与确认清单冲突时停止并报告.
3. 确认 RAW 与当前运行配置在修改前符合各自的确定性投影. 若存在与本任务无关的既有不同步, 不覆盖或顺带修复, 先报告.

按依赖关系直接修改:

1. `config.raw/ai.yaml`, 并同步它在 `server/config/ai.yaml` 中的运行投影.
2. `config.raw/growth.attribute.yaml`, 使用现有 `nextId` 分配 ID; `panelReference` 必须按 `pet_panel_reference.gd` 的正式算法计算, 再同步客户端和服务端 `growth.attribute.yaml`.
3. `config.raw/enemy.group.yaml`, 引用已经发布的外观、成长属性和 AI, 再同步客户端和服务端 `enemy.group.yaml`.

使用 `apply_patch` 做精确增量编辑. RAW 是业务编辑源; 运行 YAML 只允许写入对应 RAW 的确定性投影, 不得在生成配置中加入 RAW 不存在的业务差异. 不修改 `task.yaml`、奖励、场景、地图、宠物、角色和技能配置.

## 验证与交付

- 重新解析 RAW 和运行 YAML, 核对新增/复用条目的 ID、名称、状态、引用和确定性投影.
- 只读检查文件差异, 预期仅涉及三类 RAW、对应运行输出以及因穷举配置产生的必要测试期望; 出现其他文件时停止并说明.
- 运行三类配置 README 指定的核心测试、Godot headless 配置检查及受影响服务端配置测试. Godot headless 仅用于自动校验, 不是配置写入入口. 测试失败时从第一个真实错误修正已确认范围内的数据, 不删除断言、不弱化校验、不使用临时兜底数据.
- 最终按 `🟢 成功`、`🟡 警告` 或 `🔴 失败` 汇报: 原版来源、确认内容、新增/复用 ID、同步目标、验证结果和仍需用户处理的缺口.
