# Project Layout Reference

本文件说明 `sa-server-deploy-docker-manual` 如何从实际 `server` 工程读取手动部署资料. 不在技能中保存工程绝对路径或复制端口、挂载和运行参数.

## 项目根目录

解析顺序:

1. 用户本轮明确提供的 `server` 路径.
2. 检查当前目录或聚合工作区的 `server/` 是否包含四个业务服务的部署 README. 从服务端子目录启动时, 可检查所在 Git 仓库根目录:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"
```

3. 使用唯一且通过入口检查的候选目录. 未找到或有多个候选时才询问; 聚合工作区自身不必是 Git 仓库.

## 本地手动部署来源

完整读取以下文件:

- `$PROJECT_ROOT/deploy/cache/README.md`
- `$PROJECT_ROOT/deploy/online/README.md`
- `$PROJECT_ROOT/deploy/gateway/README.md`
- `$PROJECT_ROOT/deploy/login/README.md`

每个服务只读取和执行:

- “清理日志”
- “方式一: 本地手动构建镜像”
- “构建本地镜像”
- “启动 <service>.1”
- “验证”中针对 1 号实例的命令

同时读取对应 `Dockerfile` 和 `<service>.1.yaml`, 用于校验 README 中的镜像名、容器名、端口、配置挂载和依赖地址.

不执行以下内容:

- “启动 <service>.2”和针对 2 号实例的验证命令.
- “方式二: 从 GHCR 获取镜像”.
- `deploy/redis.cluster` 或 `deploy/etcd.cluster` 的部署命令.
- `bin` 本地二进制部署流程.

## 路径约束

Git Bash 内使用 `$PROJECT_ROOT` 和仓库相对路径. Docker bind mount 需要 Windows 路径时, 在仓库根目录执行:

```bash
PROJECT_ROOT="$(pwd -W)"
```

日志清理前, 确认解析后的目标严格等于以下四个工程内目录之一:

```text
$PROJECT_ROOT/deploy/cache/log
$PROJECT_ROOT/deploy/online/log
$PROJECT_ROOT/deploy/gateway/log
$PROJECT_ROOT/deploy/login/log
```

不得通过通配服务名、父目录或计算结果未校验的路径执行递归删除.
