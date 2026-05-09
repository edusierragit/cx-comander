param(
    [switch]$NoPathUpdate
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $RepoRoot "bin\cx.ps1"
$InstallDir = Join-Path $env:LOCALAPPDATA "cx-commander"
$ShimDir = Join-Path $env:APPDATA "npm"

if (-not (Test-Path -LiteralPath $Source)) {
    throw "No encontre bin\cx.ps1 en $RepoRoot"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null

Copy-Item -LiteralPath $Source -Destination (Join-Path $InstallDir "cx.ps1") -Force

$psShim = @"
& "$InstallDir\cx.ps1" @args
exit `$LASTEXITCODE
"@
[IO.File]::WriteAllText((Join-Path $ShimDir "cx.ps1"), $psShim, (New-Object System.Text.UTF8Encoding $false))

$cmdShim = @"
@echo off
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\cx-commander\cx.ps1" %*
"@
[IO.File]::WriteAllText((Join-Path $ShimDir "cx.cmd"), $cmdShim, (New-Object System.Text.UTF8Encoding $false))

if (-not $NoPathUpdate) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @($userPath -split ";" | Where-Object { $_ })
    if ($parts -notcontains $ShimDir) {
        $newPath = ($parts + $ShimDir) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = $env:Path + ";$ShimDir"
        Write-Host "Agregado al PATH de usuario: $ShimDir"
    }
}

Write-Host "cx commander instalado."
Write-Host "Abri una terminal nueva y proba: cx list"
