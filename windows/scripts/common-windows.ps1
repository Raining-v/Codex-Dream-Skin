$DreamSkinVersion = '1.0.2'
$ExpectedPackagePublisherId = '2p2nqsd0c76g0'

function Read-Utf8TextFile {
  param([Parameter(Mandatory)][string]$LiteralPath)

  $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  return [System.IO.File]::ReadAllText($LiteralPath, $utf8)
}

function Write-Utf8TextFile {
  param(
    [Parameter(Mandatory)][string]$LiteralPath,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Value
  )

  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($LiteralPath, $Value, $utf8)
}

function Set-TomlSectionValue {
  param(
    [Parameter(Mandatory)][string]$Content,
    [Parameter(Mandatory)][string]$Section,
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$Value
  )

  $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $sectionPattern = "(?ms)^(?<header>[ \t]*\[$([regex]::Escape($Section))\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z))(?<body>.*?)(?=^[ \t]*\[|\z)"
  $sectionMatch = [regex]::Match($Content, $sectionPattern)
  if (-not $sectionMatch.Success) {
    $Content = $Content.TrimEnd() + "$newline$newline[$Section]$newline"
    $sectionMatch = [regex]::Match($Content, $sectionPattern)
  }
  $body = $sectionMatch.Groups['body'].Value
  $keyPattern = "(?m)^(?<indent>[ \t]*)$([regex]::Escape($Key))[ \t]*=[^\r\n]*$"
  $line = "$Key = $Value"
  if ([regex]::IsMatch($body, $keyPattern)) {
    $body = [regex]::Replace($body, $keyPattern, '${indent}' + $line, 1)
  } else {
    $body = $body.TrimEnd() + "$newline$line$newline"
  }
  return $Content.Substring(0, $sectionMatch.Groups['body'].Index) + $body +
    $Content.Substring($sectionMatch.Groups['body'].Index + $sectionMatch.Groups['body'].Length)
}

function Remove-TomlSectionValue {
  param(
    [Parameter(Mandatory)][string]$Content,
    [Parameter(Mandatory)][string]$Section,
    [Parameter(Mandatory)][string]$Key
  )

  $sectionPattern = "(?ms)^(?<header>[ \t]*\[$([regex]::Escape($Section))\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z))(?<body>.*?)(?=^[ \t]*\[|\z)"
  $sectionMatch = [regex]::Match($Content, $sectionPattern)
  if (-not $sectionMatch.Success) { return $Content }
  $body = [regex]::Replace(
    $sectionMatch.Groups['body'].Value,
    "(?m)^[ \t]*$([regex]::Escape($Key))[ \t]*=[^\r\n]*(?:\r?\n|$)",
    '',
    1
  )
  return $Content.Substring(0, $sectionMatch.Groups['body'].Index) + $body +
    $Content.Substring($sectionMatch.Groups['body'].Index + $sectionMatch.Groups['body'].Length)
}

function Set-DreamSkinDesktopConfig {
  param([Parameter(Mandatory)][string]$Content)

  $Content = Set-TomlSectionValue $Content 'desktop' 'appearanceTheme' '"light"'
  $Content = Set-TomlSectionValue $Content 'desktop' 'appearanceLightCodeThemeId' '"codex"'
  if ($Content -match '(?m)^[ \t]*\[desktop\.appearanceLightChromeTheme\][ \t]*(?:#[^\r\n]*)?$') {
    $Content = Remove-TomlSectionValue $Content 'desktop' 'appearanceLightChromeTheme'
    foreach ($entry in ([ordered]@{
      accent = '"#B65CFF"'; contrast = '64'; ink = '"#4A235F"'; opaqueWindows = 'true'; surface = '"#FFF4FA"'
    }).GetEnumerator()) {
      $Content = Set-TomlSectionValue $Content 'desktop.appearanceLightChromeTheme' $entry.Key $entry.Value
    }
    foreach ($entry in ([ordered]@{ code = '"Cascadia Code"'; ui = '"Microsoft YaHei UI"' }).GetEnumerator()) {
      $Content = Set-TomlSectionValue $Content 'desktop.appearanceLightChromeTheme.fonts' $entry.Key $entry.Value
    }
    foreach ($entry in ([ordered]@{ diffAdded = '"#BCE8CF"'; diffRemoved = '"#F7B8CE"'; skill = '"#C47BFF"' }).GetEnumerator()) {
      $Content = Set-TomlSectionValue $Content 'desktop.appearanceLightChromeTheme.semanticColors' $entry.Key $entry.Value
    }
  } else {
    $inlineTheme = '{ accent = "#B65CFF", contrast = 64, fonts = { code = "Cascadia Code", ui = "Microsoft YaHei UI" }, ink = "#4A235F", opaqueWindows = true, semanticColors = { diffAdded = "#BCE8CF", diffRemoved = "#F7B8CE", skill = "#C47BFF" }, surface = "#FFF4FA" }'
    $Content = Set-TomlSectionValue $Content 'desktop' 'appearanceLightChromeTheme' $inlineTheme
  }
  return $Content
}

