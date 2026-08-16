# NODEX Cross-Platform PowerShell Installer
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

# Platform detection & robust path resolution
$IsWin = $false
if ($PSVersionTable.PSEdition -eq "Desktop" -or $IsWindows -or ($env:OS -like "*Windows*")) {
    $IsWin = $true
}

if ($IsWin -and $env:LOCALAPPDATA) {
    $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\nodex"
} else {
    $HomeDir = if ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath("UserProfile") }
    $InstallDir = Join-Path $HomeDir ".local/share/nodex"
    $BinDir = Join-Path $HomeDir ".local/bin"
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$RawUrl = "https://raw.githubusercontent.com/marhaburrisqi/Nodex/main/ddns.sh"
$TargetScript = Join-Path $InstallDir "ddns.sh"

Write-Green "[INSTALLER] Downloading NODEX..."
Invoke-WebRequest -Uri $RawUrl -OutFile $TargetScript

if ($IsWin) {
    $TargetCmd = Join-Path $InstallDir "nodex.cmd"
    $TargetModexCmd = Join-Path $InstallDir "modex.cmd"

    # Create CMD wrapper executable for Windows CMD / PowerShell (Git Bash, WSL, Busybox, or native sh)
    $CmdContent = @"
@echo off
setlocal
where sh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    sh "%~dp0ddns.sh" %*
    goto :eof
)
where bash >nul 2>&1
if %ERRORLEVEL% equ 0 (
    bash "%~dp0ddns.sh" %*
    goto :eof
)
if exist "%ProgramFiles%\Git\bin\sh.exe" (
    "%ProgramFiles%\Git\bin\sh.exe" "%~dp0ddns.sh" %*
    goto :eof
)
if exist "%SystemRoot%\System32\bash.exe" (
    "%SystemRoot%\System32\bash.exe" "%~dp0ddns.sh" %*
    goto :eof
)
echo [ERROR] No POSIX shell (sh/bash/Git Bash) found in PATH.
echo Please install Git for Windows or WSL to run NODEX.
exit /b 1
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
} else {
    # Non-Windows POSIX environment (Linux/macOS)
    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }

    $NodexBin = Join-Path $BinDir "nodex"
    $ModexBin = Join-Path $BinDir "modex"

    Copy-Item -Path $TargetScript -Destination $NodexBin -Force
    chmod +x $NodexBin 2>$null
    Copy-Item -Path $TargetScript -Destination $ModexBin -Force
    chmod +x $ModexBin 2>$null

    Write-Blue "`n✓ Installation complete!"
    Write-Yellow "[NOTE] Ensure $BinDir is in your PATH by adding this to your shell profile (~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish):"
    Write-Cyan "  export PATH=`"$BinDir`:`$PATH`""
    Write-Blue "Then run 'nodex' or 'nodex --help' to get started."
}
