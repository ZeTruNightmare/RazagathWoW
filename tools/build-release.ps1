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
    [switch]$LocalInstaller,                        # build + attach the installer here instead of in GitHub Actions
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
#  1.6.4 = Wow.exe patched Large-Address-Aware (4 GB) + re-patch from Wow.exe.orig.
#  1.6.7 = Wow.exe pokes for 12 playable races (Goblin + Worgen): race-array size + compositor loops.
#  1.6.8 = Wow.exe pokes raise the playable-race cap to 31 (random-race array + relocated per-race table).
$MinLauncher = [version]"1.6.8"
$launcherOut = "$RepoDir\dist\RazagathWoW.exe"
$curLv = (Get-Content "$RepoDir\manifest.json" | ConvertFrom-Json).launcher.version
$lv = if ($LauncherVersion) { $LauncherVersion } else { $curLv }
if ([version]$lv -lt $MinLauncher) { $lv = "$MinLauncher" }
& "$RepoDir\launcher\build.ps1" -Version $lv -ManifestUrl $ManifestUrl -Out $launcherOut
if ($LASTEXITCODE) { throw "launcher build failed" }

# --- 4. hash managed files -----------------------------------------
$mpq   = "$RepoDir\patch\patch-enUS-Z.MPQ"
if (-not (Test-Path $mpq)) { throw "missing $mpq" }
# Root-level patch: the stock Patch-F/G/H.MPQ override CharSections / CreatureModelData / EmotesTextSound ... and load AFTER the enUS
# patches, so the goblin/worgen versions of those tables must ship as Data\Patch-Z.MPQ (loads after Patch-H).
$mpqRoot = "$RepoDir\patch\Patch-Z.MPQ"
if (-not (Test-Path $mpqRoot)) { throw "missing $mpqRoot  (run tools\sync-from-module.ps1)" }
# Gilneas (2026.10.06): zone world data / models / DBC tables + the Worgen talent and full Item.dbc fixes. Root-level so it loads after the stock Patch-F/G/H/S/T and the enUS patches.
$mpqY = "$RepoDir\patch\Patch-Y.MPQ"
if (-not (Test-Path $mpqY)) { throw "missing $mpqY  (run tools\sync-from-module.ps1)" }
# Login screen (2026.10.07): the background picture tiles + the Mists of Pandaria login music (mk_login_bg.py / mk_login_audio.py + build_mpq.pl). Root-level, its own archive so patch-enUS-Z does not grow by 13 MB.
$mpqL = "$RepoDir\patch\Patch-L.MPQ"
if (-not (Test-Path $mpqL)) { throw "missing $mpqL  (run tools\sync-from-module.ps1)" }

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
# Folders that earlier releases shipped but that were merged into "Razagath".
# Listing them as members makes the launcher wipe them from players' clients on
# update (they are not in the zip, so nothing is re-extracted) - otherwise the old
# SpellBladeUI/BigBags/Companions would load alongside the merged addon.
$legacyMembers = @("Interface/AddOns/SpellBladeUI","Interface/AddOns/RazagathBigBags","Interface/AddOns/RazagathCompanions")
$members = @($members + ($legacyMembers | Where-Object { $members -notcontains $_ }))
# DETERMINISTIC zip (added 2026.10.07): Compress-Archive stamps every entry with the file's modification time and sync-from-module.ps1 re-copies the files on every
# release, so the zips got a NEW hash each release even when nothing inside changed - every player re-downloaded the 32 MB Questie bundle + the add-on bundle every time.
# Here the entries are sorted (ordinal), have a fixed timestamp and forward-slash names (the launcher accepts both), so identical content => a byte-identical zip => players
# only download a bundle when it really changed.
function New-DeterministicZip([string]$SourceRoot, [string]$ZipPath, [string]$TopFolder) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $base  = (Resolve-Path $SourceRoot).Path.TrimEnd('\')
    $stamp = New-Object DateTimeOffset(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $rel   = @(Get-ChildItem $base -Recurse -File | ForEach-Object { $_.FullName.Substring($base.Length + 1).Replace('\', '/') })
    [Array]::Sort($rel, [StringComparer]::Ordinal)
    $fs = [IO.File]::Open($ZipPath, [IO.FileMode]::Create)
    $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($r in $rel) {
            $entry = $za.CreateEntry("$TopFolder/$r", [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $stamp
            $inStream = [IO.File]::OpenRead((Join-Path $base $r.Replace('/', '\')))
            $outStream = $entry.Open()
            try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose(); $inStream.Dispose() }
        }
    } finally { $za.Dispose(); $fs.Dispose() }
}
$zip = "$RepoDir\dist\RazagathAddons.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
New-DeterministicZip "$RepoDir\overlay\Interface" $zip "Interface"
Write-Host ("RazagathAddons.zip  ({0:N0} bytes, {1} add-ons)" -f (Get-Item $zip).Length, $members.Count)

# Questie-335 (third-party quest add-on, ~120 MB unpacked): kept out of git in static\, shipped as its own zip bundle so the small add-on bundle above is not re-downloaded for it.
$qSrc = "$RepoDir\static\Interface\AddOns\Questie-335"; $qZip = "$RepoDir\dist\Questie-335.zip"
if (Test-Path $qSrc) {
    if (Test-Path $qZip) { Remove-Item $qZip -Force }
    New-DeterministicZip "$RepoDir\static\Interface" $qZip "Interface"
    Write-Host ("Questie-335.zip  ({0:N0} bytes)" -f (Get-Item $qZip).Length)
}

$files = @(
    @{ path="Data/enUS/patch-enUS-Z.MPQ"; local=$mpq;  asset="patch-enUS-Z.MPQ" },
    @{ path="Data/Patch-Z.MPQ";           local=$mpqRoot; asset="Patch-Z.MPQ" },
    @{ path="Data/Patch-Y.MPQ";           local=$mpqY;    asset="Patch-Y.MPQ" },
    @{ path="Data/Patch-L.MPQ";           local=$mpqL;    asset="Patch-L.MPQ" },
    @{ path="Data/enUS/patch-enUS-M.MPQ"; local=$mapM; asset="patch-enUS-M.MPQ" },
    @{ path="Data/enUS/patch-enUS-N.MPQ"; local=$mapN; asset="patch-enUS-N.MPQ" },
    @{ path="Interface/AddOns"; local=$zip; asset="RazagathAddons.zip"; type="zip"; members=$members }
)
if (Test-Path $qZip) { $files += @{ path="Interface/AddOns/Questie-335"; local=$qZip; asset="Questie-335.zip"; type="zip"; members=@("Interface/AddOns/Questie-335") } }
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

# --- 5b. installer -------------------------------------------------
# (Default: the .github/workflows/release-installer.yml Action builds it after the release is
# published, from the patch archive uploaded below + the commit pushed in step 7.)
# Every release carries RazagathWoW-Setup.exe under a FIXED name so the permalink
#   https://github.com/<repo>/releases/latest/download/RazagathWoW-Setup.exe
# always resolves for players (no need to build the installer themselves).
$installer = $null
if (-not $LocalInstaller) {
    Write-Host "installer: built + attached by the 'Build installer' GitHub Action once this release is published (re-run it from the Actions tab if it ever fails; -LocalInstaller builds it here instead)"
} elseif (Test-Path "C:\Program Files (x86)\NSIS\makensis.exe") {
    & "$PSScriptRoot\build-installer.ps1" -Version $Version -LauncherVersion $lv
    if ($LASTEXITCODE) { throw "installer build failed" }
    $builtInstaller = "$RepoDir\dist\RazagathWoW-Setup-$Version.exe"
    if (-not (Test-Path $builtInstaller)) { throw "installer build did not produce $builtInstaller" }
    $installer = "$RepoDir\dist\RazagathWoW-Setup.exe"
    Copy-Item $builtInstaller $installer -Force
    Write-Host ("installer ready: {0}  ({1:N1} MB)" -f $installer, ((Get-Item $installer).Length / 1MB))
} else {
    Write-Warning "NSIS not installed - this release will NOT carry RazagathWoW-Setup.exe (winget install NSIS.NSIS)"
}

# --- 6. GitHub release ---------------------------------------------
$assets = @($mpq, $mpqRoot, $mpqY, $mpqL, $mapM, $mapN, $launcherOut, $zip)
if (Test-Path $qZip) { $assets += $qZip }
if ($installer) { $assets += $installer }

$relNotes = "RazagathWoW client patch $Version`n`n" + (($noteList | ForEach-Object { "- $_" }) -join "`n")
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
& $gh release view $Tag --repo $Repo 2>&1 | Out-Null
$exists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEAP

if ($exists) {
    & $gh release upload $Tag @assets --repo $Repo --clobber
} else {
    # Windows PowerShell 5.1 mangles multi-line / quoted native args: pass the body as a file instead
    $notesFile = Join-Path $env:TEMP "razagath_relnotes_$Version.md"
    [System.IO.File]::WriteAllText($notesFile, $relNotes, (New-Object System.Text.UTF8Encoding($false)))
    & $gh release create $Tag @assets --repo $Repo --title "Patch $Version" --notes-file $notesFile
}
if ($LASTEXITCODE) { throw "gh release failed" }

# --- 7. commit + push -------------------------------------------
# git writes harmless warnings (e.g. CRLF) to stderr; under Windows PowerShell 5.1 with
# ErrorActionPreference=Stop that surfaces as a terminating NativeCommandError and
# aborted the script AFTER the GitHub release already existed. Run git with Continue
# and check real exit codes instead.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
git -C $RepoDir add manifest.json CHANGELOG.md overlay hd-patches.json 2>&1 | ForEach-Object { "$_" } | Write-Host
if ($LASTEXITCODE) { $ErrorActionPreference = $prevEAP; throw "git add failed" }
git -C $RepoDir commit -m "release: client $Version (launcher $lv)" 2>&1 | ForEach-Object { "$_" } | Write-Host
if ($LASTEXITCODE) { $ErrorActionPreference = $prevEAP; throw "git commit failed" }
git -C $RepoDir push 2>&1 | ForEach-Object { "$_" } | Write-Host
if ($LASTEXITCODE) { $ErrorActionPreference = $prevEAP; throw "git push failed" }
$ErrorActionPreference = $prevEAP
Write-Host "`nDONE. Players get $Version on next launch."
