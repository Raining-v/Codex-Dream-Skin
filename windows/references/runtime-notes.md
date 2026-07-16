# Runtime notes

- The skin launches the Store-installed `ChatGPT.exe` with `--remote-debugging-address=127.0.0.1 --remote-debugging-port=<port>` and injects through CDP.
- Windows requires a global Node.js 20+ runtime. The Node copy inside WindowsApps may not be directly executable under normal package ACLs.
- The default production port is `9335`; test instances may use another port plus an isolated `--user-data-dir`.
- CDP is bound to loopback. Do not expose it on a LAN interface.
- The injector polls page targets and reinjects after document loads. In-page route changes use a debounced observer plus a low-frequency safety check to avoid CPU churn during streamed tasks.
- `%LOCALAPPDATA%\CodexDreamSkin\state.json` records the port plus injector PID, start time, Node path, injector path, Codex executable, and version. Logs stay in the same directory.
- If Codex is already running without the chosen debugging port, close it first or explicitly use `-RestartExisting`.
- Store updates are supported because the launcher queries `Get-AppxPackage OpenAI.Codex` on every launch. If that query is unavailable, it accepts a running executable only from the protected `%ProgramFiles%\WindowsApps\OpenAI.Codex_*__2p2nqsd0c76g0` path after validating its manifest and OpenAI/Codex file metadata.
