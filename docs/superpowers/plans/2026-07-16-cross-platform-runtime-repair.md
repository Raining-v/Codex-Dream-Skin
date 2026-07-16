# Cross-platform Runtime Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the broken fresh-clone macOS theme and make the Windows launcher safely discover and control the official Codex Store app when Appx lookup is unavailable.

**Architecture:** Keep the existing loopback-CDP injection architecture. Centralize Windows runtime discovery and process identity in a dot-sourced PowerShell module, then make every Windows entry point consume that module while the JavaScript injector independently validates loopback debugger URLs and native Codex renderer markers.

**Tech Stack:** Bash, Node.js ES modules, PowerShell 5.1-compatible scripts, Chromium DevTools Protocol, TOML text preservation.

## Global Constraints

- Never modify official `.app`, `app.asar`, WindowsApps contents, or code signatures.
- Bind CDP to `127.0.0.1` only.
- Never change API keys, Base URLs, model providers, authentication, threads, pets, or plugins.
- Windows requires a global Node.js 20 or newer runtime.
- Do not launch or stop Codex from automated tests.

---

### Task 1: macOS fresh-clone regressions

**Files:**
- Modify: `macos/tests/run-tests.sh`
- Modify: `macos/assets/theme.json`
- Modify: `macos/VERSION`
- Modify: macOS runtime version constants and user-facing release documentation

**Interfaces:**
- Consumes: `injector.mjs --check-payload`, `theme-config.mjs install|restore`.
- Produces: a committed default theme whose image exists and a test that requires install to preserve `appearanceTheme`.

- [ ] Add a test that resolves `assets/theme.json.image` and requires a non-empty file.
- [ ] Run the payload check and confirm it fails on the missing `background-20260715-215040-40507.jpg`.
- [ ] Change the theme image to `portal-hero.png` and confirm the payload check passes.
- [ ] Replace the obsolete dark-theme assertion with a byte-for-byte unchanged-config assertion after install and restore.
- [ ] Bump macOS to `1.1.2` and synchronize changelog, QA, runtime notes, package metadata, client copy, and runtime constants.

### Task 2: Windows runtime discovery and process identity

**Files:**
- Create: `windows/scripts/common-windows.ps1`
- Create: `windows/tests/run-tests.ps1`
- Modify: `windows/scripts/install-dream-skin.ps1`
- Modify: `windows/scripts/start-dream-skin.ps1`
- Modify: `windows/scripts/verify-dream-skin.ps1`
- Modify: `windows/scripts/restore-dream-skin.ps1`

**Interfaces:**
- Produces: `Resolve-CodexRuntime`, `Resolve-NodeRuntime`, `Get-OfficialCodexMainProcesses`, `Test-CodexDebugPort`, `Stop-RecordedInjectorSafely`.
- Consumes: PowerShell Appx cmdlets, `Get-Process`, file version metadata, process creation time and executable paths.

- [ ] Write isolated tests with fake package directories and dependency-injection parameters for package/process candidates.
- [ ] Run tests and confirm discovery fallback, loopback launch flags, and stale-PID identity assertions fail because the shared functions do not yet exist.
- [ ] Implement the smallest shared runtime functions needed to pass those tests.
- [ ] Update all entry points to dot-source the module and consume the validated runtime/state functions.
- [ ] Re-run the Windows test suite and parser checks.

### Task 3: Windows CDP target validation

**Files:**
- Modify: `windows/scripts/injector.mjs`
- Test: `windows/tests/run-tests.ps1`

**Interfaces:**
- Produces: `--check-payload` mode and validated loopback WebSocket/renderer target selection.
- Consumes: the existing CSS, renderer payload, and `dream-reference.png`.

- [ ] Add tests requiring `--check-payload` to succeed without a running Codex session and requiring source-level loopback/renderer probe guards.
- [ ] Run tests and confirm the missing mode/guards fail.
- [ ] Implement payload check mode, debugger URL validation, and a native-shell probe before injection.
- [ ] Re-run payload, JavaScript syntax, and Windows tests.

### Task 4: Windows release documentation

**Files:**
- Create: `windows/VERSION`
- Create: `windows/CHANGELOG.md`
- Modify: `windows/SKILL.md`
- Modify: `windows/references/runtime-notes.md`
- Modify: `windows/references/qa-inventory.md`
- Modify: `docs/platforms.md`
- Modify: root README files when requirements text changes

**Interfaces:**
- Produces: accurate Node, discovery, CDP, verification, rollback, and version instructions.

- [ ] Document Node.js 20+, fallback discovery, explicit loopback binding, and identity-safe restore.
- [ ] Record Windows `1.0.1` user-facing fixes and macOS `1.1.2` fixes.
- [ ] Check all version references and internal documentation links.

### Task 5: final verification and commit

**Files:**
- Verify all modified files.

**Interfaces:**
- Consumes: all platform test and static-check entry points.
- Produces: one intentional Git commit containing the approved repair.

- [ ] Run `powershell -NoProfile -File windows/tests/run-tests.ps1`.
- [ ] Run Node syntax checks for all `.js` and `.mjs` files.
- [ ] Run `node macos/scripts/injector.mjs --check-payload` and `node windows/scripts/injector.mjs --check-payload`.
- [ ] Run PowerShell parser checks for every `.ps1` file.
- [ ] Run `git diff --check` and review `git diff --stat` plus the complete diff.
- [ ] Stage only the approved files and commit with a descriptive message.
