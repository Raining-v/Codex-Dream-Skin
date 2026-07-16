# Windows Changelog

## 1.0.1 — 2026-07-16

### 修复

- 当 `Get-AppxPackage` 查询不到 Codex 时，可从正在运行且通过受保护 WindowsApps 包路径与产品元数据校验的官方 Codex 恢复安装位置
- 启动 CDP 时显式绑定 `127.0.0.1`，并拒绝非回环 WebSocket 地址和不含 Codex 原生界面标记的渲染目标
- 启动、更新或恢复时不再只凭 PID 强制停止注入器；同时核对启动时间、Node 路径、脚本路径与命令行，避免 PID 复用误伤
- Verify / Restore 自动使用状态文件记录的实际端口

### 改进

- 增加 Node.js 20+ 的明确检查与错误提示
- 失败的启动验证会自动清理本次注入器
- 增加 Windows 隔离测试，覆盖运行时发现、回环 CDP、进程身份、载荷与 PowerShell 语法

### 说明

- 仍通过本机 CDP 外部注入，不修改 WindowsApps、`app.asar`、登录状态或模型/API 配置
