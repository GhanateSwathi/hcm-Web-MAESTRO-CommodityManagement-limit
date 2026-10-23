<#
.SYNOPSIS
    Runs the HCM workbench-ui Maestro suite and keeps every artifact under artifacts/.

.DESCRIPTION
    Reads .env from the project root and forwards each key to Maestro as -e KEY=VALUE.

    By default Maestro scatters a run across ~/.maestro/tests/<timestamp>/, which is
    awkward to find and easy to lose. This script redirects the whole run - report,
    takeScreenshot files, failure screenshots, hierarchy dumps and logs - into
    artifacts/<timestamp>/ inside the project instead.

    artifacts/ is gitignored, which matters more here than on most projects: the
    workbench-ui login form exposes the password as plain text in the view hierarchy,
    so the screen-hierarchy dumps this script collects can carry the secret in the
    clear. Keep them local; never commit them.

.EXAMPLE
    .\scripts\run.ps1
    Runs every flow under flows/, writes an HTML report.

.EXAMPLE
    .\scripts\run.ps1 -IncludeTags smoke -Headless

.EXAMPLE
    .\scripts\run.ps1 -Path flows/login/login-screen.yaml -Format JUNIT
#>
[CmdletBinding()]
param(
    # Flow file or folder to run. Defaults to the workspace root, which config.yaml
    # narrows to flows/** so nothing in subflows/ can execute on its own.
    [string] $Path = '.',

    [string[]] $IncludeTags,

    [string[]] $ExcludeTags,

    # NOOP runs the flows but writes no report file. Anything else writes one into
    # the run folder alongside the screenshots.
    [ValidateSet('HTML', 'HTML-DETAILED', 'JUNIT', 'NOOP')]
    [string] $Format = 'HTML',

    # Web only. Skips painting a visible browser window.
    [switch] $Headless,

    # Parent folder for per-run output.
    [string] $ArtifactRoot = 'artifacts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

# Reads the major version out of a JDK's `release` file. Cheaper and more reliable
# than shelling out to `java -version`, which writes to stderr and trips up
# PowerShell 5.1's native-command error handling.
function Get-JavaMajor {
    param([string] $JavaHome)

    if (-not $JavaHome) { return 0 }
    $release = Join-Path $JavaHome 'release'
    if (-not (Test-Path $release)) { return 0 }

    $line = Get-Content -LiteralPath $release |
        Where-Object { $_ -like 'JAVA_VERSION=*' } |
        Select-Object -First 1
    if (-not $line) { return 0 }

    $version = ($line -split '=', 2)[1].Trim('"')
    $parts = $version.Split('.')
    # Legacy scheme: 1.8.0_x means 8. Modern scheme: 17.0.20.1 means 17.
    if ($parts[0] -eq '1' -and $parts.Count -gt 1) { return [int] $parts[1] }
    return [int] $parts[0]
}

# Maestro 2.x refuses to start on anything below Java 17, and the error it prints
# ("Java 17 or higher is required") points at the JDK rather than at JAVA_HOME - so
# a stale JAVA_HOME reads as a missing install. This machine has JAVA_HOME on a
# JDK 11 while newer JDKs sit right beside it, so pick a usable one for this process
# only and leave the user's environment alone.
function Resolve-JavaHome {
    if ((Get-JavaMajor $env:JAVA_HOME) -ge 17) { return $env:JAVA_HOME }

    $roots = @(
        'C:\Program Files\Amazon Corretto'
        'C:\Program Files\Java'
        'C:\Program Files\Eclipse Adoptium'
        'C:\Program Files\Microsoft\jdk'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        # Newest first, so a later JDK upgrade is picked up without editing this list.
        $found = Get-ChildItem -LiteralPath $root -Directory |
            Sort-Object Name -Descending |
            Where-Object { (Get-JavaMajor $_.FullName) -ge 17 } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    return $null
}

# Minimal .env reader: KEY=VALUE, blank lines and # comments skipped, one optional
# layer of surrounding quotes stripped. Values are passed through verbatim otherwise,
# so a password containing '=' or '#' survives intact.
function Import-DotEnv {
    param([string] $File)

    $pairs = [ordered] @{}
    foreach ($raw in (Get-Content -LiteralPath $File)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        $split = $line.IndexOf('=')
        if ($split -lt 1) { continue }

        $key = $line.Substring(0, $split).Trim()
        $value = $line.Substring($split + 1).Trim()

        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        $pairs[$key] = $value
    }

    return $pairs
}

# --- preflight ---------------------------------------------------------------

if (-not (Get-Command maestro -ErrorAction SilentlyContinue)) {
    throw 'maestro was not found on PATH. Install it from https://maestro.dev and reopen the shell.'
}

$envFile = Join-Path $projectRoot '.env'
if (-not (Test-Path $envFile)) {
    throw ".env not found at $envFile. Copy .env.example to .env and fill in the values."
}

$envPairs = Import-DotEnv $envFile
if ($envPairs.Count -eq 0) {
    throw "No KEY=VALUE lines found in $envFile."
}

$javaHome = Resolve-JavaHome
if (-not $javaHome) {
    throw 'No JDK 17 or newer found. Maestro 2.x will not start without one.'
}
$env:JAVA_HOME = $javaHome

# --- build the run folder ----------------------------------------------------

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
# Join-Path would mangle an absolute -ArtifactRoot into 'C:\project\C:\elsewhere'.
$artifactBase = if ([System.IO.Path]::IsPathRooted($ArtifactRoot)) {
    $ArtifactRoot
} else {
    Join-Path $projectRoot $ArtifactRoot
}
$runDir = Join-Path $artifactBase $stamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

# --debug-output plus --flatten-debug-output drops a clean tree straight into
# $runDir. Two traps worth not rediscovering:
#   * --test-output-dir looks like the modern equivalent, but combining it with
#     --flatten-debug-output silently produces no output at all.
#   * without --flatten-debug-output, Maestro nests its own timestamp folder inside
#     the timestamped folder created just above.
$maestroArgs = @(
    'test'
    '--platform', 'web'
    '--debug-output', $runDir
    '--flatten-debug-output'
)

if ($Headless) { $maestroArgs += '--headless' }

$configFile = Join-Path $projectRoot 'config.yaml'
if (Test-Path $configFile) { $maestroArgs += @('--config', $configFile) }

$reportPath = $null
if ($Format -ne 'NOOP') {
    $extension = if ($Format -eq 'JUNIT') { 'xml' } else { 'html' }
    $reportPath = Join-Path $runDir "report.$extension"
    # --output will not create missing parent directories - it throws
    # FileNotFoundException instead. $runDir exists by now, so this is safe.
    $maestroArgs += @('--format', $Format, '--output', $reportPath)
}

if ($IncludeTags) { $maestroArgs += @('--include-tags', ($IncludeTags -join ',')) }
if ($ExcludeTags) { $maestroArgs += @('--exclude-tags', ($ExcludeTags -join ',')) }

foreach ($key in $envPairs.Keys) {
    $maestroArgs += @('-e', "$key=$($envPairs[$key])")
}

$maestroArgs += $Path

# --- run ---------------------------------------------------------------------

Write-Host "Run       : $stamp"
Write-Host "JAVA_HOME : $javaHome"
Write-Host "Flows     : $Path"
# Key names only. HCM_WEB_PASSWORD's value must not reach the console or a log.
Write-Host "Env       : $($envPairs.Keys -join ', ')"
Write-Host "Output    : $runDir"
Write-Host ''

Push-Location $projectRoot
try {
    & maestro @maestroArgs
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

# --- summarise ---------------------------------------------------------------

Write-Host ''
Write-Host "Artifacts kept in $runDir"

if ($reportPath -and (Test-Path $reportPath)) {
    Write-Host "  report      $reportPath"
}

$screenshots = @(Get-ChildItem -LiteralPath $runDir -Recurse -Filter '*.png' -File)
if ($screenshots.Count -gt 0) {
    Write-Host "  screenshots $($screenshots.Count) png under $runDir"
    foreach ($shot in $screenshots) {
        Write-Host "    $($shot.FullName.Substring($runDir.Length + 1))"
    }
}

exit $exitCode
