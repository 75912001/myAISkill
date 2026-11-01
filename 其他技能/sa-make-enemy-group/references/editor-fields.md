# 原版字段与编辑器映射

仅在整理录入方案或直接维护 YAML 配置时阅读本文件.

## 原版证据链

`gmsv/setup.cf` 是当前启用文件的入口:

- `groupfile`: 敌人组. 第一列为内部名称, 后续依次为组 ID、出现所需道具、禁止出现道具、10 个敌人 ID、10 个相对权重.
- `enemyfile`: 敌人实例. 前三列为名称、`tacticsOption`、行动条件, 后续包含敌人 ID、模板 ID、等级、生成数量、战术模式、经验、DP、style、掉落等.
- `enemybasefile`: 敌人模板. 保存模板名称、成长、元素、抗性、7 个技能槽、稀有率、暴击、反击、图像号等.
- `encountfile`: 地图区域到原版组 ID 的索引. 它不定义组内成员.

重复组 ID、敌人 ID 或模板 ID 均按原服务端线性查找的第一条生效, 但必须把重复行全部报告为异常.

## AI YAML

原版普通 AI 的权重顺序是 `at -> gu -> ma -> es -> wa0..wa6`:

| 原版字段 | 现代含义 |
|---|---|
| `at[0]` | 普通攻击权重, 技能 `8000001` |
| `gu[0]` | 防御权重, 技能 `8000002` |
| `ma[0]` | 原版魔法权重; 当前没有可靠已发布映射时必须停止 |
| `es[0]` | 逃跑权重, 技能 `8000003` |
| `wa[i]` | `enemybase` 的第 `i+1` 个技能槽对应技能权重 |
| `at[1]` | 目标范围: 1=全部对手, 2=玩家角色, 3=玩家宠物, 4=队长 |
| `at[2]` | 目标选择: 1=随机, 2=最高HP, 3=最低HP, 4=最高腕力, 5=最高敏捷, 6=最低敏捷, 7=属性克制 |
| `rn[0]` | 非随机目标策略的原版随机覆盖上限, 对应 `targetRandomRollMax` |

保留技能的原始顺序和原始整数权重. 不归一化百分比. `tactics != 1`、非空行动条件、未知目标枚举或当前校验器及运行时不支持的策略都必须列为未解决项, 不能凭名称猜测.

## 成长属性 YAML

| 原版 `enemybase` | 成长属性 YAML |
|---|---|
| `earth/water/fire/wind` | `elemental` 四元素, 省略零值 |
| 六项 resistance | 六项 `*Resist` |
| `critical/counter` | `critical/counter` |
| `rare` | `rate` 稀有率 |
| `captureRate` | `get` 捕获难度 |
| `initialNumber` | `growth.initNum` |
| `levelUpPoint` 原始数值 | `growth.lvupPointSource` |
| `baseVitality` | `growth.baseVital` |
| `baseStrength` | `growth.baseStr` |
| `baseToughness` | `growth.baseTough` |
| `baseDexterity` | `growth.baseDex` |

`panelReference` 由 `pet_panel_reference.gd` 的正式算法派生, 不拿它参与去重. 直接维护 YAML 时必须用同一算法计算并由核心测试复核, 不能凭经验填写. 数值去重必须比较完整的 `elemental`、`attribute` 和 `growth`.

## 敌人组 YAML

- `petId` 与 `characterId` 必须二选一. 角色还必须确认 `weapon`; 原版 `style` 只能作为查证线索, 不能未经核对直接当现代武器枚举.
- 原版单个敌人的 `levelMin/levelMax` 对应成员 `level` 或 `levelRange`.
- 普通组的组内敌人及概率来自 `groupfile`; 数量必须结合原版组、区域 `enemymaxnum` 和选定任务语义讨论后确认. 不把原版组 ID 直接复用为现代敌人组 ID.
- 任务脚本直接列出的固定敌人通常建为 Boss 组并保持脚本顺序, 但仍须由用户确认.
- 原版 `enemyfile` 掉落概率以千分比保存, 现代 `enemy.group.yaml` 使用万分比, 因此确认导入时乘以 10. 道具 ID 必须先映射到当前已发布道具.
- `displayName` 使用用户确认的任务展示名; 不因原版敌人名和模板名不同而静默改名.
- `captured`、`babyRate`、`gradeRange` 和 `attributeModifiers` 只有在原版证据或用户决定明确时才填写, 不补默认业务结论.

## 停止条件

出现以下任一情况时只输出缺口, 不修改配置:

- 用户尚未确认具体敌人、外观映射或三类名称.
- 缺少所需的已发布宠物、角色、技能或确认要录入的掉落道具.
- 原版记录缺失模板、字段数量异常、目标策略无法表达或证据相互冲突.
- 目标 ID 或 `nextId` 与当前配置冲突, 正式规则代码无法加载, 或 RAW 与运行配置存在本任务之外的既有不同步.
