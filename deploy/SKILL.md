---
name: deploy
description: server 项目部署技能。用于处理当前 server 仓库的 Docker 部署、本地 bin 部署、部署配置检查、启动停止、日志查看、Redis/etcd 基础组件部署，以及 deploy 与 bin 目录相关的部署文档同步。
---

# Deploy

## 基本原则

使用本技能处理当前 `server` 仓库的部署任务。不要在技能中假定项目固定在某个磁盘路径；每次都先解析当前工程根目录。

项目根目录解析顺序：

1. 如果用户明确给出项目路径，使用用户给出的路径。
2. 否则在当前工作目录执行 `git rev-parse --show-toplevel`。
3. 如果当前目录不在目标仓库内，先询问用户项目根目录。

所有命令使用 Git Bash 执行。除非用户明确要求，不要执行会影响本机环境或运行实例的命令；涉及依赖安装、联网下载、权限提升、Docker 拉取镜像、删除数据目录、删除容器、清空日志或重建集群时，先征求用户确认。

部署资料以工程内实时文件为准，不在技能中复制运行配置：

- Docker 部署目录：`deploy`
- 本地部署目录：`bin`
- Docker 服务文档：`deploy/<service>/README.md`
- 基础组件文档：`deploy/redis.cluster/README.md`、`deploy/etcd.cluster/README.md`
- 本地部署说明：`bin/README.md`
- 工程引用说明：`references/project-layout.md`

需要确认目录结构、部署资料入口或本地/Docker 目录关系时，先读取 `references/project-layout.md`。

## 操作前检查

执行部署相关任务前先读取对应 README 和配置文件，确认端口、容器名、镜像名、挂载路径、etcd endpoints、Redis addrs 与当前目标一致。

优先检查：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"
find deploy -maxdepth 3 -type f | sort
find bin -maxdepth 1 -type f | sort
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

如果发现 README、配置文件或代码注释与实现不一致，先向用户列出差异并确认处理方案；代码修改后必须同步更新对应服务目录下的 `README.md`。

## Docker 部署

业务服务位于：

- `deploy/gateway`
- `deploy/online`
- `deploy/cache`
- `deploy/login`

每个服务通常包含：

- `Dockerfile`
- `<service>.1.yaml`、`<service>.2.yaml`
- `log/`
- `README.md`

Docker 部署优先按对应服务 README 执行。通用流程是：

1. 进入仓库根目录。
2. 确认或创建 `deploy/<service>/log`。
3. 本地构建镜像，或按 README 从 GHCR 拉取镜像。
4. 使用 `MSYS_NO_PATHCONV=1 docker run` 挂载实例配置和日志目录。
5. 用 `docker ps`、`docker logs`、`grpcurl` 或 `curl` 验证。

常见本地构建格式：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"
docker build -f deploy/<service>/Dockerfile -t server.<service>:dev .
```

常见本地镜像运行格式：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"
mkdir -p deploy/<service>/log
PROJECT_ROOT_WIN="$(pwd -W)"

MSYS_NO_PATHCONV=1 docker run -d --name server.<service>.<n> \
  -v "$PROJECT_ROOT_WIN/deploy/<service>/<service>.<n>.yaml:/app/config/<service>.yaml" \
  -v "$PROJECT_ROOT_WIN/deploy/<service>/log:/app/log" \
  server.<service>:dev
```

端口映射不要凭空推断，必须从对应 README 或 YAML 读取。

## 基础组件

Redis Cluster 位于 `deploy/redis.cluster`，etcd Cluster 位于 `deploy/etcd.cluster`。两者使用 Docker Compose 部署。

Redis 注意事项：

- 默认容器名：`redis-cluster`
- 默认密码：`111111`
- 客户端端口：`7000-7005`
- Cluster 总线端口：`17000-17005`
- 只重启已有集群时不要清理 `7000-7005/data`

etcd 注意事项：

- 默认节点：`etcd1`、`etcd2`、`etcd3`
- 客户端端口：`2379`、`22379`、`32379`
- Peer 端口：`2380`、`22380`、`32380`
- 只重启已有集群时不要清理 `data/`

跨 host 部署时，先确认宿主机 IP 是否变化。IP 变化会影响 Redis `cluster-announce-ip`、业务服务 `redis.addrs`、etcd `--advertise-client-urls` 和业务服务 `etcd.endpoints`。

## 本地 bin 部署

本地部署路径固定为当前项目根目录下的 `bin`，不要写死磁盘绝对路径。

该目录保存本地运行配置：

- `gateway.yaml`
- `online.yaml`
- `cache.yaml`
- `login.yaml`
- 对应 `.yaml.template`

本地运行前先确认二进制是否存在；如果不存在，再按服务源码构建到 `bin`。Windows/Git Bash 下常见构建格式：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"
go build -o bin/<service>.exe ./<service>
```

服务入口通过命令行参数读取配置文件路径。运行时传入 `bin` 下对应 YAML，建议用解析出的项目根目录拼接路径：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT/bin"
./<service>.exe "$PROJECT_ROOT/bin/<service>.yaml"
```

本地部署前确认依赖组件已可访问：

- `cache` 依赖 Redis Cluster。
- `gateway`、`online`、`login` 依赖 etcd 服务发现。
- `login` 还会访问 `cache` 和 `gateway`。

## 验证与排障

Docker 验证优先使用服务 README 中的命令。本地部署验证优先检查：

- 进程是否存在。
- `bin` 或配置指定日志目录中是否有错误日志。
- 配置文件中的监听端口是否被占用。
- Redis/etcd 地址是否可达。
- 服务是否已按预期注册到 etcd。

查看服务注册数据可参考：

```bash
docker exec etcd1 etcdctl --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 get /project/server/ --prefix
```

涉及删除数据、清理日志、重建 Redis/etcd 集群或删除容器时，先说明影响范围并等待用户确认。
