<#  Build RazagathWoW-Setup.exe.

    Ensures the launcher + installer deps are present, then runs makensis with
    the realm / manifest / version baked in. If installer\client-base.nsh exists
    (written by stage-client.ps1) the full-client download option is included.

      pwsh tools/build-installer.ps1 -Version 2026.09.04
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$Realm = "ztnwow.duckdns.org",
    [string]$ManifestUrl = "https://raw.githubusercontent.com/ZeTruNightmare/RazagathWoW/main/manifest.json",
    [string]$LauncherVersion = "",
    # Embed THIS already-built launcher (e.g. the one published on the release) instead of compiling one. Using the released file
    # means the installer contains exactly the launcher the manifest points at, so there is one file for antivirus to learn.
    [string]$LauncherExe = ""
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Repo = Split-Path -Parent $Here
$makensis = "C:\Program Files (x86)\NSIS\makensis.exe"
if (-not (Test-Path $makensis)) { throw "NSIS not found - winget install NSIS.NSIS" }
if (-not $Version) {
    $Version = (Get-Content "$Repo\manifest.json" -Raw | ConvertFrom-Json).clientVersion
}

& "$Here\..\installer\tools\fetch-deps.ps1"

$lv = if ($LauncherVersion) { $LauncherVersion } else {
    (Get-Content "$Repo\manifest.json" -Raw | ConvertFrom-Json).launcher.version
}
if ($LauncherExe) {
    New-Item -ItemType Directory -Force -Path "$Repo\dist" | Out-Null
    Copy-Item $LauncherExe "$Repo\dist\RazagathWoW.exe" -Force
    Write-Host "using the supplied launcher: $LauncherExe"
} else {
    & "$Repo\launcher\build.ps1" -Version $lv -ManifestUrl $ManifestUrl -Out "$Repo\dist\RazagathWoW.exe"
    if ($LASTEXITCODE) { throw "launcher build failed" }
}

if (Test-Path "$Repo\installer\client-base.nsh") {
    Write-Host "client-base.nsh present -> full-client download option INCLUDED"
} else {
    Write-Host "no client-base.nsh -> patch-only installer (run stage-client.ps1 to add the full-client option)"
}

# NSIS stores every embedded file's modification time inside the installer, and a CI runner re-downloads them with a fresh time
# on every run - so the same inputs gave a different installer hash each build. Pin the times so the installer is reproducible.
$pin = [datetime]::SpecifyKind([datetime]"2026-01-01T00:00:00", [DateTimeKind]::Utc)
foreach ($f in @("$Repo\dist\RazagathWoW.exe", "$Repo\overlay\WTF\Config.wtf", "$Repo\installer\tools\7zr.exe", "$Repo\installer\tools\NScurl.dll", "$Repo\installer\client-base.nsh")) {
    if (Test-Path $f) { (Get-Item $f).LastWriteTimeUtc = $pin }
}

& $makensis "/DVERSION=$Version" "/DREALM=$Realm" "/DMANIFEST_URL=$ManifestUrl" "$Repo\installer\RazagathWoW.nsi"
if ($LASTEXITCODE) { throw "makensis failed" }

Get-ChildItem "$Repo\dist\RazagathWoW-Setup-$Version.exe" | ForEach-Object {
    "`nOK  {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB)
}
