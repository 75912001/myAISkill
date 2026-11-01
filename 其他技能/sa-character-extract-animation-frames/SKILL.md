---
name: sa-character-extract-animation-frames
description: 采集 SA 角色动画的 104 个动作, 通过正式生成器更新 character.sprite.yaml 并只读校验四字段帧元数据. 用于角色动作提取或 sa.角色.提取帧.偏移; 不用于宠物 56 动作、特效单动作或独立 frameid 查询.
---

# 角色帧和偏移提取

## 输入与约束

- 接收一个大于等于 0 的整数作为角色动画序号, 同时作为 `sprite[].id`.
- 固定使用 `D:\软件\素材导出工具\石器时代资源提取器.exe`.
- 开始 GUI 采集前提醒用户暂时不要操作鼠标和键盘.
- 必须运行本 skill 随附的 `scripts/extract_character_animation.ps1`, 不要重写自动化逻辑, 不要改用固定屏幕坐标.
- 固定写入 `D:\src\github.com\sa.project\server\config\character.sprite.yaml`.
- 固定使用 `D:\src\github.com\sa.project\server\docs\offset.yaml` 的 `[offset_x,offset_y,width,height]` 元数据只读校验所有采集帧; 缺失元数据时立即停止.
- 固定使用 `D:\src\github.com\sa.project\server\tool\character_sprite_metadata.py` 生成正式角色播放元数据.
- 正式元数据生成器固定读取 `D:\csa_8.0\data\spr_115.bin` 和 `D:\csa_8.0\data\spradrn_115.bin`.
- Python、正式生成器或原版二进制资源缺失时, 必须在启动 GUI 前停止.

## 新增与覆盖

开始采集前只读检查目标 `sprite[].id`:

- ID 不存在时直接采集并追加新条目. 脚本先在临时配置中写入命中帧种子, 再由正式生成器补齐 FPS、攻击和投掷声音、释放帧及 ActionRaw 参考.
- 新条目的 `attackImpactFrameNumberList` 使用八个方向共同的 `attack` 最后播放位置, 即 `[attack 帧数]`. 八个方向的攻击帧数不一致时立即停止, 不猜测共享命中位置.
- ID 已存在时先向用户提示并询问是否覆盖. 未明确确认时不得添加 `-Overwrite`.
- 覆盖先替换条目首行范围注释和八方向动作帧, 保留已有 `attackImpactFrameNumberList` 和其他非生成元数据; 正式生成器随后重建播放元数据和 ActionRaw 参考.
- 覆盖时若新范围注释与原注释不同, 脚本不写文件并逐条输出原注释和建议注释. 向用户展示这些差异并再次确认后, 才能添加 `-UpdateComments`.
- `-UpdateComments` 必须与 `-Overwrite` 同时使用.

## 执行

按当前环境要求从 Git Bash 调用 Windows PowerShell:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_character_animation.ps1' -AnimationIndex <动画序号>
```

用户确认覆盖已有 ID 后:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_character_animation.ps1' -AnimationIndex <动画序号> -Overwrite
```

用户确认脚本报告的全部注释变更后:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_character_animation.ps1' -AnimationIndex <动画序号> -Overwrite -UpdateComments
```

控件版本变化时使用只读探测:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_character_animation.ps1' -Probe
```

维护脚本后运行不启动 GUI 的自检:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_character_animation.ps1' -SelfTest
```

## 固定动作映射

每个方向连续 13 个动作. 方向顺序固定为:

1. `down`
2. `downleft`
3. `left`
4. `upleft`
5. `up`
6. `upright`
7. `right`
8. `downright`

每组动作顺序固定为:

1. `attack`
2. `wave`
3. `faint`
4. `hurt`
5. `defense`
6. `sad`
7. `angry`
8. `sit`
9. `stand`
10. `throw`
11. `nod`
12. `walk`
13. `happy`

动作号必须按方向分组映射, 总数必须恰好为 104.

角色武器名称按 `id % 5` 固定映射:

1. `0`: `unarmed`
2. `1`: `axe`
3. `2`: `stick`
4. `3`: `spear`
5. `4`: `bow`

## 采集和写入规则

1. 取消 "自动播放帧", 设置并回读动画序号, 动作号和动作帧.
2. 逐帧读取 "指定序号" 作为 `frameid`, 使用绿色 "序号" 交叉校验, 同时读取图片偏移 X/Y.
3. 动作数组保留重复 frameid 和原始播放顺序. 偏移映射按 frameid 去重; 同一 frameid 的偏移不一致时立即停止.
4. 每个动作必须至少有一帧, 每个数组长度必须等于界面报告的总帧数.
5. `unarmed` 的范围注释统计全部动作. 其他武器保留 `throw` 数组, 但范围注释不统计复用的 `throw` 帧, 与现有角色配置格式一致.
6. 新 ID 追加到当前最后一个 sprite 条目之后, 文件尾部分隔线之前. 每个新五武器组的 `unarmed` 条目前添加 `######`.
7. 保留 `character.sprite.yaml` 原有 UTF-8 BOM 状态和换行风格; `offset.yaml` 只读, 不改变其内容和文件状态.
8. 候选角色配置先写入同目录临时文件, 由正式生成器执行全量审计和元数据生成; 除目标 sprite 条目外出现任何内容变化时立即停止.
9. 采集完成后重新校验角色配置和四字段元数据表均未被其他流程修改. 任一文件发生并发变化都拒绝写入角色配置.
10. 仅在正式生成器审计通过后, 使用同目录临时文件和备份原子更新 `character.sprite.yaml`; 写入前再次确认 `offset.yaml` 快照未变化.

## 失败与结果

- 任一控件设置失败, 回读不一致, 动作数不是 104, 序号交叉校验失败, 攻击帧数不一致, 四字段元数据格式非法、帧元数据缺失、偏移冲突, 正式元数据审计失败, 目标 YAML 格式无效或并发变化时立即停止.
- 失败时不写不完整动作数据, 不使用估算帧号, 估算偏移或临时补丁绕过.
- 成功后返回动画序号, 新增或覆盖模式, 动作数, 总播放帧数, 已校验偏移数, 角色输出路径、只读元数据路径和包含 FPS、声音、释放帧及 ActionRaw 参考的完整角色条目 YAML.
- 成功后提醒用户: `character.sprite.yaml` 文件头要求任何修改都通知客户端和服务端开发人员.
