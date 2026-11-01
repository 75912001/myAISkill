---
name: sa-pet-extract-animation-frames
description: 采集 SA 宠物动画的 56 个动作, 生成独立 sprite YAML 并只读校验帧偏移. 用于宠物八方向动作提取或 sa.宠物.提取帧动画. 不因泛指资源提取器而触发, 不用于角色 104 动作、特效单动作或独立 frameid 查询.
---

# 宠物帧动画提取

## 输入与约束

- 接收一个大于 0 的整数作为当前动画序号.
- 固定使用 `D:\软件\素材导出工具\石器时代资源提取器.exe`.
- 开始前提醒用户暂时不要操作鼠标和键盘. 脚本会启动或接管该窗口并操作原生上下箭头按钮.
- 必须运行本 skill 随附的 `scripts/extract_pet_animation.ps1`, 不要重新手写自动化逻辑或改用固定屏幕坐标.
- 不需要第三方 Python、AutoHotkey 或 Windows UI 插件. 脚本仅使用 Windows PowerShell 5.1、UI Automation 和 Win32 API.
- GUI 启动或桌面交互需要权限时, 按当前环境流程请求批准.

## 执行

按当前环境要求从 Git Bash 调用 Windows PowerShell. 将 `<skill-dir>` 替换为本 `SKILL.md` 所在目录的绝对路径:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_pet_animation.ps1' -AnimationIndex <当前动画序号>
```

脚本会自动完成以下工作:

1. 启动或连接资源提取器, 取消“自动播放帧”.
2. 通过编辑框和对应的上下箭头按钮设置当前动画序号、动作号和动作帧, 再回读控件值确认操作成功.
3. 验证当前动画总动作数为 56.
4. 遍历动作号 1~56, 动态读取每个动作的总帧数, 从动作帧 1 开始逐帧采集.
5. 以界面上方“指定序号”为 `frameid`, 以左上角绿色“序号”交叉校验, 同时读取“图片偏移 X/Y”.
6. `sprite` 数组原样保留连续或非连续的重复序号. 重复帧必须再次校验偏移一致.
7. 全部通过后, 使用 `server/docs/offset.yaml` 的四字段元数据逐项校验本次偏移, 再写入带文件范围和去重文件数注释的完整 `sprite` YAML.

输出目录固定为 `D:\src\github.com\sa.project\server\config`, 动画文件名固定为 `<当前动画序号>.yaml`. 例如当前动画序号为 `277` 时写入 `D:\src\github.com\sa.project\server\config\277.yaml`. 帧元数据固定从 `D:\src\github.com\sa.project\server\docs\offset.yaml` 只读校验. 脚本在启动采集前检查动画文件并拒绝覆盖已有文件. 不修改 `pet.yaml`; 只有用户明确要求时才另行修改该配置.

如果控件 ID 因软件版本变化而失效, 使用只读探测模式输出当前窗口的 UI Automation 和 Win32 控件树:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_pet_animation.ps1' -Probe
```

探测后先报告差异并修改脚本, 不要用推算值、固定屏幕坐标或不完整 YAML 绕过失败.

## 固定映射

每个方向连续 7 个动作. 方向顺序固定为:

1. `down`: 动作号 1~7
2. `downleft`: 动作号 8~14
3. `left`: 动作号 15~21
4. `upleft`: 动作号 22~28
5. `up`: 动作号 29~35
6. `upright`: 动作号 36~42
7. `right`: 动作号 43~49
8. `downright`: 动作号 50~56

每组 7 个动作按用户指定的顺序固定为:

1. `attack`
2. `faint`
3. `hurt`
4. `defense`
5. `stand`
6. `walk`
7. `attackShort`

不要按动作分组后再排列方向.

## 输出与失败处理

- 输出结构必须与 `config/pet.yaml` 的 `sprite` 项目一致, 方向数为 8, 每个方向恰好 7 个动作数组, 总计 56 个数组.
- 输出路径必须是 `D:\src\github.com\sa.project\server\config\<当前动画序号>.yaml`.
- 帧元数据路径必须是 `D:\src\github.com\sa.project\server\docs\offset.yaml`, 格式为 `frameid: [offsetX,offsetY,width,height]`.
- 帧元数据只读. frameid 缺失或 X/Y 与采集值不一致时立即报错, 不输出动画 YAML, 不创建或修改任何 offset 文件.
- 在 `sprite` 和每个方向后添加 `# [最小序号,最大序号] N 个文件` 注释. `N` 是对应范围内所有动作帧序号去重后的数量, 不是 `最大序号 - 最小序号 + 1`.
- `sprite` 的注释统计全部 8 个方向; 方向注释只统计该方向的 7 个动作.
- 每个数组长度必须等于界面中该动作的总帧数, 帧顺序必须与动作帧 1~总帧数一致.
- 数组元素为不带引号的整数, 使用英文逗号分隔.
- 相邻帧可能显示相同的指定序号. 这是合法数据, 必须为每一帧分别记录, 不能用序号是否变化判断箭头点击是否成功.
- 任一控件设置失败、回读不一致、总动作数不是 56、序号交叉校验失败、重复偏移不一致或正式帧元数据格式无效时, 立即暴露错误并停止, 不输出不完整的最终 YAML.
- 成功后向用户返回动画序号、动作数、总帧数、唯一偏移数、校验偏移数、动画输出路径和帧元数据路径和完整 `sprite` YAML.
