---
name: sa-character-mount-publish-sprite-sheet
description: 按角色和骑宠配置预览或批量发布 role_pet 图集, 输出到 sa.desktop/assets/character, 区分共享和颜色专属命名. 用于角色骑宠发布或 sa.角色骑宠.发布精灵表. 不用于角色动作采集、普通宠物发布或通用同目录打包.
---

# 角色骑宠精灵表发布

## 固定输入和输出

- 固定源根目录为 `D:\src\github.com\role_pet`.
- 固定角色配置为 `D:\src\github.com\sa.project\server\config\character.yaml`.
- 固定宠物配置为 `D:\src\github.com\sa.project\server\config\pet.yaml`.
- 固定偏移配置为 `D:\src\github.com\sa.project\server\docs\offset.yaml`.
- 固定 TexturePacker 工程为 `D:\src\github.com\sa.project\sa.desktop\TexturePacker.tps`.
- 固定输出目录为 `D:\src\github.com\sa.project\sa.desktop\assets\character`.
- 10 种共用骑宠的输出基名为 `<角色名称>.<骑宠名称>.<mounts[].petId>`.
- 颜色专属骑宠的输出基名为 `<角色名称>.<character[].id>.<骑宠名称>.<mounts[].petId>`.
- 同时生成同基名 `.png` 和 `.tpsheet`; 不生成只有 PNG 的不完整资源.
- `.tpsheet.textures[0].image` 必须等于最终 PNG 文件名; 每个 sprite 独占一行, 使用整数 `frameid` 并写入 `offset: [x, y]`.
- `mounts[].spriteId` 是骑乘角色帧动画组 ID, 只用于配置校验, 不作为文件名中的角色 ID 或骑宠 ID.

## 目录映射

源目录结构固定为 `<角色名称>/<骑宠目录>`.

- 带颜色的目录使用 `<中文颜色>.<虎|雷龙>` 格式. 把中文颜色映射到角色 `color`, 唯一选择同名角色配置, 再按 `老虎系` 或 `雷龙系` 唯一选择 mount, 生成一组输出.
- 不带颜色的目录名必须等于共用骑宠白名单和 `pet.yaml` 中的骑宠名称. 它必须在该角色每个颜色配置中唯一匹配同一个 `petId` 和 `spriteId`, 并只生成一组同名角色共用输出.
- 任一角色、颜色、宠物名称、系别、mount 或输出基名无法唯一映射时立即停止, 不猜测.
- 当前固定数据应由 216 个源目录生成 216 组输出, 其中 120 组是共用资源, 96 组是颜色专属资源. 数量变化时先报告差异, 经用户确认后再正式发布.

## 预览

正式发布前必须先运行无 GUI、无写入的计划预览:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_character_mount_sprite_sheets.ps1' -PlanOnly
```

可按角色或骑宠源目录筛选:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_character_mount_sprite_sheets.ps1' -PlanOnly -RoleName '吉米' -MountDirectoryName '红.虎'
```

预览必须报告源目录数、输出组数、映射错误、重复基名、已存在的完整输出和不完整输出.

## 发布

开始前提醒用户暂时不要操作 TexturePacker 窗口、鼠标和键盘. 只使用已经打开且标题包含 `TexturePacker.tps` 的唯一窗口, 不启动新实例.

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_character_mount_sprite_sheets.ps1'
```

用户明确确认覆盖后才允许:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '<skill-dir>/scripts/publish_character_mount_sprite_sheets.ps1' -Overwrite
```

脚本固定执行以下流程:

1. 调用 `build_publish_plan.py` 解析 YAML 与源目录, 生成并验证完整发布计划.
2. 按源目录串行处理, 不并行操作同一个 TexturePacker 窗口.
3. 每个源目录只调用一次 TexturePacker, 每个源目录只生成一组最终资源.
4. 调用同级 [sa-texturepacker-core](../sa-texturepacker-core/SKILL.md) 的 `scripts/publish_sprite_sheet.ps1` 完成 GUI 发布, 显式传入源目录连接和输出目录. 保留现有 `assets/pet` 暂存与验证后移入 `assets/character` 的流程, 不依赖宠物发布 Skill.
5. 使用临时目录连接让原脚本获得目标输出基名; 不复制、移动或删除源图片.
6. 使用 `normalize_tpsheet.py` 把帧名转换为整数 `frameid`, 从 `offset.yaml` 写入偏移, 保持每个 sprite 独占一行, 并把 `textures[0].image` 改成最终 PNG 文件名.
7. 把验证通过的临时输出移动到 `assets/character`, 再验证同基名 PNG、`.tpsheet`、纹理引用、精灵数量、帧号、偏移和单行格式.
8. 已存在且验证完整的输出视为可续跑结果并跳过. 单边缺失或验证失败的输出立即停止; 只有 `-Overwrite` 才允许替换.
9. 任一源目录失败时立即停止, 保留此前已经验证成功的输出, 报告准确进度以便续跑.
10. 成功或失败后都移除本次创建的临时目录连接, 不在项目中留下缓存和绝对路径配置.

## 输出和边界

- 成功后报告源目录数、生成组数、复用组数、跳过组数和全部输出路径.
- PNG 与 `.tpsheet` 都必须非空, `.tpsheet` 必须是有效 JSON、只引用对应 PNG, 且 `frameid` 与源文件名一致、每帧 offset 完整.
- 不修改 `TexturePacker.tps`, 不关闭或保存用户窗口, 不修改 `character.yaml`、`pet.yaml` 或角色动作配置.
- 本技能只发布资产. 客户端按三段名建立同名角色共用池、按四段名建立颜色专属池, 初始化时为每个角色装配完整 `petId -> MountResource` 索引.
