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
$RepoDir = Split-Path -Parent $PSScriptRoot
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
$launcherOut = "$RepoDir\dist\RazagathWoW.exe"
$lv = if ($LauncherVersion) { $LauncherVersion } else {
    (Get-Content "$RepoDir\manifest.json" | ConvertFrom-Json).launcher.version
}
& "$RepoDir\launcher\build.ps1" -Version $lv -ManifestUrl $ManifestUrl -Out $launcherOut
if ($LASTEXITCODE) { throw "launcher build failed" }

# --- 4. hash managed files -----------------------------------------
$mpq   = "$RepoDir\patch\patch-enUS-Z.MPQ"
$lua   = "$RepoDir\overlay\Interface\AddOns\SpellBladeUI\SpellBladeUI.lua"
$toc   = "$RepoDir\overlay\Interface\AddOns\SpellBladeUI\SpellBladeUI.toc"
foreach ($f in @($mpq,$lua,$toc)) { if (-not (Test-Path $f)) { throw "missing $f" } }

$files = @(
    @{ path="Data/enUS/patch-enUS-Z.MPQ"; local=$mpq; asset="patch-enUS-Z.MPQ" },
    @{ path="Interface/AddOns/SpellBladeUI/SpellBladeUI.lua"; local=$lua; asset="SpellBladeUI.lua" },
    @{ path="Interface/AddOns/SpellBladeUI/SpellBladeUI.toc"; local=$toc; asset="SpellBladeUI.toc" }
)
$fileEntries = foreach ($f in $files) {
    [ordered]@{
        path   = $f.path
        sha256 = Sha256 $f.local
        size   = (Get-Item $f.local).Length
        url    = "$RelBase/$($f.asset)"
    }
}

# --- 5. rewrite manifest.json ------------------------------------
$mf = Get-Content "$RepoDir\manifest.json" -Raw | ConvertFrom-Json
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
        notes   = @($Notes)
    }
    $mf.changelog = @($entry) + @($mf.changelog)
}
$json = $mf | ConvertTo-Json -Depth 8
Set-Content "$RepoDir\manifest.json" -Value $json -Encoding UTF8
Write-Host "manifest.json updated -> client $Version / launcher $lv"

# mirror into CHANGELOG.md
if ($Notes.Count) {
    $md = "## $Version — $Title`n`n" + (($Notes | ForEach-Object { "- $_" }) -join "`n") + "`n`n"
    $cl = Get-Content "$RepoDir\CHANGELOG.md" -Raw
    $cl = $cl -replace "(---\r?\n\r?\n)", "`$1$md"
    Set-Content "$RepoDir\CHANGELOG.md" -Value $cl -Encoding UTF8
}

if ($DryRun) { Write-Host "DryRun: skipping gh release + git push"; return }

# --- 6. GitHub release ---------------------------------------------
$assets = @($mpq, $launcherOut, $lua, $toc)

$relNotes = "RazagathWoW client patch $Version`n`n" + (($Notes | ForEach-Object { "- $_" }) -join "`n")
$exists = (& $gh release view $Tag --repo $Repo 2>$null; $LASTEXITCODE -eq 0)
if ($exists) {
    & $gh release upload $Tag @assets --repo $Repo --clobber
} else {
    & $gh release create $Tag @assets --repo $Repo --title "Patch $Version" --notes $relNotes
}
if ($LASTEXITCODE) { throw "gh release failed" }

# --- 7. commit + push -------------------------------------------
git -C $RepoDir add manifest.json CHANGELOG.md
git -C $RepoDir commit -m "release: client $Version (launcher $lv)"
git -C $RepoDir push
Write-Host "`nDONE. Players get $Version on next launch."
