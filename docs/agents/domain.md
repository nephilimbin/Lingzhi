# Domain Docs

本仓库使用多上下文布局，每个主要模块有独立的领域文档。

## 上下文映射

参见仓库根目录的 `CONTEXT-MAP.md`，其中定义了所有上下文的位置。

## 当前上下文

1. **App (Flutter)** - `app/CONTEXT.md`
   - 移动端应用架构
   - Clean Architecture
   - Riverpod 状态管理
   - WebRTC 集成

2. **Server (Python)** - `server/CONTEXT.md`
   - FastAPI 后端架构
   - 依赖注入容器
   - WebSocket 通信
   - MCP 服务集成

## ADR 位置

架构决策记录存放在各上下文目录下的 `docs/adr/` 中：

- `app/docs/adr/` - 前端架构决策
- `server/docs/adr/` - 后端架构决策

## 技能使用

- `improve-codebase-architecture` - 读取当前模块的 CONTEXT.md
- `diagnose` - 使用领域语言理解问题
- `tdd` - 遵循模块特定的测试规范
