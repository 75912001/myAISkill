---
name: sa-pet-publish-sprite-sheet
description: 使用已打开的 TexturePacker 工程将宠物图片目录发布为 PNG 和 .tpsheet, 默认输出到 sa.desktop/assets/pet. 用于宠物图集发布或 sa.宠物.发布精灵表. 同目录带偏移打包使用通用打包流程, 角色骑宠批量发布使用专用流程.
---

# 宠物精灵表发布

本 Skill 保留宠物默认输出目录和用户入口, GUI 实现统一维护在同级 [sa-texturepacker-core](../sa-texturepacker-core/SKILL.md). `scripts/publish_pet_sprite_sheet.ps1` 只设置业务默认参数并转调基础脚本, 透传输出与退出码.

## 输入和固定环境

- 必须接收宠物精灵源文件夹的绝对路径.
- 只导入源文件夹顶层的全部普通文件, 不递归读取子文件夹.
- 任一普通文件不是 TexturePacker 支持的图片时, 列出文件并停止.
- 以源文件夹名称作为精灵名称 `<name>`.
- 只使用已经打开的 `C:\Program Files\CodeAndWeb\TexturePacker\bin\TexturePackerGUI.exe`.
- 只操作标题包含 `TexturePacker.tps` 的唯一工作窗口, 不启动新实例, 不打开新工程或新窗口.
- 固定工作工程为 `D:\src\github.com\sa.project\sa.desktop\TexturePacker.tps`.
- 默认输出为 `D:\src\github.com\sa.project\sa.desktop\assets\pet\<name>.tpsheet` 和 `<name>.png`; 内部复用时可通过 `-OutputDirectory` 指定其他已存在目录.
- 任一输出已存在时, 必须先获得用户明确的覆盖确认. 确认后才使用 `-Overwrite`.

## 发布

开始前提醒用户暂时不要操作 TexturePacker 窗口. 按当前环境要求从 Git Bash 调用 Windows PowerShell:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_pet_sprite_sheet.ps1' -SourceDirectory '<源文件夹绝对路径>'
```

用户已经明确确认覆盖时:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_pet_sprite_sheet.ps1' -SourceDirectory '<源文件夹绝对路径>' -Overwrite
```

旧入口仍接受显式输出目录以保留兼容性. 其他 Skill 应直接调用基础入口, 不再依赖宠物默认参数:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<core-skill-dir>/scripts/publish_sprite_sheet.ps1' -SourceDirectory '<源文件夹绝对路径>' -OutputDirectory '<输出目录绝对路径>' -Overwrite
```

基础脚本执行以下顺序, 宠物入口不复制 GUI 实现:

1. 校验源文件夹、全部顶层文件、固定工程和输出目录.
2. 找到当前唯一的 `TexturePacker.tps` 工作窗口.
3. 选中左侧全部精灵条目, 直接调用 TexturePacker 的“删除精灵”按钮; 禁止发送全局 `Delete`. 存在对话框或删除按钮未启用时立即停止; 虚拟列表仍有项目时重复, 直到列表为空. 只移除工程中的精灵条目, 不删除磁盘源文件.
4. 点击“添加精灵”, 在弹出的文件窗口进入源文件夹, 点击文件区域后执行 `Ctrl+A`, 再点击“打开”, 一次加入全部文件.
5. 把数据文件设置为输出目录中的 `<name>.tpsheet`.
6. 等待打包完成后调用“发布精灵表”.
7. 发布完成后如果出现结果弹窗, 只点击 `OK`、`确定` 或 `关闭`; 不接受许可证或未知确认.
8. 等待输出写入完成, 再验证 `.tpsheet`、PNG、纹理引用、精灵数量和精灵名称.
9. 发布成功后再次复用上述安全删除流程清空左侧精灵列表, 为下次调用保持空列表.
10. 输出两个 `OUTPUT_FILE=<绝对路径>` 和 `OUTPUT_FILE_COUNT=2`.

如果没有打开固定工作工程、找到多个同名工作窗口、GUI 控件无法唯一识别、出现非覆盖确认对话框或输出验证失败, 立即停止并暴露错误. 不启动其他 TexturePacker 进程, 不关闭或保存用户窗口, 不修改磁盘上的 `TexturePacker.tps`.

## 展示结果

成功后必须展示脚本返回的全部 `OUTPUT_FILE`:

- 为 `.tpsheet` 和 `.png` 分别提供可点击的绝对路径.
- 使用本地 Markdown 图片语法直接预览输出 PNG.
- 报告精灵名称、导入文件数、输出文件数, 以及左侧精灵列表已经清空.
- 不要只回复“发布成功”, 不要遗漏任一输出文件.
