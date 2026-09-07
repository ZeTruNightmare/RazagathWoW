<#  Cut a RazagathWoW patch release.

    What it does:
      1. (optional) rebuilds patch-enUS-Z.MPQ from the module
      2. syncs artifacts into this repo
      3. builds RazagathWoW.exe (launcher) stamped with -Version + the manifest URL
      4. hashes every managed file
      5. rewrites manifest.json (versions, hashes, release URLs) and prepends a
         changelog entry
      6. creates//uploads a GitHub release with the big assets
      7. commits + pushes manifest.json + CHANGELOG.md

    Example:
      pwsh tools/build-release.ps1 -Repo ZeTruNightmare/RazagathWoW `
           -Version 2026.09.05 -Title "Balance pass" `
           -Notes "Spellblade mana costs reduced 10%","Fixed Light Touch tooltip"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Repo,           # owner/name
    [Parameter(Mandatory)] [string]$Version,        # e.g. 2026.09.05  (client version)
    [string]$LauncherVersion = "",                  # bump only when launcher.exe changes
    [string]$Title = "",
    [string[]]$Notes = @(),
    [string]$Realmlist = "",                        # keep existing if empty
    [string]$Tag = "",                              # default: patch-<Version>
    [switch]$RebuildMpq,
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$Repo    = $Repo.Trim()
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Here) { $Here = $PSScriptRoot }
$RepoDir = Split-Path -Parent $Here
$gh      = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { $gh = "C:\Program Files\GitHub CLI\gh.exe" }
if (-not (Test-Path $gh)) { throw "gh CLI not found - install it and run 'gh auth login'." }
if (-not $Tag) { $Tag = "patch-$Version" }
$ManifestUrl = "https://raw.githubusercontent.com/$Repo/main/manifest.json"
$RelBase     = "https://github.com/$Repo/releases/download/$Tag"

function Sha256($p) { (Get-FileHash -Algorithm SHA256 $p).Hash.ToLower() }

# --- 1. rebuild MPQ -------------------------------------------------------
if ($RebuildMpq) {
    $bf = "C:\Users\ZomgM\AppData\Local\Temp\claude\C--Azerothcore\d1dd20b4-dd34-483d-b1b0-b7763748e475\scratchpad\build_final.pl"
    if (Test-Path $bf) { perl $bf; if ($LASTEXITCODE) { throw "build_final.pl failed" } }
    else { Write-Warning "build_final.pl not found; skipping MPQ rebuild" }
}

# --- 2. sync artifacts --------------------------------------------------
& "$PSScriptRoot\sync-from-module.ps1"

# --- 3. build launcher ------------------------------------------------
#  1.4.0 = zip-bundle (add-on pack) support.
#  1.5.0 = resumable/retrying downloads (for the multi-GB HD client patches).
#  1.6.0 = optional auto sign-in (Settings tab) - skips the WoW login screen.
$MinLauncher = [version]"1.6.0"
$launcherOut = "$RepoDir\dist\RazagathWoW.exe"
$curLv = (Get-Content "$RepoDir\manifest.json" | ConvertFrom-Json).launcher.version
$lv = if ($LauncherVersion) { $LauncherVersion } else { $curLv }
if ([version]$lv -lt $MinLauncher) { $lv = "$MinLauncher" }
& "$RepoDir\launcher\build.ps1" -Version $lv -ManifestUrl $ManifestUrl -Out $launcherOut
if ($LASTEXITCODE) { throw "launcher build failed" }

# --- 4. hash managed files -----------------------------------------
$mpq   = "$RepoDir\patch\patch-enUS-Z.MPQ"
if (-not (Test-Path $mpq)) { throw "missing $mpq" }

# Static community map patches - classic/BC dungeon interior maps (DungeonMap.dbc
# + Interface\WorldMap art). Not generated; drop them in patch\ once. The WDM
# addon that drives them rides the add-on bundle from overlay\.
$mapM = "$RepoDir\patch\patch-enUS-M.MPQ"
$mapN = "$RepoDir\patch\patch-enUS-N.MPQ"
foreach ($f in @($mapM, $mapN)) {
    if (-not (Test-Path $f)) { throw "missing $f  (copy it from the client's Data\enUS\ - see the dungeon-map note)" }
}

# Bundle every add-on under overlay/Interface/AddOns into one zip. The launcher
# (>= 1.4.0) verifies its hash and extracts it client-root-relative, wiping the
# `members` folders first so removed files also leave the player's client.
$addonsRoot = "$RepoDir\overlay\Interface\AddOns"
$members = @(Get-ChildItem $addonsRoot -Directory | ForEach-Object { "Interface/AddOns/$($_.Name)" })
if (-not $members) { throw "no add-on folders under $addonsRoot" }
$zip = "$RepoDir\dist\RazagathAddons.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$RepoDir\overlay\Interface" -DestinationPath $zip -CompressionLevel Optimal
Write-Host ("RazagathAddons.zip  ({0:N0} bytes, {1} add-ons)" -f (Get-Item $zip).Length, $members.Count)

