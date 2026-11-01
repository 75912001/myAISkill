---
name: sa-pet-lookup-frame-offsets
description: 查询 SA 独立 frameid 的图片偏移并只读校验已存在的四字段元数据, 不限宠物. 用于指定序号查询和帧偏移核对. 不采集完整动画, 不补写缺失 offset 或宽高, 元数据缺失时失败.
---

# 帧偏移查询

名称保留 sa-pet 前缀以兼容已有调用, 实际可查询任意合法独立 frameid. 本技能只有查询和只读校验职责, 不作为正式四字段元数据的补全入口.

## 输入与约束

- 接收一个或多个大于 0 且不重复的 frameid.
- 固定使用 `D:\软件\素材导出工具\石器时代资源提取器.exe`.
- 默认只读校验 `D:\src\github.com\sa.project\server\docs\offset.yaml`.
- 开始前提醒用户暂时不要操作鼠标和键盘.
- 必须运行 `scripts/lookup_frame_offsets.ps1`, 不要手写临时 UI 自动化、使用固定屏幕坐标或根据图片尺寸推算 offset.
- 本技能只查询独立 frameid 并校验正式帧元数据, 不生成 `<动画序号>.yaml`, 不修改 offset、`pet.sprite.yaml`、tpsheet 或客户端资源.

## 执行

从 Git Bash 调用 Windows PowerShell 5.1:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File '<skill-dir>/scripts/lookup_frame_offsets.ps1' \
  -FrameId 170984,171014,171044
```

脚本会:

1. 严格解析现有 `server/docs/offset.yaml`, 接受文件头注释, 并要求每项为 `[offsetX,offsetY,width,height]` 且 frameid 不重复.
2. 启动或连接资源提取器并关闭“自动播放帧”.
3. 将每个 frameid 写入 AutomationId `530` 的“指定序号”输入框.
4. 原生点击 AutomationId `540` 的“确定”按钮.
5. 交叉校验上方“序号”`450` 和输入框 `530` 都等于目标 frameid.
6. 连续读取两次一致的“图片偏移 X/Y”`400/370` 后才接受结果.
7. frameid 缺失或 X/Y 与正式元数据冲突时立即停止.
8. 全部 frameid 成功后返回查询结果和校验数量, 不写入任何文件.

可使用 `-OffsetPath` 指定另一份已存在的四字段帧元数据做隔离验证:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File '<skill-dir>/scripts/lookup_frame_offsets.ps1' \
  -FrameId 170984 \
  -OffsetPath 'D:\tmp\offset.yaml'
```

## 控件探测

控件 ID 失效时只运行探测模式:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File '<skill-dir>/scripts/lookup_frame_offsets.ps1' \
  -Probe
```

先报告控件差异并修正脚本, 不要绕过交叉校验或改用固定坐标.

## 失败处理与汇报

- 输入重复、frameid 非正数、控件缺失、点击后序号不一致、读数不稳定或 offset 冲突时立即停止.
- 任一查询失败时不修改帧元数据, 不保存部分结果.
- 帧元数据使用 UTF-8, 格式固定为 `frameid: [offsetX,offsetY,width,height]`, 不允许重复键.
- 成功后汇报请求数、采集数、校验数、元数据路径和每个查询结果.
