[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Common = Join-Path $Root 'windows\scripts\common-windows.ps1'
$Injector = Join-Path $Root 'windows\scripts\injector.mjs'

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-False([bool]$Condition, [string]$Message) {
  if ($Condition) { throw "ASSERT FALSE FAILED: $Message" }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
  if ($Expected -ne $Actual) {
    throw "ASSERT EQUAL FAILED: $Message`nExpected: $Expected`nActual:   $Actual"
  }
}

Assert-True (Test-Path -LiteralPath $Common) 'shared Windows runtime module exists'
. $Common

$utf8Fixture = Join-Path ([System.IO.Path]::GetTempPath()) "dream-skin-utf8-$PID.toml"
try {
  $utf8Config = 'notify = [ "C:\\Users\\刘云飞\\AppData\\Local\\OpenAI\\Codex.exe", "turn-ended" ]' + "`n`n[desktop]`n"
  [System.IO.File]::WriteAllText($utf8Fixture, $utf8Config, (New-Object System.Text.UTF8Encoding($false)))
  $utf8Content = Read-Utf8TextFile -LiteralPath $utf8Fixture
  Assert-Equal $utf8Config $utf8Content 'BOM-less UTF-8 config with a Chinese user path is decoded without corruption'
  Write-Utf8TextFile -LiteralPath $utf8Fixture -Value ($utf8Content + 'appearanceTheme = "light"' + "`n")
  $utf8RoundTrip = [System.IO.File]::ReadAllText($utf8Fixture, (New-Object System.Text.UTF8Encoding($false, $true)))
  Assert-True ($utf8RoundTrip.Contains('C:\\Users\\刘云飞\\AppData')) 'UTF-8 config round trip preserves Chinese text and escaped path separators'
} finally {
  Remove-Item -LiteralPath $utf8Fixture -Force -ErrorAction SilentlyContinue
}

$nestedThemeConfig = @'
[desktop]
appearanceTheme = "system"
appearanceLightCodeThemeId = "codex"

[desktop.appearanceLightChromeTheme]
accent = "#0169cc"
contrast = 45
ink = "#0d0d0d"
opaqueWindows = false
surface = "#ffffff"
'@
$nestedThemeResult = Set-DreamSkinDesktopConfig -Content $nestedThemeConfig
Assert-Equal 0 ([regex]::Matches($nestedThemeResult, '(?m)^appearanceLightChromeTheme\s*=')).Count `
  'an existing nested light theme is not duplicated by an inline table'
Assert-True ($nestedThemeResult.Contains('appearanceTheme = "light"')) 'Dream Skin selects the light shell'
Assert-True ($nestedThemeResult.Contains('accent = "#B65CFF"')) 'nested light theme accent is updated'
Assert-True ($nestedThemeResult.Contains('code = "Cascadia Code"')) 'nested light theme code font is added'
Assert-True ($nestedThemeResult.Contains('ui = "Microsoft YaHei UI"')) 'nested light theme UI font is added'
$restoredNestedTheme = Restore-DreamSkinDesktopConfig -CurrentContent $nestedThemeResult -BackupContent $nestedThemeConfig
Assert-True ($restoredNestedTheme.Contains('appearanceTheme = "system"')) 'restore returns the original shell selection'
Assert-True ($restoredNestedTheme.Contains('accent = "#0169cc"')) 'restore returns the original nested accent'
Assert-False ($restoredNestedTheme.Contains('code = "Cascadia Code"')) 'restore removes a nested font absent from the backup'
Assert-False ($restoredNestedTheme.Contains('ui = "Microsoft YaHei UI"')) 'restore removes an added UI font absent from the backup'

$parentOnlyThemeConfig = @'
[desktop]
appearanceTheme = "system"

[desktop.appearanceLightChromeTheme]
accent = "#0169cc"
'@
$parentOnlyThemed = Set-DreamSkinDesktopConfig -Content $parentOnlyThemeConfig
$parentOnlyRestored = Restore-DreamSkinDesktopConfig -CurrentContent $parentOnlyThemed -BackupContent $parentOnlyThemeConfig
Assert-False ($parentOnlyRestored.Contains('[desktop.appearanceLightChromeTheme.fonts]')) `
  'restore removes an empty nested font table absent from the backup'
Assert-False ($parentOnlyRestored.Contains('[desktop.appearanceLightChromeTheme.semanticColors]')) `
  'restore removes an empty nested semantic color table absent from the backup'

$formattedNestedConfig = @'
[desktop]
  appearanceTheme = "system"

  [desktop.appearanceLightChromeTheme] # keep this user comment
  accent = "#0169cc"
  contrast = 45
'@
$formattedNestedResult = Set-DreamSkinDesktopConfig -Content $formattedNestedConfig
Assert-Equal 1 ([regex]::Matches($formattedNestedResult, '(?m)^\s*\[desktop\.appearanceLightChromeTheme\]')).Count `
  'an indented and commented table header is reused instead of duplicated'
Assert-Equal 1 ([regex]::Matches($formattedNestedResult, '(?m)^\s*accent\s*=')).Count `
  'an indented theme key is updated instead of duplicated'
Assert-True ($formattedNestedResult.Contains('accent = "#B65CFF"')) 'formatted nested theme receives the new accent'
Assert-Equal $formattedNestedResult (Set-DreamSkinDesktopConfig -Content $formattedNestedResult) `
  'theme transformation remains idempotent with indented keys and commented headers'

$packageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex_26.707.9981.0_x64__2p2nqsd0c76g0'
$officialExe = Join-Path $packageRoot 'app\ChatGPT.exe'
Assert-Equal $packageRoot (Get-CodexPackageRootFromExecutablePath -ExecutablePath $officialExe) 'official package path is parsed'
Assert-Equal '26.707.9981.0' (Get-CodexPackageVersionFromRoot -PackageRoot $packageRoot) 'Store package version is parsed from the package root'
Assert-Equal $null (Get-CodexPackageRootFromExecutablePath -ExecutablePath 'C:\Temp\ChatGPT.exe') 'arbitrary ChatGPT.exe is rejected'
$forgedExe = 'C:\Temp\WindowsApps\OpenAI.Codex_26.707.9981.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe'
Assert-Equal $null (Get-CodexPackageRootFromExecutablePath -ExecutablePath $forgedExe) 'lookalike WindowsApps directory outside Program Files is rejected'
Assert-Equal 'OpenAI.Codex_2p2nqsd0c76g0!App' `
  (Format-CodexApplicationUserModelId -PackageName 'OpenAI.Codex' -ApplicationId 'App') `
  'Codex AUMID is built from the manifest identity and publisher ID'
$launchArguments = Format-CodexLaunchArguments -Port 9335 -ProfilePath 'C:\Users\Demo User\Preview Profile'
Assert-Equal '--remote-debugging-address=127.0.0.1 --remote-debugging-port=9335 --user-data-dir="C:\Users\Demo User\Preview Profile"' `
  $launchArguments `
  'packaged activation arguments preserve a profile path containing spaces'
$trailingSlashArguments = Format-CodexLaunchArguments -Port 9335 -ProfilePath 'C:\Preview\'
Assert-Equal '--remote-debugging-address=127.0.0.1 --remote-debugging-port=9335 --user-data-dir="C:\Preview\\"' `
  $trailingSlashArguments `
  'packaged activation doubles trailing backslashes before a closing quote'

$selected = Resolve-CodexExecutableCandidate `
  -PackageCandidates @('C:\missing\ChatGPT.exe') `
  -ProcessCandidates @($officialExe) `
  -Validator { param($Path) $Path -eq $officialExe }
Assert-Equal $officialExe $selected 'running official process is used when Appx lookup has no valid result'

$nodeRuntime = Resolve-NodeRuntime
Assert-True (Test-Path -LiteralPath $nodeRuntime.Path -PathType Leaf) 'resolved Node.js path exists'
Assert-True ($nodeRuntime.Version -match '^v(?:2[0-9]|[3-9][0-9])\.') 'resolved Node.js version is 20 or newer'

Assert-True (Test-LoopbackDebuggerUrl -Url 'ws://127.0.0.1:9335/devtools/page/abc' -Port 9335) 'IPv4 loopback debugger URL is accepted'
Assert-True (Test-LoopbackDebuggerUrl -Url 'ws://localhost:9335/devtools/page/abc' -Port 9335) 'localhost debugger URL is accepted'
Assert-False (Test-LoopbackDebuggerUrl -Url 'ws://192.168.1.10:9335/devtools/page/abc' -Port 9335) 'LAN debugger URL is rejected'
Assert-False (Test-LoopbackDebuggerUrl -Url 'ws://127.0.0.1:9444/devtools/page/abc' -Port 9335) 'wrong debugger port is rejected'

$started = [DateTimeOffset]::Parse('2026-07-16T01:02:03.0000000+00:00')
$state = [PSCustomObject]@{
  injectorPid = 4321
  injectorStartedAt = $started.ToString('o')
  nodePath = 'D:\Node\node.exe'
  injectorPath = 'E:\DreamSkin\injector.mjs'
}
$matchingProcess = [PSCustomObject]@{
  Id = 4321
  StartTime = $started.LocalDateTime
  Path = 'D:\Node\node.exe'
  CommandLine = '"D:\Node\node.exe" "E:\DreamSkin\injector.mjs" --watch --port 9335'
}
Assert-True (Test-RecordedInjectorIdentity -State $state -Process $matchingProcess) 'matching injector identity is accepted'
$reusedProcess = $matchingProcess.PSObject.Copy()
$reusedProcess.StartTime = $started.AddMinutes(2).LocalDateTime
Assert-False (Test-RecordedInjectorIdentity -State $state -Process $reusedProcess) 'reused PID is rejected'
$foreignProcess = $matchingProcess.PSObject.Copy()
$foreignProcess.CommandLine = '"D:\Node\node.exe" C:\Temp\other.mjs --watch'
Assert-False (Test-RecordedInjectorIdentity -State $state -Process $foreignProcess) 'foreign Node command is rejected'

$stateFixture = Join-Path ([System.IO.Path]::GetTempPath()) "dream-skin-state-$PID.json"
try {
  $staleState = [PSCustomObject]@{
    injectorPid = 2147483000
    injectorStartedAt = $started.ToString('o')
    nodePath = 'D:\Node\node.exe'
    injectorPath = 'E:\DreamSkin\injector.mjs'
  }
  $staleState | ConvertTo-Json | Set-Content -LiteralPath $stateFixture -Encoding utf8
  Assert-True (Stop-RecordedInjectorSafely -StatePath $stateFixture) 'already-exited injector is safe to clear'

  $current = Get-Process -Id $PID
  $foreignState = [PSCustomObject]@{
    injectorPid = $PID
    injectorStartedAt = $current.StartTime.ToUniversalTime().ToString('o')
    nodePath = 'D:\Definitely-Not-PowerShell\node.exe'
    injectorPath = 'E:\DreamSkin\injector.mjs'
  }
  $foreignState | ConvertTo-Json | Set-Content -LiteralPath $stateFixture -Encoding utf8
  Assert-False (Stop-RecordedInjectorSafely -StatePath $stateFixture) 'identity mismatch refuses to stop a live process'
  Assert-True ([bool](Get-Process -Id $PID -ErrorAction SilentlyContinue)) 'identity mismatch leaves the live process untouched'
} finally {
  Remove-Item -LiteralPath $stateFixture -Force -ErrorAction SilentlyContinue
}

$startSource = Get-Content -LiteralPath (Join-Path $Root 'windows\scripts\start-dream-skin.ps1') -Raw
$commonSource = Get-Content -LiteralPath $Common -Raw
$injectorSource = Get-Content -LiteralPath $Injector -Raw
Assert-True ($commonSource.Contains('--remote-debugging-address=127.0.0.1')) 'launcher explicitly binds CDP to IPv4 loopback'
Assert-True ($startSource.Contains('Invoke-CodexApplicationActivation')) 'launcher uses packaged application activation'
Assert-False ($startSource.Contains('Start-Process -FilePath $codexRuntime.Executable')) 'launcher never directly executes the protected WindowsApps binary'
Assert-False ($injectorSource.Contains('innerText')) 'diagnostic probe never serializes renderer text content'

$node = (Get-Command node -ErrorAction Stop).Source
$payloadJson = & $node $Injector --check-payload
if ($LASTEXITCODE -ne 0) { throw 'Windows injector payload self-check failed.' }
$payload = $payloadJson | ConvertFrom-Json
Assert-True ([bool]$payload.pass) 'Windows payload self-check reports pass'
$releaseVersion = (Get-Content -LiteralPath (Join-Path $Root 'windows\VERSION') -Raw).Trim()
Assert-Equal $releaseVersion $DreamSkinVersion 'Windows VERSION and PowerShell runtime agree'
Assert-Equal $releaseVersion $payload.version 'Windows VERSION and injector agree'
$rendererSource = Get-Content -LiteralPath (Join-Path $Root 'windows\assets\renderer-inject.js') -Raw
Assert-True ($rendererSource.Contains("version: `"$releaseVersion`"")) 'Windows renderer payload uses release version'
Assert-True ([bool]$payload.security.loopbackDebuggerUrls) 'Windows payload checks loopback debugger URLs'
Assert-True ([bool]$payload.security.nativeRendererProbe) 'Windows payload checks native renderer markers'

$scripts = Get-ChildItem -LiteralPath (Join-Path $Root 'windows') -Recurse -File -Filter '*.ps1'
foreach ($script in $scripts) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
  Assert-Equal 0 $errors.Count "PowerShell syntax: $($script.FullName)"
}

Write-Host "PASS: Windows runtime, identity, loopback CDP, payload, and $($scripts.Count) PowerShell syntax checks."
