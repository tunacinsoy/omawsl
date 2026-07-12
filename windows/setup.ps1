<#
.SYNOPSIS
  Optional helper for the winget-installable pieces of omawsl's Windows-side setup.

.DESCRIPTION
  This script is NEVER invoked automatically by boot.sh or install.sh - omawsl's own rule
  (design spec Sections 2 and 13) is that nothing on the Windows side gets installed without
  the user explicitly choosing to. Read this script before running it, the same way you'd
  read any script before piping it into your shell.

  It installs Windows Terminal (if winget can find it - it's usually preinstalled on
  Windows 11) and the Nerd Font used by windows-terminal.json's "enhanced" profile, then
  prints the one manual step this script does NOT do for you: merging windows-terminal.json
  (or windows-terminal-fallback.json, if you skip the font) into your own settings.json.
  See docs/windows-setup.md for that step and everything else covered in this repo.

.NOTES
  Requires winget (bundled with Windows 11 App Installer). On a corporate machine where
  winget itself is blocked or Windows software installs require an IT ticket, skip this
  script entirely and follow docs/windows-setup.md by hand instead - that path needs no
  elevated rights beyond what a normal user already has for a per-user font install.
#>

param(
    [switch]$SkipFont
)

$ErrorActionPreference = "Stop"

function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Install-WindowsTerminal {
    Write-Host "Checking for Windows Terminal..."
    $installed = winget list --id Microsoft.WindowsTerminal --source winget 2>$null | Select-String "Microsoft.WindowsTerminal"
    if ($installed) {
        Write-Host "Windows Terminal is already installed."
        return
    }
    Write-Host "Installing Windows Terminal via winget..."
    winget install --id Microsoft.WindowsTerminal --source winget --accept-package-agreements --accept-source-agreements
}

function Install-NerdFont {
    $zipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip"
    $tempDir = Join-Path $env:TEMP "omawsl-cascadia-nerd-font"
    $zipPath = Join-Path $env:TEMP "omawsl-cascadia-nerd-font.zip"

    Write-Host "Downloading CaskaydiaMono Nerd Font from $zipUrl ..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    Write-Host "Extracting..."
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

    # Per-user font install: no admin rights needed, matches docs/windows-setup.md's
    # "right-click -> Install, no admin needed" framing for the manual path.
    $fontsFolder = (New-Object -ComObject Shell.Application).Namespace(0x14)
    $ttfFiles = Get-ChildItem -Path $tempDir -Filter "*.ttf" -Recurse
    foreach ($font in $ttfFiles) {
        Write-Host "Installing $($font.Name)..."
        $fontsFolder.CopyHere($font.FullName, 0x10)
    }

    Remove-Item -Force $zipPath
    Remove-Item -Recurse -Force $tempDir
    Write-Host "Font install complete. Family name: CaskaydiaMono Nerd Font Mono"
}

if (-not (Test-WingetAvailable)) {
    Write-Error "winget isn't available on this machine. Follow docs/windows-setup.md by hand instead."
    exit 1
}

Install-WindowsTerminal

if (-not $SkipFont) {
    Install-NerdFont
} else {
    Write-Host "Skipping font install (-SkipFont). Use windows-terminal-fallback.json instead of windows-terminal.json."
}

Write-Host ""
Write-Host "Done. One manual step left: merge windows-terminal.json (or windows-terminal-fallback.json"
Write-Host "if you used -SkipFont) into your Windows Terminal settings.json - see docs/windows-setup.md#fonts."
