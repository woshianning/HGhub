#requires -version 5.1
<#
.SYNOPSIS
    One-click Windows build for HGhub (Tauri 2 desktop client).

.DESCRIPTION
    Checks the toolchain, installs frontend dependencies, runs the frontend and
    Rust release build, then collects the installer and a portable zip into
    <repo>\dist-windows\.

.PARAMETER Bundle
    Installer format to build: nsis (default) or msi.

.PARAMETER SkipInstall
    Skip "pnpm install" (use when node_modules is already up to date).

.PARAMETER Clean
    Run "cargo clean" first (removes all cached Rust build artifacts).

.PARAMETER NoPortable
    Do not create the portable zip.

.PARAMETER OutDir
    Output directory relative to the repository root. Default: dist-windows.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build.ps1 -Bundle msi -Clean
#>
[CmdletBinding()]
param(
    [ValidateSet('nsis', 'msi')]
    [string]$Bundle = 'nsis',
    [switch]$SkipInstall,
    [switch]$Clean,
    [switch]$NoPortable,
    [string]$OutDir = 'dist-windows'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $root

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note([string]$Message) { Write-Host "    $Message" -ForegroundColor Gray }
function Stop-Build([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

Write-Step 'Checking toolchain'
foreach ($tool in @('node', 'pnpm', 'cargo')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Stop-Build "$tool was not found on PATH. Run scripts\windows\check.ps1 and see docs/windows.md."
    }
}
Write-Note ("node  " + (& node -v))
Write-Note ("pnpm  " + (& pnpm -v))
Write-Note ("rustc " + (& rustc -V))

if (-not $SkipInstall) {
    Write-Step 'Installing frontend dependencies (pnpm install --frozen-lockfile)'
    & pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { Stop-Build 'pnpm install failed.' }
}

if ($Clean) {
    Write-Step 'Cleaning Rust build cache (cargo clean)'
    & cargo clean --manifest-path (Join-Path $root 'src-tauri\Cargo.toml')
    if ($LASTEXITCODE -ne 0) { Stop-Build 'cargo clean failed.' }
}

Write-Step "Building release bundle ($Bundle)"
& pnpm tauri build --bundles $Bundle
if ($LASTEXITCODE -ne 0) { Stop-Build 'tauri build failed.' }

$version = (Get-Content -LiteralPath (Join-Path $root 'src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json).version
$arch = if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$releaseDir = Join-Path $root 'src-tauri\target\release'
$out = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $out | Out-Null

$produced = New-Object System.Collections.Generic.List[string]

Write-Step 'Collecting installers'
$installerDirs = @()
if ($Bundle -eq 'msi') {
    $installerDirs += (Join-Path $releaseDir 'bundle\msi')
} else {
    $installerDirs += (Join-Path $releaseDir 'bundle\nsis')
}
$installers = @()
foreach ($dir in $installerDirs) {
    if (Test-Path -LiteralPath $dir) {
        $installers += Get-ChildItem -LiteralPath $dir -File |
            Where-Object { $_.Extension -eq '.exe' -or $_.Extension -eq '.msi' }
    }
}
foreach ($installer in $installers) {
    $dest = Join-Path $out ("HGhub_{0}_{1}-setup{2}" -f $version, $arch, $installer.Extension)
    Copy-Item -LiteralPath $installer.FullName -Destination $dest -Force
    $produced.Add($dest)
    Write-Note $dest
}
if ($installers.Count -eq 0) {
    Write-Note 'No installer found under src-tauri\target\release\bundle.'
}

if (-not $NoPortable) {
    Write-Step 'Building portable zip'
    $exe = @(
        (Join-Path $releaseDir 'HGhub.exe'),
        (Join-Path $releaseDir 'huangguo-client.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $exe) {
        $exe = Get-ChildItem -LiteralPath $releaseDir -File -Filter '*.exe' |
            Sort-Object Length -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $exe) { Stop-Build "Release executable not found under $releaseDir." }

    $portableExe = Join-Path $out 'HGhub.exe'
    Copy-Item -LiteralPath $exe -Destination $portableExe -Force
    $zip = Join-Path $out ("HGhub_{0}_{1}_portable.zip" -f $version, $arch)
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -LiteralPath $portableExe -DestinationPath $zip -CompressionLevel Optimal
    Remove-Item -LiteralPath $portableExe -Force
    $produced.Add($zip)
    Write-Note $zip
}

if ($produced.Count -eq 0) { Stop-Build 'Nothing was produced.' }

Write-Step 'Done'
foreach ($file in $produced) {
    $sizeMb = [math]::Round((Get-Item -LiteralPath $file).Length / 1MB, 1)
    Write-Host ("    {0}  ({1} MB)" -f $file, $sizeMb)
}
