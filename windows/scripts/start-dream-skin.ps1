[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$RestartExisting,
  [string]$ProfilePath,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
$SkillRoot = Split-Path -Parent $PSScriptRoot
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$StatePath = Join-Path $StateRoot 'state.json'
$StdoutPath = Join-Path $StateRoot 'injector.log'
$StderrPath = Join-Path $StateRoot 'injector-error.log'
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

$nodeRuntime = Resolve-NodeRuntime
$codexRuntime = Resolve-CodexRuntime
$node = $nodeRuntime.Path
$debugReady = Test-CodexDebugPort $Port
$mainProcesses = @(Get-OfficialCodexMainProcesses $codexRuntime.Executable | Where-Object { $_.MainWindowHandle -ne 0 })

if (-not $debugReady -and -not $ProfilePath -and $mainProcesses.Count -gt 0) {
  if (-not $RestartExisting) {
    throw "Codex is already running without dream-skin debugging on port $Port. Close Codex or rerun with -RestartExisting."
  }
  foreach ($process in $mainProcesses) { [void]$process.CloseMainWindow() }
  $closeDeadline = (Get-Date).AddSeconds(10)
  do {
    Start-Sleep -Milliseconds 250
    $remaining = @(Get-OfficialCodexMainProcesses $codexRuntime.Executable)
  } while ($remaining.Count -gt 0 -and (Get-Date) -lt $closeDeadline)
  if ($remaining.Count -gt 0) { $remaining | Stop-Process -Force }
  Start-Sleep -Milliseconds 600
}

if (-not (Test-CodexDebugPort $Port)) {
  $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
  if ($ProfilePath) {
    New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
    $arguments += "--user-data-dir=$ProfilePath"
  }
  Start-Process -FilePath $codexRuntime.Executable -ArgumentList $arguments
}

$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-CodexDebugPort $Port)) {
  if ((Get-Date) -ge $deadline) { throw "Codex did not expose CDP on port $Port within 30 seconds." }
  Start-Sleep -Milliseconds 400
}

if (Test-Path -LiteralPath $StatePath) {
  if (-not (Stop-RecordedInjectorSafely $StatePath)) {
    throw "Refusing to stop the recorded injector because its live process identity does not match $StatePath."
  }
  Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
}

if ($ForegroundInjector) {
  & $node $Injector --watch --port $Port
  exit $LASTEXITCODE
}

$injectorArgs = @("`"$Injector`"", '--watch', '--port', "$Port")
$daemon = Start-Process -FilePath $node -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
$daemonStart = $daemon.StartTime.ToUniversalTime().ToString('o')
@{
  schemaVersion = 2
  skinVersion = $DreamSkinVersion
  port = $Port
  injectorPid = $daemon.Id
  injectorStartedAt = $daemonStart
  nodePath = $node
  injectorPath = $Injector
  codexExecutable = $codexRuntime.Executable
  codexProductVersion = $codexRuntime.ProductVersion
  skillRoot = $SkillRoot
  profilePath = $ProfilePath
} | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8

$verified = $false
for ($attempt = 0; $attempt -lt 45; $attempt++) {
  Start-Sleep -Milliseconds 700
  & $node $Injector --verify --port $Port *> $null
  if ($LASTEXITCODE -eq 0) { $verified = $true; break }
}
if (-not $verified) {
  if (-not (Stop-RecordedInjectorSafely $StatePath)) {
    throw "Injection verification failed, and the recorded injector identity did not match $StatePath. Inspect it before retrying."
  }
  Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
  throw 'Dream skin launched but verification failed. The injector was stopped; see injector logs.'
}
Write-Host "Codex Dream Skin $DreamSkinVersion is active on loopback port $Port."