function Get-TomlSectionValue {
  param(
    [Parameter(Mandatory)][string]$Content,
    [Parameter(Mandatory)][string]$Section,
    [Parameter(Mandatory)][string]$Key
  )

  $sectionPattern = "(?ms)^(?<header>[ \t]*\[$([regex]::Escape($Section))\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z))(?<body>.*?)(?=^[ \t]*\[|\z)"
  $sectionMatch = [regex]::Match($Content, $sectionPattern)
  if (-not $sectionMatch.Success) { return [PSCustomObject]@{ Found = $false; Value = $null } }
  $keyMatch = [regex]::Match(
    $sectionMatch.Groups['body'].Value,
    "(?m)^[ \t]*$([regex]::Escape($Key))[ \t]*=[ \t]*(?<value>[^\r\n]*)$"
  )
  if (-not $keyMatch.Success) { return [PSCustomObject]@{ Found = $false; Value = $null } }
  return [PSCustomObject]@{ Found = $true; Value = $keyMatch.Groups['value'].Value }
}

function Restore-TomlSectionValue {
  param(
    [Parameter(Mandatory)][string]$CurrentContent,
    [Parameter(Mandatory)][string]$BackupContent,
    [Parameter(Mandatory)][string]$Section,
    [Parameter(Mandatory)][string]$Key
  )

  $saved = Get-TomlSectionValue $BackupContent $Section $Key
  if ($saved.Found) {
    return Set-TomlSectionValue $CurrentContent $Section $Key $saved.Value
  }
  return Remove-TomlSectionValue $CurrentContent $Section $Key
}

function Remove-TomlSectionIfEmpty {
  param(
    [Parameter(Mandatory)][string]$Content,
    [Parameter(Mandatory)][string]$Section
  )

  $sectionPattern = "(?ms)^(?<section>[ \t]*\[$([regex]::Escape($Section))\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z)(?<body>.*?))(?=^[ \t]*\[|\z)"
  $sectionMatch = [regex]::Match($Content, $sectionPattern)
  if (-not $sectionMatch.Success) { return $Content }
  $meaningfulLines = @($sectionMatch.Groups['body'].Value -split '\r?\n' | Where-Object {
    $_.Trim() -and -not $_.TrimStart().StartsWith('#')
  })
  if ($meaningfulLines.Count -gt 0) { return $Content }
  $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
  return $Content.Remove($sectionMatch.Groups['section'].Index, $sectionMatch.Groups['section'].Length).TrimEnd() + $newline
}

