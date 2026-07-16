[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
$node = (Resolve-NodeRuntime).Path
$injector = Join-Path $PSScriptRoot 'injector.mjs'
$statePath = Join-Path (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin') 'state.json'
if (Test-Path -LiteralPath $statePath) {
  try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.port) { $Port = [int]$state.port }
  } catch {}
}
$arguments = @($injector, '--verify', '--port', "$Port")
if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
& $node @arguments
exit $LASTEXITCODE
