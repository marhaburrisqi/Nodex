# NODEX Windows PowerShell Installer
$ErrorActionPreference = "Stop"

function Write-Cyan ($text) { Write-Host $text -ForegroundColor Cyan }
function Write-Green ($text) { Write-Host $text -ForegroundColor Green }
function Write-Yellow ($text) { Write-Host $text -ForegroundColor Yellow }
function Write-Blue ($text) { Write-Host $text -ForegroundColor Blue }

Write-Cyan @"
 _  _   ___   ___   ___  __  __
| \| | / _ \ |   \ | __| \ \/ /
| .  || (_) || |) || _|   >  <
|_|\_| \___/ |___/ |___| /_/\_\

 Dynamic DNS Automation Tool
"@

$InstallDir = "$env:LOCALAPPDATA\Programs\nodex"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$RawUrl = "https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh"
$TargetScript = Join-Path $InstallDir "ddns.sh"
$TargetCmd = Join-Path $InstallDir "nodex.cmd"
$TargetModexCmd = Join-Path $InstallDir "modex.cmd"

Write-Green "[INSTALLER] Downloading NODEX..."
Invoke-WebRequest -Uri $RawUrl -OutFile $TargetScript

# Create CMD wrapper executable for Windows CMD / PowerShell
$CmdContent = @"
@echo off
if exist "%SystemRoot%\System32\bash.exe" (
    bash "%~dp0ddns.sh" %*
) else (
    sh "%~dp0ddns.sh" %*
)
"@

Set-Content -Path $TargetCmd -Value $CmdContent -Encoding ASCII
Set-Content -Path $TargetModexCmd -Value $CmdContent -Encoding ASCII

# Add to User PATH if not present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$InstallDir*") {
    Write-Yellow "[INSTALLER] Adding $InstallDir to User PATH environment variable..."
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
    $env:Path += ";$InstallDir"
}

Write-Blue "`n✓ Installation complete! Restart your terminal and run 'nodex' or 'nodex --help' to get started."
