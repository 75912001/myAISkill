# Go 后端审查

## Go 正确性

- 检查 nil 路径、零值、map 初始化、slice 越界、整数转换和时间单位转换。
- 检查是否返回 typed nil interface，或丢失 sentinel error。
- 检查 public 函数输入校验是否与调用方和 proto/API 契约一致。
- 检查注释、命名和行为是否冲突；如需修改已有注释，遵循项目规则。

## 错误处理和 gRPC

- 将内部错误映射为合适的 gRPC status code。
- 不要把服务端失败返回为 `InvalidArgument`。
- 保留有用错误上下文，但不要泄露敏感信息。
- unary handler 要明确错误是用 gRPC error 表达，还是用 response 字段表达；不要混用语义。
- 检查 deadline/cancellation 传递和 context 使用。

## 并发和 Actor

- 需要顺序保证的 actor 消息必须走同一个 actor。
- 检查 sync 调用是否可能在调用方和被调用方共享 actor/event loop 时死锁。
- 检查断线、服务停止、stream 关闭和重试路径上的 goroutine/timer 清理。
- 检查 map 或 manager 访问是否有锁保护和陈旧指针竞态。

## 测试

- 优先为变更行为添加聚焦测试。
- handler 测试要覆盖非法输入、not found、后端错误和成功路径。
- 并发敏感代码尽量测试顺序假设。
- 配置解析测试默认值、显式值和非法值。
