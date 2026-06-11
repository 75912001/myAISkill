# Docker、Redis 和 etcd 审查

## Docker 和运行时

- 检查 build context 和 Dockerfile 路径假设。
- 检查 volume mount、配置路径、日志路径、时区、暴露端口和 entrypoint 参数。
- 检查容器网络是否使用运行环境中可达的地址。
- 除非依赖在同一容器内，否则不要在容器里使用 `127.0.0.1` 访问依赖。
- 检查镜像变更是否需要重新创建容器，而不是只 restart。

## Redis Cluster

- 多 key 操作必须落同一 slot 时，检查 key 是否使用 hash tag。
- 检查 TTL 行为：避免部分写入后留下永久脏数据。
- 相关写入和过期时间必须一起生效时，使用 pipeline 或 Lua。
- 检查 cluster advertised addresses 是否对客户端可达。
- 避免频繁更新的大单值；需要细粒度更新时优先使用拆分 key/hash。
- 单独处理 `redis.Nil`，不要和后端故障混在一起。

## etcd

- 检查 `listen-client-urls` 和 `advertise-client-urls`。
- advertised client URLs 必须对服务客户端可达，而不只是容器内部可达。
- 检查 lease TTL 单位和 keepalive 生命周期。
- 检查服务注册值是否包含外部可达的 gRPC 地址。
- 检查 watch prefix 范围，避免处理无关服务事件。

## 部署配置

- 检查模板配置和实际配置是否同步。
- 分开检查本机、Docker 和跨机器地址。
- 检查凭据、端口和服务名是否匹配 docker compose 与运行时配置。

## 项目引用

审查 `D:\src\github.com\server` 时，使用仓库文档确认具体地址、端口、容器名和拓扑：

- `D:\src\github.com\server\docs\topology.md`
