---
name: sa-make-texturepacker-sprite-sheet
description: 使用已打开的 TexturePacker 将 frameid PNG 目录打包为同目录 PNG 和 .tpsheet, 从正式四字段元数据注入偏移. 用于同目录带偏移打包或 sa.制作.texturepacker. 缺失元数据时发布前失败, 不补采或修改 offset.
---

# 制作 TexturePacker 精灵表

## 输入与固定环境

- 必须接收源文件夹绝对路径.
- 只处理源文件夹顶层的 `<正整数frameid>.png`, 不递归读取子文件夹.
- 允许存在上次生成的 `<文件夹名>.png` 和 `<文件夹名>.tpsheet`. 同名 PNG 必须经配套精灵表验证为图集后才能排除和替换; 其他普通文件均视为非法输入.
- 允许正整数文件夹名. 同名 PNG 缺少有效配套精灵表或与其中的源帧编号冲突时停止, 不把可能的原始帧当作旧图集覆盖. 验证包括单纹理引用、PNG 格式和尺寸、唯一正整数帧号及区域边界; 无法验证的文件保留原样.
- 使用源文件夹名称 `<name>` 作为精灵表名称, 固定输出到源文件夹内的 `<name>.png` 和 `<name>.tpsheet`.
- 固定偏移文件为 `D:\src\github.com\sa.project\server\docs\offset.yaml`.
- 复用唯一已打开且标题包含 `TexturePacker.tps` 的 TexturePacker GUI, 不启动新实例或打开新工程.
- 固定覆盖同名输出. 发布前保留旧输出备份, 完成规范化和验证后才视为成功; 失败时恢复旧输出.

## 执行

本流程依赖 Python、已打开的 TexturePacker 和同级 [sa-texturepacker-core](../sa-texturepacker-core/SKILL.md). Python 只负责本流程的 tpsheet 规范化, 公共 GUI 发布不依赖 Python 或宠物 Skill. 正式偏移表始终只读. 开始 GUI 发布前提醒用户暂时不要操作 TexturePacker、鼠标和键盘. 从 Git Bash 调用 Windows PowerShell 5.1:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_texturepacker_sprite_sheet.ps1' -SourceDirectory '<源文件夹绝对路径>'
```

脚本固定执行以下流程:

1. 校验源文件夹、文件夹名和全部顶层普通文件. 先验证已有同名 PNG 的图集身份, 再排除输出并按源文件名解析、去重 frameid. 数字目录无同名 PNG 时正常接受.
2. 严格读取 `server/docs/offset.yaml` 的四字段元数据. 缺失任何 frameid 时列出全部缺失项并停止, 不启动偏移查询、不操作 GUI、不备份或替换输出.
3. 全部源帧元数据齐全后才开始发布. 缺失记录需要通过正式元数据维护流程补齐后重试; 不依据图片或仅有的 X/Y 猜测、补写正式记录.
4. 备份并移出已有输出后, 调用 `sa-texturepacker-core/scripts/publish_sprite_sheet.ps1`, 显式传入源目录和 `-OutputDirectory`, 发布到源文件夹并使用 `-Overwrite`.
5. 调用本技能的 `normalize_tpsheet.py`, 把帧名称改为整数 `frameid`, 从偏移文件写入 `offset: [x, y]`, 并保持每个 sprite 独占一行.
6. 验证 PNG 和 `.tpsheet` 非空、纹理引用、帧集合、偏移值及单行格式. 失败时恢复原输出; 原来没有输出时移除本次不完整输出.
7. 输出两个 `OUTPUT_FILE=<绝对路径>` 和 `OUTPUT_FILE_COUNT=2`.

出现非法文件、重复帧号、元数据缺失或非法、多个 TexturePacker 窗口、未知对话框、发布失败或格式验证失败时立即停止, 不猜测或推算偏移.

## 展示结果

仅在发布、规范化和最终校验全部通过后显示成功, 不把中间步骤成功当作整个任务成功. 终端成功提示使用绿色, 失败提示使用红色; 对话结果分别使用 `🟢 成功` 和 `🔴 失败`, 不依赖聊天正文的字体颜色支持.

失败时报告失败阶段、原因和旧输出恢复情况. 恢复失败时保留备份, 报告备份绝对路径和恢复错误, 不声称已恢复或继续清理备份.

成功后必须:

- 分别提供 `.tpsheet` 和 PNG 的可点击绝对路径, 并直接预览 PNG.
- 报告帧数、已有偏移数和输出文件数. 为兼容现有输出字段保留 `ADDED_OFFSET_COUNT=0`, 不表示执行过元数据补采.
- 报告 TexturePacker 左侧精灵列表已经清空.

## 开发验证

修改本技能后运行无 GUI 自检. PowerShell 自检使用隔离文件验证数字目录首次打包、有效旧图集重跑、同名源帧或无效图集拒绝, 以及缺失元数据在外部调用前失败, 且源帧、已有输出和元数据保持不变:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_texturepacker_sprite_sheet.ps1' -SelfTest
python '<skill-dir>/scripts/normalize_tpsheet.py' --self-test
```

备份恢复和状态颜色的无 GUI 回归测试:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/test_output_recovery.ps1'
```
