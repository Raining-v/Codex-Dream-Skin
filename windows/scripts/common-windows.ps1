$DreamSkinVersion = '1.0.1'
$ExpectedPackagePublisherId = '2p2nqsd0c76g0'

function Get-NormalizedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  try {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
  } catch {
    return $null
  }
}

function Test-SamePath([string]$Left, [string]$Right) {
  $leftPath = Get-NormalizedPath $Left
  $rightPath = Get-NormalizedPath $Right
  if (-not $leftPath -or -not $rightPath) { return $false }
  return $leftPath.Equals($rightPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-CodexPackageRootFromExecutablePath([string]$ExecutablePath) {
  $normalized = Get-NormalizedPath $ExecutablePath
  if (-not $normalized) { return $null }
  $trustedWindowsApps = Get-NormalizedPath (Join-Path $env:ProgramFiles 'WindowsApps')
  if (-not $trustedWindowsApps) { return $null }
  $trustedPrefix = $trustedWindowsApps + [System.IO.Path]::DirectorySeparatorChar
  if (-not $normalized.StartsWith($trustedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
  $escapedPublisher = [regex]::Escape($ExpectedPackagePublisherId)
  $pattern = "(?i)^(?<root>.+[\\/]WindowsApps[\\/]OpenAI\.Codex_[^\\/]+__$escapedPublisher)[\\/]app[\\/]ChatGPT\.exe$"
  $match = [regex]::Match($normalized, $pattern)
  if (-not $match.Success) { return $null }
  return $match.Groups['root'].Value
}

function Get-CodexPackageVersionFromRoot([string]$PackageRoot) {
  $normalized = Get-NormalizedPath $PackageRoot
  if (-not $normalized) { return $null }
  $leaf = Split-Path -Leaf $normalized
  $match = [regex]::Match($leaf, '^OpenAI\.Codex_(?<version>\d+(?:\.\d+){3})_[^_]+__[^_]+$', 'IgnoreCase')
  if (-not $match.Success) { return $null }
  return $match.Groups['version'].Value
}

function Test-OfficialCodexExecutable([string]$ExecutablePath) {
  $packageRoot = Get-CodexPackageRootFromExecutablePath $ExecutablePath
  if (-not $packageRoot) { return $false }
  if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { return $false }
  if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'AppxManifest.xml') -PathType Leaf)) { return $false }
  try {
    $version = (Get-Item -LiteralPath $ExecutablePath -ErrorAction Stop).VersionInfo
    return $version.CompanyName -eq 'OpenAI OpCo, LLC' -and
      $version.ProductName -eq 'Codex' -and
      $version.FileDescription -eq 'Codex'
  } catch {
    return $false
  }
}

function Resolve-CodexExecutableCandidate {
  [CmdletBinding()]
  param(
    [string[]]$PackageCandidates = @(),
    [string[]]$ProcessCandidates = @(),
    [scriptblock]$Validator = { param($Path) Test-OfficialCodexExecutable $Path }
  )

  $seen = @{}
  foreach ($candidate in @($PackageCandidates) + @($ProcessCandidates)) {
    $normalized = Get-NormalizedPath $candidate
    if (-not $normalized -or $seen.ContainsKey($normalized.ToLowerInvariant())) { continue }
    $seen[$normalized.ToLowerInvariant()] = $true
    if (& $Validator $normalized) { return $normalized }
  }
  return $null
}

function Get-CodexExecutableCandidates {
  $packageCandidates = @()
  try {
    $packages = @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Sort-Object Version -Descending)
    foreach ($package in $packages) {
      if ($package.InstallLocation) {
        $packageCandidates += Join-Path $package.InstallLocation 'app\ChatGPT.exe'
      }
    }
  } catch {}

  $processCandidates = @()
  foreach ($process in @(Get-Process ChatGPT -ErrorAction SilentlyContinue)) {
    try {
      if ($process.Path) { $processCandidates += $process.Path }
    } catch {}
  }

  [PSCustomObject]@{
    PackageCandidates = $packageCandidates
    ProcessCandidates = $processCandidates
  }
}