$files = @(
    @{ path="Data/enUS/patch-enUS-Z.MPQ"; local=$mpq;  asset="patch-enUS-Z.MPQ" },
    @{ path="Data/enUS/patch-enUS-M.MPQ"; local=$mapM; asset="patch-enUS-M.MPQ" },
    @{ path="Data/enUS/patch-enUS-N.MPQ"; local=$mapN; asset="patch-enUS-N.MPQ" },
    @{ path="Interface/AddOns"; local=$zip; asset="RazagathAddons.zip"; type="zip"; members=$members }
)
$fileEntries = foreach ($f in $files) {
    $e = [ordered]@{
        path   = $f.path
        sha256 = Sha256 $f.local
        size   = (Get-Item $f.local).Length
        url    = "$RelBase/$($f.asset)"
    }
    if ($f.type)    { $e.type    = $f.type }
    if ($f.members) { $e.members = @($f.members) }
    $e
}

# HD client patches - large static MPQs hosted on archive.org (see
# upload-hd-patches.ps1). hd-patches.json already carries path/url/sha256/size,
# so pass them straight through.
$hdJson = "$RepoDir\hd-patches.json"
if (Test-Path $hdJson) {
    $hd = Get-Content $hdJson -Raw | ConvertFrom-Json
    $fileEntries = @($fileEntries) + @($hd | ForEach-Object {
        [ordered]@{ path = $_.path; sha256 = $_.sha256; size = [int64]$_.size; url = $_.url }
    })
    Write-Host ("+ {0} HD patch entries from hd-patches.json (archive.org)" -f @($hd).Count)
}

# Notes: pass each as its own -Notes arg, OR one arg with ' || ' between them
# (robust when PowerShell's -File invocation flattens the array).
$noteList = @()
foreach ($n in $Notes) { $noteList += ($n -split '\s*\|\|\s*') }
$noteList = @($noteList | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$utf8 = New-Object System.Text.UTF8Encoding($false)

# --- 5. rewrite manifest.json ------------------------------------
$mf = [System.IO.File]::ReadAllText("$RepoDir\manifest.json", $utf8) | ConvertFrom-Json
$mf.clientVersion = $Version
if ($Realmlist) { $mf.realmlist = $Realmlist }
$mf.launcher.version = $lv
$mf.launcher.url     = "$RelBase/RazagathWoW.exe"
$mf.launcher.sha256  = Sha256 $launcherOut
$mf.files = @($fileEntries | ForEach-Object { [pscustomobject]$_ })

if ($mf.changelog.version -notcontains $Version) {
    $entry = [pscustomobject][ordered]@{
        version = $Version
        date    = (Get-Date -Format "yyyy-MM-dd")
        title   = $Title
        notes   = @($noteList)
    }
    $mf.changelog = @($entry) + @($mf.changelog)
}
[System.IO.File]::WriteAllText("$RepoDir\manifest.json", ($mf | ConvertTo-Json -Depth 8), $utf8)
Write-Host "manifest.json updated -> client $Version / launcher $lv  ($($noteList.Count) notes)"

# mirror into CHANGELOG.md (skip if this version's heading is already there)
$cl = [System.IO.File]::ReadAllText("$RepoDir\CHANGELOG.md", $utf8)
if ($noteList.Count -and $cl -notmatch "(?m)^##\s+$([regex]::Escape($Version))\b") {
    $md = "## $Version - $Title`r`n`r`n" + (($noteList | ForEach-Object { "- $_" }) -join "`r`n") + "`r`n`r`n"
    $marker = if ($cl.Contains("---`r`n`r`n")) { "---`r`n`r`n" } else { "---`n`n" }
    $i = $cl.IndexOf($marker)
    if ($i -ge 0) {
        $cl = $cl.Substring(0, $i + $marker.Length) + $md + $cl.Substring($i + $marker.Length)
        [System.IO.File]::WriteAllText("$RepoDir\CHANGELOG.md", $cl, $utf8)
    }
}

if ($DryRun) { Write-Host "DryRun: skipping gh release + git push"; return }

# --- 6. GitHub release ---------------------------------------------
$assets = @($mpq, $mapM, $mapN, $launcherOut, $zip)

$relNotes = "RazagathWoW client patch $Version`n`n" + (($noteList | ForEach-Object { "- $_" }) -join "`n")
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
& $gh release view $Tag --repo $Repo 2>&1 | Out-Null
$exists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEAP

if ($exists) {
    & $gh release upload $Tag @assets --repo $Repo --clobber
} else {
    & $gh release create $Tag @assets --repo $Repo --title "Patch $Version" --notes $relNotes
}
if ($LASTEXITCODE) { throw "gh release failed" }

# --- 7. commit + push -------------------------------------------
git -C $RepoDir add manifest.json CHANGELOG.md overlay hd-patches.json
git -C $RepoDir commit -m "release: client $Version (launcher $lv)"
git -C $RepoDir push
Write-Host "`nDONE. Players get $Version on next launch."
