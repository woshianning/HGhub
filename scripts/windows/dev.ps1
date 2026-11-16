#requires -version 5.1
<#
.SYNOPSIS
    Start HGhub in development mode on Windows.

.DESCRIPTION
    Installs frontend dependencies when node_modules is missing, then runs the
    Tauri dev shell (Vite + Rust with hot reload).

.PARAMETER Web
    Only start the Vite dev server in the browser. Tauri APIs are unavailable in
    this mode, so it is only useful for pure UI/CSS work.
#>
[CmdletBinding()]
param([switch]$Web)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $root

if (-not (Test-Path -LiteralPath (Join-Path $root 'node_modules'))) {
    Write-Host '==> Installing frontend dependencies' -ForegroundColor Cyan
    & pnpm install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

if ($Web) {
    Write-Host '==> Starting Vite only (Tauri APIs are not available)' -ForegroundColor Cyan
    & pnpm dev
} else {
    Write-Host '==> Starting Tauri dev window' -ForegroundColor Cyan
    & pnpm tauri dev
}
exit $LASTEXITCODE
