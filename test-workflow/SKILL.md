---
name: test-workflow
description: 通用测试流程，用于规划、运行、排查和汇报代码测试与构建验证。Use when Codex needs to validate code changes, choose appropriate test commands, investigate failing tests, run build checks, or summarize verification results across Go, JavaScript/TypeScript, Python, Rust, or similar repositories.
---

# 测试流程

## 目标

使用这个 skill 选择、运行、解释和汇报测试。默认先做最小可靠范围验证，再按变更风险扩大范围。

## 工作流程

1. 运行命令前先读取项目说明和测试入口。
   - 检查 `AGENTS.md`、`README*`、`Makefile`、`go.mod`、`package.json`、`pyproject.toml`、`Cargo.toml`、CI 配置和 scripts 目录。
   - 优先使用仓库文档中已有的测试命令，不要直接套通用默认命令。

2. 先选择最小但有效的验证范围。
   - 聚焦改动先跑 touched package/module 的测试。
   - 如果改动涉及公共 API、共享库、协议、生成代码或跨服务调用，再跑依赖包测试或构建。
   - 只有在变更范围、项目约定或用户要求需要时，才跑全量测试。

3. 单独看待构建检查。
   - 如果项目有构建目标，并且改动涉及生成代码、二进制打包、类型检查或编译路径，测试后运行相关构建。
   - 默认缓存目录权限失败时，改用项目本地缓存。

4. 从第一个真实错误开始定位失败。
   - 区分代码错误、测试期望错误、缺依赖、网络/沙箱失败、权限问题和已有无关失败。
   - 不要为了让测试通过而跳过测试、删除断言、弱化检查或改变生产行为，除非用户明确要求。
   - 如果失败与本次改动无关，说明原因，并在可能时继续做更窄范围的相关验证。

5. 清晰汇报结果。
   - 列出执行过的命令以及通过/失败状态。
   - 失败时只摘要第一个可行动错误和受影响文件/包。
   - 明确说明没有运行的测试以及原因。
   - 不粘贴长日志，只引用定位问题所需的关键行。

## 命令选择

优先使用项目已有命令。如果项目没有明确命令，按生态选择：

- Go：`go test ./...`，或更窄的 `go test ./path/to/pkg`；构建用 `go build ./cmd-or-package`。
- Node：使用 `package.json` 中的脚本，例如 `npm test`、`npm run test`、`npm run build`、`pnpm test` 或 `yarn test`。
- Python：优先使用项目文档；否则使用 `pytest`、指定路径的 pytest，或已配置的 tox/nox 命令。
- Rust：使用 `cargo test`，必要时使用更窄的 package/test selector，并用 `cargo build` 做编译验证。

## 项目引用

在 `D:\src\github.com\server` 中工作时，先读 `references/server-services.md`，再读其中列出的受影响服务 `TEST.md` 文件。

## 完成标准

只有当所选测试/构建覆盖了本次变更风险，并且最终回复说明了通过项、失败项和剩余风险时，才认为验证完成。
