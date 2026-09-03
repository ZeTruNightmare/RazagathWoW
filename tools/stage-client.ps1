<#  Build the full, ready-to-play RazagathWoW client tree from a clean 3.3.5a
    client, then (optionally) compress it into split archives for GitHub /
    Cloudflare / torrent distribution.

    The output tree contains:
      - the clean game exe (Wow.exe) copied straight from -Source; the launcher
        patches it in place on first run and keeps Wow.exe.orig
      - RazagathWoW.exe launcher + launcher.cfg
      - Data/enUS/patch-enUS-Z.MPQ
      - Interface/AddOns/SpellBladeUI/*
      - WTF/Config.wtf  (windowed by default)
      - realmlist.wtf
    and NOT: your account data, cache, logs, screenshots, other addons.

    Example:
      pwsh tools/stage-client.ps1 -Source "D:\WoW335\clean" -Dest "D:\RazagathWoW" -Zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [string]$Dest,
    [string]$ManifestUrl = "",
    [switch]$Zip,
    [int]$VolumeMB = 1900
)
$ErrorActionPreference = "Stop"
$RepoDir = Split-Path -Parent $PSScriptRoot
$sevenZip = "C:\Program Files\7-Zip\7z.exe"

if (-not (Test-Path "$Source\Wow.exe")) { throw "no Wow.exe under -Source ($Source)" }
$mpq      = "$RepoDir\patch\patch-enUS-Z.MPQ"
$launcher = "$RepoDir\dist\RazagathWoW.exe"
foreach ($f in @($mpq,$launcher)) { if (-not (Test-Path $f)) { throw "missing $f - run build-release.ps1 first" } }

Write-Host "staging clean client -> $Dest"
$exclDirs  = @("Cache","Logs","Errors","Screenshots","WTF")
$exclFiles = @("*.bak","Wow.exe.orig","Wow.exe.spellblade-patched","*.7z","*.7z.*")
$rcArgs = @($Source, $Dest, "/E", "/NFL","/NDL","/NJH","/NJS","/NP","/R:1","/W:1")
foreach ($d in $exclDirs)  { $rcArgs += "/XD"; $rcArgs += (Join-Path $Source $d) }
foreach ($f in $exclFiles) { $rcArgs += "/XF"; $rcArgs += $f }
robocopy @rcArgs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

# launcher (Wow.exe already copied clean by robocopy; launcher patches it on run)
Copy-Item $launcher "$Dest\RazagathWoW.exe" -Force
if ($ManifestUrl) {
    Set-Content "$Dest\launcher.cfg" -Value ('{ "manifestUrl": "' + $ManifestUrl + '" }') -Encoding UTF8
}
# pre-patch now so the bundle is ready to play offline
& "$Dest\RazagathWoW.exe" --patch-exe "$Dest" | Out-Null
Write-Host ("Wow.exe patch: " + (Get-Content "$env:TEMP\razagath_patchexe.log" -ErrorAction SilentlyContinue))

# overlay (addon, Config.wtf, realmlist.wtf)
New-Item -ItemType Directory -Force -Path "$Dest\Data\enUS","$Dest\WTF","$Dest\Interface\AddOns" | Out-Null
Copy-Item "$mpq" "$Dest\Data\enUS\patch-enUS-Z.MPQ" -Force
Copy-Item "$RepoDir\overlay\Interface\AddOns\SpellBladeUI" "$Dest\Interface\AddOns\" -Recurse -Force
Copy-Item "$RepoDir\overlay\WTF\Config.wtf" "$Dest\WTF\Config.wtf" -Force
Copy-Item "$RepoDir\overlay\realmlist.wtf" "$Dest\realmlist.wtf" -Force
Copy-Item "$RepoDir\overlay\realmlist.wtf" "$Dest\Data\enUS\realmlist.wtf" -Force

$size = (Get-ChildItem $Dest -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("staged  {0:N1} GB" -f ($size/1GB))

if ($Zip) {
    if (-not (Test-Path $sevenZip)) { throw "7-Zip not found at $sevenZip" }
    $archive = "$RepoDir\dist\RazagathWoW-client.7z"
    Remove-Item "$archive*" -ErrorAction SilentlyContinue
    Write-Host "compressing (this takes a while)..."
    & $sevenZip a -t7z -mx=5 -mmt=on "-v${VolumeMB}m" $archive "$Dest\*"
    if ($LASTEXITCODE) { throw "7z failed" }
    Get-ChildItem "$archive*" | ForEach-Object { Write-Host ("  {0}  {1:N0} MB" -f $_.Name, ($_.Length/1MB)) }
    Write-Host "`nUpload dist\RazagathWoW-client.7z.* as release assets (they're <2GB each)."
}
