---
name: sa-server-deploy-docker-manual
description: 按 SA 服务端 README 本地重建并部署四个业务服务的 1 号 Docker 实例, 包含目标旧容器、dev 镜像和业务日志清理. 用于明确的本地手动部署请求. 查看日志、状态或单服务任务仅处理指定范围, 不操作基础组件或 2 号实例.
---

# sa server Docker Deploy 手动模式

## 范围

只处理当前 `server` 仓库的四个 Docker 业务服务:

- `cache.1`
- `online.1`
- `gateway.1`
- `login.1`

默认部署目标是以上全部 1 号实例. 不部署 2 号实例, 不使用 GHCR 镜像, 不处理 `bin` 本地二进制部署, 不创建、删除或重建 Redis、etcd、Docker 卷、网络和基础组件容器.

如果用户只要求查看日志、验证或操作单个服务, 只执行明确要求的范围. 只有用户要求部署或全新部署时, 才执行完整手动部署闭环.

## 工程和文档来源

按以下顺序解析工程根目录:

1. 使用用户明确提供的 `server` 路径.
2. 检查当前目录或聚合工作区的 `server/` 是否包含四个服务的 `deploy/<service>/README.md`; 从服务端子目录启动时, 可通过 `git rev-parse --show-toplevel` 定位并检查.
3. 只有未找到或存在多个候选时才询问工程根目录, 不要求聚合工作区本身必须是 Git 仓库.

执行部署前读取 [references/project-layout.md](references/project-layout.md), 再完整读取以下实际工程文件:

- `deploy/cache/README.md`、`cache.1.yaml`、`Dockerfile`
- `deploy/online/README.md`、`online.1.yaml`、`Dockerfile`
- `deploy/gateway/README.md`、`gateway.1.yaml`、`Dockerfile`
- `deploy/login/README.md`、`login.1.yaml`、`Dockerfile`

镜像名、容器名、端口和挂载参数以各 README 的“方式一: 本地手动构建镜像”和“启动 <service>.1”为准. 不把这些易变化参数复制到技能中, 也不从 2 号实例或历史命令推断.

所有命令使用 Git Bash 执行.

## 默认完整部署流程

严格按以下顺序执行. 完成所有只读检查后才能开始删除或清理.

### 1. 只读预检

1. 确认四份 README、四个 `Dockerfile` 和四个 `<service>.1.yaml` 都存在.
2. 从 README 提取四个本地 dev 镜像名及 1 号容器的完整 `docker run` 命令.
3. 对照 YAML 检查监听端口、Redis 地址、etcd endpoints 和宿主机 IP.
4. 检查 Docker daemon、现有目标容器、目标本地镜像、端口占用以及 Redis/etcd 可用性.
5. 确认计划中只包含 `server.cache.1`、`server.online.1`、`server.gateway.1`、`server.login.1` 和对应 `server.<service>:dev` 镜像.

发现配置、README 或实际状态不一致时, 在发生外部副作用前停止并向用户说明. 不临时改端口、配置或容器名来绕过问题.

### 2. 移除旧 1 号业务容器

依次停止并移除四个目标 1 号容器. 容器不存在时继续. 不操作任何 2 号实例、基础组件容器或无关容器.

显式调用本技能进行完整部署, 即表示用户已授权移除上述四个目标旧容器, 无需重复询问.

### 3. 移除旧本地业务镜像

移除四个 README 指定的 `server.<service>:dev` 本地镜像. 镜像不存在时继续. 不删除基础镜像、GHCR 镜像、构建缓存或无关镜像.

显式调用本技能进行完整部署, 即表示用户已授权移除上述四个目标旧本地镜像, 无需重复询问.

### 4. 清空遗留业务日志

在目标容器全部移除后, 创建并清空以下目录:

- `deploy/cache/log`
- `deploy/online/log`
- `deploy/gateway/log`
- `deploy/login/log`

清理前解析并检查每个绝对路径都位于当前工程根目录的 `deploy/<service>/log` 内. 只清理目录内容, 保留 `log` 目录本身. 不清理其他日志、数据目录或挂载目录.

显式调用本技能进行完整部署, 即表示用户已授权清空上述四个业务日志目录, 无需重复询问.

### 5. 本地构建四个镜像

逐个执行各服务 README“构建本地镜像”中的 `docker build` 命令. 使用当前工作区源码和默认 BuildKit 缓存, 不添加 `--no-cache`, 不拉取 GHCR 业务镜像.

如果构建需要联网拉取缺失的基础镜像或依赖, 先向用户说明并申请联网授权. 任一构建失败时立即停止, 直接报告失败, 不恢复旧镜像或改用 GHCR.

### 6. 启动每个服务的 1 号实例

四个镜像全部构建成功后, 按以下顺序执行各 README 中对应的“启动 <service>.1”命令:

1. `cache.1`
2. `online.1`
3. `gateway.1`
4. `login.1`

Docker bind mount 命令必须保留 README 中的 `MSYS_NO_PATHCONV=1` 和 `PROJECT_ROOT="$(pwd -W)"` 处理. 不启动 2 号实例.

每启动一个容器就确认它仍在运行. 任一服务启动失败时立即停止后续部署, 明确列出已成功、失败和尚未启动的服务, 不静默回滚或改用其他镜像.

### 7. 验证

按四份 README 的“验证”章节检查:

- 四个 1 号容器存在且保持运行.
- `docker logs` 没有启动失败、配置加载失败或依赖连接错误.
- cache、online、gateway 的 1 号 gRPC 服务可访问.
- login.1 的 HTTP 接口可访问.
- etcd 中的服务注册与本次部署一致.
- 2 号实例和基础组件未被修改.

验证失败视为部署失败. 保留现场并报告第一个可行动错误, 不删除新容器来掩盖问题.

## 安全边界

- 删除和清理只允许命中本节列出的四个 1 号容器、四个 dev 镜像和四个日志目录.
- 不使用宽泛名称匹配批量删除容器或镜像.
- 不运行 `docker system prune`、`docker image prune` 或 `docker volume prune`.
- 不删除 `deploy/redis.cluster/*/data`、`deploy/etcd.cluster/data` 或任何业务数据.
- 不修改 README、YAML、Dockerfile 或源码来让部署临时通过. 如果它们确实需要修改, 先说明原因、影响和同步文档方案并等待用户确认.
- 一旦开始外部副作用, 后续错误必须立即暴露. 不回退到旧容器、旧镜像或 GHCR 镜像.

## 结果汇报

最终按服务列出:

- 清理的旧容器、旧镜像和日志目录.
- 新镜像构建结果.
- 1 号容器名称、镜像、运行状态和端口.
- README 验证命令的结果.
- 未通过项和仍需用户处理的外部依赖.