function Resolve-CodexRuntime {
  [CmdletBinding()]
  param()

  $candidates = Get-CodexExecutableCandidates
  $executable = Resolve-CodexExecutableCandidate `
    -PackageCandidates $candidates.PackageCandidates `
    -ProcessCandidates $candidates.ProcessCandidates
  if (-not $executable) {
    throw 'Could not find a verified official Codex Store installation. Open Codex once, then retry so the launcher can validate its running executable.'
  }
  $packageRoot = Get-CodexPackageRootFromExecutablePath $executable
  $version = (Get-Item -LiteralPath $executable).VersionInfo
  [PSCustomObject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    ProductVersion = Get-CodexPackageVersionFromRoot $packageRoot
    FileVersion = $version.FileVersion
  }
}

function Resolve-NodeRuntime {
  [CmdletBinding()]
  param()

  $command = Get-Command node -ErrorAction SilentlyContinue
  if (-not $command) {
    throw 'Node.js 20 or newer is required on Windows. Install Node.js, reopen PowerShell, and retry.'
  }
  $versionText = (& $command.Source --version 2>$null | Select-Object -First 1)
  if ($versionText -notmatch '^v(?<major>\d+)\.') {
    throw "Could not validate the Node.js runtime at $($command.Source)."
  }
  if ([int]$Matches['major'] -lt 20) {
    throw "Node.js 20 or newer is required; found $versionText at $($command.Source)."
  }
  [PSCustomObject]@{
    Path = $command.Source
    Version = $versionText
  }
}

function Get-OfficialCodexMainProcesses([string]$ExecutablePath) {
  $matches = @()
  foreach ($process in @(Get-Process ChatGPT -ErrorAction SilentlyContinue)) {
    try {
      if ($process.Path -and (Test-SamePath $process.Path $ExecutablePath)) { $matches += $process }
    } catch {}
  }
  return $matches
}

function Test-LoopbackDebuggerUrl {
  [CmdletBinding()]
  param(
    [string]$Url,
    [int]$Port
  )
  try {
    $uri = [Uri]$Url
    if ($uri.Scheme -ne 'ws') { return $false }
    if ($uri.Port -ne $Port) { return $false }
    return @('127.0.0.1', 'localhost', '::1').Contains($uri.Host.ToLowerInvariant())
  } catch {
    return $false
  }
}

function Test-CodexDebugPort([int]$Port) {
  try {
    $targets = @(Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 1)
    return [bool]($targets | Where-Object {
      $_.type -eq 'page' -and $_.url -like 'app://*' -and
      (Test-LoopbackDebuggerUrl -Url $_.webSocketDebuggerUrl -Port $Port)
    })
  } catch {
    return $false
  }
}

function Get-ProcessIdentity([int]$ProcessId) {
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $process) { return $null }
  $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
  $path = $null
  try { $path = $process.Path } catch {}
  if (-not $path -and $cim) { $path = $cim.ExecutablePath }
  [PSCustomObject]@{
    Id = $process.Id
    StartTime = $process.StartTime
    Path = $path
    CommandLine = if ($cim) { $cim.CommandLine } else { $null }
  }
}

function Test-RecordedInjectorIdentity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$Process
  )

  if ([int]$State.injectorPid -ne [int]$Process.Id) { return $false }
  if (-not (Test-SamePath $State.nodePath $Process.Path)) { return $false }
  if ([string]::IsNullOrWhiteSpace([string]$State.injectorPath) -or
      [string]::IsNullOrWhiteSpace([string]$Process.CommandLine)) { return $false }
  if ($Process.CommandLine.IndexOf([string]$State.injectorPath, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
  if ($Process.CommandLine.IndexOf('--watch', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
  try {
    $saved = [DateTimeOffset]::Parse([string]$State.injectorStartedAt).ToUniversalTime()
    $actual = ([DateTimeOffset]$Process.StartTime).ToUniversalTime()
    if ([Math]::Abs(($saved - $actual).TotalSeconds) -ge 1) { return $false }
  } catch {
    return $false
  }
  return $true
}

function Stop-RecordedInjectorSafely([string]$StatePath) {
  if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $true }
  try {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if (-not $state.injectorPid) { return $true }
    $process = Get-ProcessIdentity -ProcessId ([int]$state.injectorPid)
    if (-not $process) { return $true }
    if (-not (Test-RecordedInjectorIdentity -State $state -Process $process)) { return $false }
    Stop-Process -Id ([int]$state.injectorPid) -Force -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}
