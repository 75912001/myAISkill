---
name: sa-texturepacker-core
description: SA TexturePacker GUI 基础发布能力, 供宠物、通用图集和角色骑宠 Skill 复用. 接收明确的源目录和输出目录, 发布并验证 PNG 与 tpsheet. 用于维护公共发布能力或上层流程调用; 具体资源任务优先由对应业务 Skill 处理.
---

# SA TexturePacker 基础发布

## 职责与边界

本 Skill 是公共 GUI 发布实现的唯一维护位置. 业务 Skill 负责选择输入、输出、命名映射、覆盖授权和发布后的规范化, 再调用本脚本. 不反向依赖任何宠物或角色 Skill.

- 仅依赖 Windows PowerShell 5.1、Windows UI Automation、Win32 和已安装的 TexturePacker GUI. 基础发布不依赖 Python.
- 固定程序为 `C:\Program Files\CodeAndWeb\TexturePacker\bin\TexturePackerGUI.exe`.
- 复用唯一已打开且标题包含 `TexturePacker.tps` 的工作窗口, 工程为 `D:\src\github.com\sa.project\sa.desktop\TexturePacker.tps`.
- 不启动新实例, 不打开其他工程, 不保存或关闭用户工程.
- 不读取 offset.yaml, 不改写 frameid、offset 或业务配置. 这些工作由上层 Skill 完成.
- 同一 GUI 窗口必须串行调用. 发布前提醒用户暂停操作该窗口、鼠标和键盘.

## 调用契约

从 Git Bash 调用, 将路径替换为已解析的绝对路径:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<core-skill-dir>/scripts/publish_sprite_sheet.ps1' -SourceDirectory '<源目录>' -OutputDirectory '<输出目录>'
```

- `-SourceDirectory`: 必填, 已存在的目录. 只处理顶层图片, 不递归. 文件名去掉支持的图片扩展名后是精灵名称, 必须唯一.
- `-OutputDirectory`: 必填, 已存在的目录. 没有宠物或角色默认目录.
- 输出基名取源目录名称, 生成同名 `.png` 和 `.tpsheet`. 业务别名由调用者准备, 不在基础层解析角色配置.
- `-Overwrite`: 可选, 只有上层任务已授权覆盖时传入. 不传时拒绝已有输出.
- GUI 文件对话框会全选源目录. 同目录发布前, 调用者必须完成源帧与旧输出的区分, 并备份、移出旧输出; 基础层不处理数字目录的图集身份识别. 源目录中仍有目标输出时拒绝发布.
- 基础层不提供事务回滚. 需要备份恢复、续跑或多组资源一致性的业务流程继续由上层负责.

三个入口的分工:

| 上层 Skill | 保留职责 |
|---|---|
| sa-pet-publish-sprite-sheet | 默认宠物资产目录, 覆盖授权, 展示结果 |
| sa-make-texturepacker-sprite-sheet | 正整数帧名, 数字目录冲突检查, 同目录备份恢复, offset 规范化 |
| sa-character-mount-publish-sprite-sheet | 发布计划, 角色骑宠命名映射, 暂存与续跑, offset 规范化 |

## 公共发布流程

1. 校验程序、工程、目录、图片后缀、重复精灵名及输出覆盖条件.
2. 唯一定位工作窗口, 按现有对话框处理规则检查窗口状态.
3. 使用 TexturePacker 自身的删除精灵按钮清空列表, 不发送全局 Delete, 不删除磁盘源图.
4. 导入源目录全部顶层图片, 设置数据输出路径, 等待打包稳定后发布.
5. 按已有规则处理发布结果和已授权的覆盖对话框; 未知或失败状态停止并报告.
6. 验证输出非空、JSON 有效、单纹理引用、精灵数量和名称与输入一致.
7. 成功后清空 GUI 精灵列表, 返回全部输出文件. 失败可能留下部分输出或 GUI 精灵列表, 不宣称已完成清理或自动回滚.

退出码为 0 才表示成功. 标准输出保留这些可供调用者解析的记录:

```text
SPRITE_NAME=<名称>
SOURCE_FILE_COUNT=<数量>
GUI_PROCESS_ID=<进程号>
OUTPUT_FILE=<tpsheet绝对路径>
OUTPUT_FILE=<PNG绝对路径>
OUTPUT_FILE_COUNT=2
```

调用者必须检查退出码, 不能仅凭出现 OUTPUT_FILE 判断成功. 面向用户的入口应展示两个文件并预览 PNG.

## 开发验证

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<core-skill-dir>/scripts/publish_sprite_sheet.ps1' -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<core-skill-dir>/scripts/test_skill_callers.ps1'
```

SelfTest 只加载类型并使用隔离临时文件测试图片后缀、复合后缀、输出内容验证和文件变化检测, 不寻找或操作 GUI. 调用方测试在隔离 Skill 布局中使用替身验证宠物参数及退出码透传, 并检查三个入口的依赖路径和基础入口参数契约. 修改公共实现后同时运行通用打包的 SelfTest.

真实 GUI 发布需要适当的测试图片和用户窗口, 不以纯文件测试代替真实 GUI 验证.
