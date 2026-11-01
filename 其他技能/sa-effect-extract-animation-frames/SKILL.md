---
name: sa-effect-extract-animation-frames
description: 采集 SA 资源提取器当前动作的全部 frameid 和偏移, 保持动作号不变并只读校验元数据. 用于特效单动作提取或 sa.特效.提取帧动画. 不遍历角色或宠物的全部动作, 不写动画配置.
---

# 特效帧动画提取

## 输入与约束

- 接收一个大于 0 的整数作为当前动画序号.
- 固定使用 `D:\软件\素材导出工具\石器时代资源提取器.exe`.
- 开始前提醒用户暂时不要操作鼠标和键盘. 脚本会启动或接管该窗口并操作原生上下箭头按钮.
- 必须运行本 skill 随附的 `scripts/extract_effect_animation.ps1`, 不要重新手写自动化逻辑或改用固定屏幕坐标.
- 不需要第三方 Python、AutoHotkey 或 Windows UI 插件. 脚本仅使用 Windows PowerShell 5.1、UI Automation 和 Win32 API.
- GUI 启动或桌面交互需要权限时, 按当前环境流程请求批准.

## 执行

按当前环境要求从 Git Bash 调用 Windows PowerShell. 将 `<skill-dir>` 替换为本 `SKILL.md` 所在目录的绝对路径:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_effect_animation.ps1' -AnimationIndex <当前动画序号>
```

脚本会自动完成以下工作:

1. 启动或连接资源提取器, 取消“自动播放帧”.
2. 读取并保留当前动作号. 仅在当前动画号与输入不同时设置动画号; 设置后动作号发生变化则立即失败.
3. 动态读取当前动作的总帧数, 从动画帧 1 开始逐帧切换. 脚本不会设置或点击动作号控件.
4. 以界面上方“指定序号”为 `frameid`, 以左上角绿色“序号”交叉校验, 同时读取“图片偏移 X/Y”.
5. 每一帧都回读动画号、动作号和动画帧号. 任一值偏离预期时立即失败.
6. 将本次采集到的 `frameid: [offsetX,offsetY]` 与固定的四字段帧元数据逐项校验.
7. 在标准错误输出中逐帧输出动画帧号、序号和偏移, 在标准输出中输出本次采集的偏移映射.

帧元数据固定为 `D:\src\github.com\sa.project\server\docs\offset.yaml`, 仅用于只读校验. 本 skill 不生成 `<动画序号>.yaml`, 不修改动作号、帧元数据或其他配置文件.

如果控件 ID 因软件版本变化而失效, 使用只读探测模式输出当前窗口的 UI Automation 和 Win32 控件树:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_effect_animation.ps1' -Probe
```

探测后先报告差异并修改脚本, 不要用推算值、固定屏幕坐标或不完整数据绕过失败.

## 输出与失败处理

- `server/docs/offset.yaml` 必须已存在, 使用顶层映射 `frameid: [offsetX,offsetY,width,height]`.
- 开始 UI 自动化前先校验完整元数据; 全部帧采集成功后再次读取最新文件并逐项校验.
- frameid 缺失或 X/Y 与采集值不一致时立即报错, 不写入任何文件.
- 当前动作内重复出现的 `frameid` 必须再次校验偏移一致.
- 正式帧元数据始终只读, 脚本仅在标准输出中返回本次采集的两字段偏移映射.
- 任一控件设置失败、回读不一致、动作号变化、帧数无效、序号交叉校验失败、偏移冲突或正式帧元数据格式无效时, 立即暴露错误并停止, 不写入部分结果.
- 成功后向用户返回动画序号、当前动作号、总帧数、唯一偏移数、校验偏移数和帧元数据路径.

## 开发验证

修改本 skill 后先运行自检. 自检只使用系统临时文件验证四字段解析、缺失元数据和冲突检测, 不启动资源提取器, 也不访问正式帧元数据:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/extract_effect_animation.ps1' -SelfTest
```
