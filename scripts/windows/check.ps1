#requires -version 5.1
<#
.SYNOPSIS
    Diagnose the Windows prerequisites for building/running HGhub.

.DESCRIPTION
    Prints one line per requirement and an actionable fix for anything missing.
    Exit code is the number of missing prerequisites (0 = ready to build).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$problems = 0

function Pass([string]$Label, [string]$Detail) {
    Write-Host ("[ OK ] {0,-20} {1}" -f $Label, $Detail) -ForegroundColor Green
}
function Fail([string]$Label, [string]$Detail, [string]$Fix) {
    $script:problems++
    Write-Host ("[MISS] {0,-20} {1}" -f $Label, $Detail) -ForegroundColor Yellow
    Write-Host ("       fix: " + $Fix) -ForegroundColor Gray
}

Write-Host 'HGhub Windows prerequisite check' -ForegroundColor Cyan
Write-Host ''

# Windows 10 1809+ is required by the WebView2 runtime.
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int](($os.Version -split '\.')[2])
    if ($build -ge 17763) {
        Pass 'Windows' ("{0} (build {1})" -f $os.Caption, $build)
    } else {
        Fail 'Windows' ("build {0} is too old" -f $build) 'use Windows 10 1809 (17763) or later.'
    }
} catch {
    Pass 'Windows' 'version unknown'
}

# Node.js 20+ is enough; the project itself is tested with Node 22 LTS.
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $nv = (& node -v).Trim()
    $major = [int](($nv -replace '^v(\d+).*$', '$1'))
    if ($major -ge 20) {
        Pass 'Node.js' $nv
    } else {
        Fail 'Node.js' ("{0} is too old" -f $nv) 'winget install --id OpenJS.NodeJS.LTS -e'
    }
} else {
    Fail 'Node.js' 'not found' 'winget install --id OpenJS.NodeJS.LTS -e'
}

# pnpm 9+ understands this repo's lockfile (9.0); 10 is the pinned version.
$pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
if ($pnpm) {
    $pv = (& pnpm -v).Trim()
    $pmajor = [int](($pv -split '\.')[0])
    if ($pmajor -ge 9) {
        Pass 'pnpm' $pv
    } else {
        Fail 'pnpm' ("{0} is too old" -f $pv) 'corepack enable   (or: npm install -g pnpm@10)'
    }
} else {
    Fail 'pnpm' 'not found' 'corepack enable   (or: npm install -g pnpm@10)'
}

# Rust MSVC toolchain, 1.90+ per Cargo.toml's rust-version.
$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if ($cargo) {
    $cv = (& cargo -V).Trim()
    $rv = (& rustc -V).Trim()
    $m = [regex]::Match($rv, 'rustc (\d+)\.(\d+)')
    if ($m.Success -and ([int]$m.Groups[1].Value -gt 1 -or ([int]$m.Groups[1].Value -eq 1 -and [int]$m.Groups[2].Value -ge 90))) {
        Pass 'Rust' ($cv + ' / ' + $rv)
    } else {
        Fail 'Rust' ($rv + ' is too old') 'rustup update stable-msvc'
    }
} else {
    Fail 'Rust' 'not found' 'winget install --id Rustlang.Rustup -e ; rustup default stable-msvc'
}

# Visual Studio Build Tools with the C++ workload (provides link.exe + Windows SDK).
$vswhere = $null
if (${env:ProgramFiles(x86)}) {
    $vswhere = Join-Path -LiteralPath ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
}
$vsPath = $null
if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
}
if ($vsPath) {
    Pass 'MSVC build tools' $vsPath
} else {
    Fail 'MSVC build tools' 'C++ workload / link.exe not found' 'winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"'
}

# WebView2 runtime (preinstalled on Windows 11 and most Windows 10 machines).
$wvKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
)
$wv = $null
foreach ($key in $wvKeys) {
    if (Test-Path -LiteralPath $key) {
        $pv = (Get-ItemProperty -LiteralPath $key -Name 'pv' -ErrorAction SilentlyContinue).pv
        if ($pv) { $wv = $pv; break }
    }
}
if ($wv) {
    Pass 'WebView2 runtime' $wv
} else {
    Fail 'WebView2 runtime' 'not detected' 'install the Evergreen runtime: https://developer.microsoft.com/microsoft-edge/webview2/'
}

Write-Host ''
if ($problems -eq 0) {
    Write-Host 'Ready. Build with: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build.ps1' -ForegroundColor Green
} else {
    Write-Host ("{0} prerequisite(s) missing. Fix them, then run this check again." -f $problems) -ForegroundColor Yellow
}
exit $problems
