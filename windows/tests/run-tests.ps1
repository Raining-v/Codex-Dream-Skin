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

$packageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex_26.707.9981.0_x64__2p2nqsd0c76g0'
$officialExe = Join-Path $packageRoot 'app\ChatGPT.exe'
Assert-Equal $packageRoot (Get-CodexPackageRootFromExecutablePath -ExecutablePath $officialExe) 'official package path is parsed'
Assert-Equal '26.707.9981.0' (Get-CodexPackageVersionFromRoot -PackageRoot $packageRoot) 'Store package version is parsed from the package root'
Assert-Equal $null (Get-CodexPackageRootFromExecutablePath -ExecutablePath 'C:\Temp\ChatGPT.exe') 'arbitrary ChatGPT.exe is rejected'
$forgedExe = 'C:\Temp\WindowsApps\OpenAI.Codex_26.707.9981.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe'
Assert-Equal $null (Get-CodexPackageRootFromExecutablePath -ExecutablePath $forgedExe) 'lookalike WindowsApps directory outside Program Files is rejected'

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
Assert-True ($startSource.Contains('--remote-debugging-address=127.0.0.1')) 'launcher explicitly binds CDP to IPv4 loopback'

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
