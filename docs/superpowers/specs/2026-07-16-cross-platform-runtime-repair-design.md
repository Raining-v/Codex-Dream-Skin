# Cross-platform runtime repair design

## Goal

Make a fresh clone internally consistent and make the Windows launcher find the official Codex Store installation even when `Get-AppxPackage OpenAI.Codex` is unavailable to the current process. Preserve the existing external-CDP model and do not modify Codex binaries, `app.asar`, authentication, threads, pets, plugins, or API provider settings.

## Scope

### macOS

- Point the bundled default theme at the committed `assets/portal-hero.png` file.
- Change the configuration round-trip test to assert that installation leaves the user's light/dark selection unchanged.
- Keep version constants and release-facing documentation synchronized at `1.1.2`.
- Correct runtime and QA notes that still describe the 1.0.0/launchd behavior.

### Windows

- Add a shared PowerShell runtime module used by install, start, verify, and restore scripts.
- Discover Codex in this order: Store package query, verified running `ChatGPT.exe` path, then fail with an actionable message.
- Accept a running-process path only when it is inside the protected `%ProgramFiles%\WindowsApps\OpenAI.Codex_*__2p2nqsd0c76g0` package directory, contains `AppxManifest.xml`, and the executable metadata identifies `OpenAI OpCo, LLC` / `Codex`.
- Continue using a global Node.js 20+ runtime because the Store package's internal Node is not directly executable under normal WindowsApps ACLs.
- Always launch CDP with both `--remote-debugging-address=127.0.0.1` and the selected port.
- Accept debugger targets only when the WebSocket URL is loopback-only and the renderer exposes expected Codex shell markers.
- Stop a recorded injector only after PID, start time, Node executable, and injector script path match the current process.
- Restore using the port recorded in state when available.
- Add an isolated PowerShell test suite that uses temporary fake package layouts and processes only; it must not launch or stop Codex.
- Establish Windows version `1.0.1` and a platform changelog.

## Data flow

1. `Resolve-CodexRuntime` returns a validated object containing package root, Codex executable, version, and Node path.
2. The start script checks whether a verified CDP endpoint already exists.
3. If Codex must restart, only validated official Codex main processes are closed or stopped.
4. The launcher opens the validated executable with loopback CDP flags.
5. The injector validates the debugger WebSocket and probes renderer DOM markers before applying CSS/DOM payloads.
6. State records enough injector identity to prevent stale-PID termination.
7. Restore reads state, stops only the matching injector, removes the live skin, and optionally restores appearance keys.

## Error handling

- Missing Codex: explain that the official Store installation must be opened once and that process discovery is the fallback.
- Missing/old Node: explain that Node.js 20+ is required on Windows and show the failing path/version.
- Untrusted executable path or metadata: reject it instead of launching an arbitrary `ChatGPT.exe`.
- Occupied or foreign CDP port: reject it; never inject into a renderer that fails loopback URL and Codex DOM probes.
- Stale PID: leave the unrelated process running and remove only stale state.

## Testing and acceptance

- RED/GREEN regression for the committed macOS default theme image.
- RED/GREEN regression for preserving `appearanceTheme = "system"` during macOS install/restore.
- PowerShell tests for package-path parsing, executable metadata validation hooks, discovery fallback ordering, Node version validation, loopback arguments, and stale-PID rejection.
- JavaScript syntax and payload checks on Windows.
- PowerShell parser checks for every Windows script.
- Fresh `git diff --check` and clean staged scope before commit.
- Live macOS signature/CDP tests remain a macOS-only acceptance step; Windows live launch is not part of automated tests because it would restart the user's active Codex session.

## Non-goals

- No redesign of the visual theme.
- No importing README gallery composites as theme backgrounds.
- No API key, Base URL, model provider, login, or user-data migration changes.
- No modification of files under WindowsApps or inside the official macOS application bundle.
