# Project Layout Reference

本文件说明 `deploy` 技能如何引用实际工程。不要在技能中保存项目磁盘绝对路径；项目移动后，应通过当前上下文重新解析工程根目录。

## 项目根目录

解析顺序：

1. 用户本轮明确提供的项目路径。
2. 当前工作目录所在 Git 仓库根目录：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"
```

3. 如果不在目标仓库内，向用户询问工程根目录。

## 工程内部署引用

所有部署资料都从实际工程目录读取：

- Docker 部署：`$PROJECT_ROOT/deploy`
- 本地部署：`$PROJECT_ROOT/bin`
- 服务 Docker 文档：`$PROJECT_ROOT/deploy/<service>/README.md`
- Redis 文档：`$PROJECT_ROOT/deploy/redis.cluster/README.md`
- etcd 文档：`$PROJECT_ROOT/deploy/etcd.cluster/README.md`
- 本地部署文档：`$PROJECT_ROOT/bin/README.md`

## 路径写法

Git Bash 内优先使用 `$PROJECT_ROOT` 和相对路径。Docker bind mount 需要 Windows 路径时，在仓库根目录用：

```bash
PROJECT_ROOT_WIN="$(pwd -W)"
```

然后拼接：

```bash
"$PROJECT_ROOT_WIN/deploy/<service>/<service>.<n>.yaml"
"$PROJECT_ROOT_WIN/deploy/<service>/log"
```

## 读取要求

执行具体部署前，必须读取实际工程中的对应 README 和 YAML；不要只依赖本技能中的摘要。端口、镜像名、容器名、服务实例编号、Redis/etcd 地址均以实际工程文件为准。