function Restore-DreamSkinDesktopConfig {
  param(
    [Parameter(Mandatory)][string]$CurrentContent,
    [Parameter(Mandatory)][string]$BackupContent
  )

  foreach ($key in @('appearanceTheme', 'appearanceLightCodeThemeId', 'appearanceLightChromeTheme')) {
    $CurrentContent = Restore-TomlSectionValue $CurrentContent $BackupContent 'desktop' $key
  }
  if ($BackupContent -match '(?m)^[ \t]*\[desktop\.appearanceLightChromeTheme\][ \t]*(?:#[^\r\n]*)?$') {
    foreach ($key in @('accent', 'contrast', 'ink', 'opaqueWindows', 'surface')) {
      $CurrentContent = Restore-TomlSectionValue $CurrentContent $BackupContent 'desktop.appearanceLightChromeTheme' $key
    }
    foreach ($key in @('code', 'ui')) {
      $CurrentContent = Restore-TomlSectionValue $CurrentContent $BackupContent 'desktop.appearanceLightChromeTheme.fonts' $key
    }
    foreach ($key in @('diffAdded', 'diffRemoved', 'skill')) {
      $CurrentContent = Restore-TomlSectionValue $CurrentContent $BackupContent 'desktop.appearanceLightChromeTheme.semanticColors' $key
    }
    foreach ($section in @('desktop.appearanceLightChromeTheme.fonts', 'desktop.appearanceLightChromeTheme.semanticColors')) {
      if ($BackupContent -notmatch "(?m)^[ \t]*\[$([regex]::Escape($section))\][ \t]*(?:#[^\r\n]*)?$") {
        $CurrentContent = Remove-TomlSectionIfEmpty $CurrentContent $section
      }
    }
  }
  return $CurrentContent
}

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

function Format-CodexApplicationUserModelId {
  [CmdletBinding()]
  param(
    [string]$PackageName,
    [string]$ApplicationId
  )
  if ($PackageName -ne 'OpenAI.Codex') { throw "Unexpected Codex package identity: $PackageName" }
  if ($ApplicationId -notmatch '^[A-Za-z0-9.-]+$') { throw "Invalid Codex application ID: $ApplicationId" }
  return "${PackageName}_${ExpectedPackagePublisherId}!${ApplicationId}"
}

function Get-CodexApplicationUserModelId([string]$PackageRoot) {
  $manifestPath = Join-Path $PackageRoot 'AppxManifest.xml'
  try {
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
    $identityName = [string]$manifest.Package.Identity.Name
    $application = @($manifest.Package.Applications.Application) | Where-Object {
      ([string]$_.Executable).Replace('\', '/') -eq 'app/ChatGPT.exe'
    } | Select-Object -First 1
    if (-not $application) { throw 'The manifest has no Codex full-trust application entry.' }
    return Format-CodexApplicationUserModelId -PackageName $identityName -ApplicationId ([string]$application.Id)
  } catch {
    throw "Could not resolve the Codex application model ID from $manifestPath`: $($_.Exception.Message)"
  }
}

function Format-CodexLaunchArguments {
  [CmdletBinding()]
  param(
    [int]$Port,
    [string]$ProfilePath
  )
  if ($Port -lt 1024 -or $Port -gt 65535) { throw "Invalid CDP port: $Port" }
  $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
  if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
    if ($ProfilePath.Contains('"')) { throw 'The preview profile path cannot contain a double quote.' }
    $trailingBackslashes = [regex]::Match($ProfilePath, '\\+$').Value
    $quotedProfilePath = $ProfilePath + $trailingBackslashes
    $arguments += "--user-data-dir=`"$quotedProfilePath`""
  }
  return $arguments -join ' '
}

function Invoke-CodexApplicationActivation {
  [CmdletBinding()]
  param(
    [string]$ApplicationUserModelId,
    [string]$Arguments
  )

  if (-not ('CodexDreamSkin.Win32.AppActivator' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexDreamSkin.Win32 {
  [Flags]
  public enum ActivateOptions : uint {
    None = 0
  }

  [ComImport]
  [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IApplicationActivationManager {
    [PreserveSig]
    int ActivateApplication(
      [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
      [MarshalAs(UnmanagedType.LPWStr)] string arguments,
      ActivateOptions options,
      out uint processId);
  }

  [ComImport]
  [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
  class ApplicationActivationManager { }

  public static class AppActivator {
    public static uint Activate(string appUserModelId, string arguments) {
      var manager = (IApplicationActivationManager)new ApplicationActivationManager();
      uint processId;
      int result = manager.ActivateApplication(appUserModelId, arguments, ActivateOptions.None, out processId);
      if (result < 0) Marshal.ThrowExceptionForHR(result);
      return processId;
    }
  }
}
'@
  }

  return [CodexDreamSkin.Win32.AppActivator]::Activate($ApplicationUserModelId, $Arguments)
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
    ApplicationUserModelId = Get-CodexApplicationUserModelId $packageRoot
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
