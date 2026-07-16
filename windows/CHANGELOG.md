# Windows Changelog

## 1.0.2 — 2026-07-16

### 修复

- 使用 Windows 应用激活 API 启动 Microsoft Store 版 Codex，避免直接执行受保护的 WindowsApps 程序时出现“拒绝访问”
- 配置文件始终按严格 UTF-8 读写，中文用户名或路径不再因 Windows PowerShell 5.1 的默认编码而损坏
- 已存在 `[desktop.appearanceLightChromeTheme]` 嵌套主题时原位更新字段，不再额外写入同名内联表导致 TOML 重复键
- 恢复基础主题时同步还原嵌套颜色、字体与语义色字段，不再残留 Dream Skin 外观设置
- 兼容带缩进键、表头尾注释和预览路径尾随反斜杠的合法 Windows 配置

### 改进

- 增加 `--probe` 诊断模式，仅输出结构标记，不记录项目名、任务文字或无障碍标签内容
- Windows 测试新增商店应用标识、带空格启动参数、无 BOM 中文 UTF-8 配置和嵌套主题幂等写入覆盖

### 说明

- 继续仅通过回环 CDP 外部注入，不修改 WindowsApps、`app.asar`、应用签名或模型/API 配置

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
