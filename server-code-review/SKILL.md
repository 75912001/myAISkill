---
name: server-code-review
description: 严格后端服务器代码审查，用于发现 bug、回归、并发风险、数据一致性问题、RPC/API 契约问题、配置和部署风险、资源生命周期问题和缺失测试。Use when the user asks to review, audit, inspect, check a diff, check a PR, find bugs, assess risk, or evaluate Go backend services, gRPC, actor/concurrency, Redis, etcd, Docker, configuration, deployment, or distributed service changes.
---

# 后端服务器代码审查

## 审查姿态

以资深后端服务器工程师视角审查会影响生产的缺陷。优先关注正确性、回归、数据丢失、并发、数据一致性、RPC/API 契约、安全、可用性、配置、部署、资源生命周期、可观测性和测试缺口。

不要把风格意见放在前面，除非它会隐藏真实 bug 或维护风险。

默认使用用户的语言。用户用中文时，回复中文。

## 工作流程

1. 明确审查目标：变更文件、分支 diff、指定路径、粘贴代码或命令输出。
2. 判断前先阅读相关实现、调用链、测试、配置、RPC/proto/API 契约、生成代码和部署文档。
3. 检查是否存在用户或未提交改动。不要回滚或覆盖无关改动。
4. 先输出发现的问题，并按严重级别排序。
5. 审查本地文件时提供精确文件和行号。
6. 说明运行过的测试或命令。未运行时明确说明，并指出剩余风险。
7. 如果没有发现可行动问题，直接说明，并补充残余风险或缺失覆盖。

## 输出格式

使用以下结构：

```markdown
**Findings**
- [P1] 简短标题
  File: /absolute/path/file.go:123
  问题和影响。说明具体失败模式以及为什么会发生。
  建议修复方式。

**Tests**
- `command` passed/failed/not run.

**Notes**
- 可选：假设、剩余风险或后续检查。
```

严重级别：

- `P0`：数据丢失、安全问题、生产故障，或关键路径确定性崩溃。
- `P1`：高概率 bug、回归、竞态、协议违背、部署破坏，或严重缺失测试。
- `P2`：边界 bug、健壮性问题、可观测性缺口，或有具体影响的维护风险。
- `P3`：值得修复但不阻塞的小问题。

## 引用

只加载本次审查需要的引用：

- `references/review-checklist.md`：通用审查清单和 finding 质量标准。
- `references/go-backend-review.md`：Go、gRPC、actor/并发、错误处理和测试。
- `references/docker-redis-etcd-review.md`：Docker、Redis Cluster、etcd、配置、部署和运行时检查。
