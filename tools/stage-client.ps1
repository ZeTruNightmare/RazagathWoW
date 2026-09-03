<#  Build the full, ready-to-play RazagathWoW client, compress it into split
    volumes, publish them as a GitHub "client-base" release, and generate the
    installer/client-base.nsh that wires the full-client download into
    RazagathWoW-Setup.exe.

    The staged tree contains:
      - Wow.exe  (clean from -Source, then patched in place; Wow.exe.orig kept)
      - RazagathWoW.exe launcher + launcher.cfg
      - Data/enUS/patch-enUS-Z.MPQ
      - Interface/AddOns/SpellBladeUI/*
      - WTF/Config.wtf  (windowed by default)   +   realmlist.wtf
    and NOT: account data, cache, logs, screenshots, other addons.

    Example (build + publish + wire installer):
      pwsh tools/stage-client.ps1 -Source "D:\ChromieCraft_clean" -Work "D:\rz-stage" `
           -Repo ZeTruNightmare/RazagathWoW -Version 2026.09.04 -Publish

    -Source must be a CLEAN 3.3.5a (build 12340) client. -Work needs ~35 GB free.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Source,
    [Parameter(Mandatory)] [string]$Work,          # scratch dir on a big drive
    [string]$Repo = "",                            # owner/name  (required with -Publish)
    [string]$Version = "",                         # default: today
    [string]$ManifestUrl = "https://raw.githubusercontent.com/ZeTruNightmare/RazagathWoW/main/manifest.json",
    [int]$VolumeMB = 1900,
    [int]$Compression = 3,                          # 0=store .. 9=ultra; MPQ/exe don't compress much
    [switch]$Publish
)
$ErrorActionPreference = "Stop"
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoDir = Split-Path -Parent $Here
$sevenZip = "C:\Program Files\7-Zip\7z.exe"
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { $gh = "C:\Program Files\GitHub CLI\gh.exe" }
if (-not $Version) { $Version = Get-Date -Format "yyyy.MM.dd" }
if ($Publish -and -not $Repo) { throw "-Publish needs -Repo owner/name" }

$stage = Join-Path $Work "client"
$out   = Join-Path $Work "out"
New-Item -ItemType Directory -Force -Path $stage, $out | Out-Null

$mpq      = "$RepoDir\patch\patch-enUS-Z.MPQ"
$launcher = "$RepoDir\dist\RazagathWoW.exe"
foreach ($f in @($mpq, $launcher, $sevenZip)) { if (-not (Test-Path $f)) { throw "missing $f" } }
if (-not (Test-Path "$Source\Wow.exe")) { throw "no Wow.exe under -Source ($Source)" }

# ---- 1. stage a clean tree -------------------------------------------
Write-Host "staging clean client -> $stage"
$rc = @($Source, $stage, "/MIR", "/NFL","/NDL","/NJH","/NJS","/NP","/R:1","/W:1",
        "/XD", (Join-Path $Source "Cache"), (Join-Path $Source "Logs"),
              (Join-Path $Source "Errors"), (Join-Path $Source "Screenshots"),
              (Join-Path $Source "WTF"),
        "/XF", "*.bak","Wow.exe.orig","Wow.exe.spellblade-patched","*.7z","*.7z.*","*.log")
robocopy @rc | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

# ---- 2. overlay our content ---------------------------------------
New-Item -ItemType Directory -Force -Path "$stage\Data\enUS","$stage\WTF","$stage\Interface\AddOns" | Out-Null
Copy-Item $launcher "$stage\RazagathWoW.exe" -Force
Set-Content "$stage\launcher.cfg" -Value ('{ "manifestUrl": "' + $ManifestUrl + '" }') -Encoding UTF8
Copy-Item $mpq "$stage\Data\enUS\patch-enUS-Z.MPQ" -Force
Copy-Item "$RepoDir\overlay\Interface\AddOns\SpellBladeUI" "$stage\Interface\AddOns\" -Recurse -Force
Copy-Item "$RepoDir\overlay\WTF\Config.wtf"  "$stage\WTF\Config.wtf" -Force
Copy-Item "$RepoDir\overlay\realmlist.wtf"   "$stage\realmlist.wtf" -Force
Copy-Item "$RepoDir\overlay\realmlist.wtf"   "$stage\Data\enUS\realmlist.wtf" -Force

# ---- 3. patch Wow.exe in place ---------------------------------
& "$stage\RazagathWoW.exe" --patch-exe "$stage" | Out-Null
$patchLog = Get-Content "$env:TEMP\razagath_patchexe.log" -ErrorAction SilentlyContinue
Write-Host "Wow.exe: $patchLog"
if ($patchLog -notmatch "Patched|AlreadyPatched") { throw "exe patch failed: $patchLog  (is -Source a clean build 12340 client?)" }

$stagedBytes = (Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("staged tree: {0:N1} GB" -f ($stagedBytes/1GB))

# ---- 4. compress into split volumes -------------------------
$base = Join-Path $out "RazagathWoW-client-$Version.7z"
Remove-Item "$base*" -ErrorAction SilentlyContinue
Write-Host "compressing (mx=$Compression, ${VolumeMB} MB volumes) - this takes a while..."
& $sevenZip a -t7z "-mx=$Compression" -mmt=on -ms=on "-v${VolumeMB}m" $base "$stage\*"
if ($LASTEXITCODE) { throw "7z failed ($LASTEXITCODE)" }
$vols = Get-ChildItem "$base.*" | Sort-Object Name
$compBytes = ($vols | Measure-Object Length -Sum).Sum
Write-Host ("{0} volumes, {1:N1} GB compressed" -f $vols.Count, ($compBytes/1GB))

# ---- 5. write installer/client-base.nsh -------------------
#  Volumes are hosted WITHOUT the ".7z" in the remote name - archive.org (and
#  some other hosts) reject an upload whose extension says "7z archive" but whose
#  bytes are an incomplete split volume. The installer downloads
#  "<stem>.00N" and saves it locally as "<stem>.7z.00N" so 7zr can join them.
$tag     = "client-base-$Version"
$stem    = "RazagathWoW-client-$Version"
$baseUrl = "https://github.com/$Repo/releases/download/$tag"   # upload-ia.ps1 rewrites this
$needMb  = [int](($stagedBytes + $compBytes) / 1MB + 2048)     # peak disk during install
$nsh = @()
$nsh += "; generated by tools/stage-client.ps1 - do not edit"
$nsh += "!define CLIENT_VERSION `"$Version`""
$nsh += "!define CLIENT_STEM `"$stem`""
$nsh += "!define CLIENT_BASEURL `"$baseUrl`""
$nsh += "!define CLIENT_VOLUMES $($vols.Count)"
$nsh += "!define CLIENT_NEED_MB $needMb"
$nsh += ""
$nsh += "!macro DOWNLOAD_CLIENT_VOLUMES"
for ($i = 0; $i -lt $vols.Count; $i++) {
    $suf = ($vols[$i].Name -replace '.*\.7z\.', '')            # "001"
    $sha = (Get-FileHash -Algorithm SHA256 $vols[$i].FullName).Hash.ToLower()
    $nsh += "  !insertmacro DL_VOLUME $i `"$suf`" `"$sha`""
}
$nsh += "!macroend"
Set-Content "$RepoDir\installer\client-base.nsh" -Value ($nsh -join "`r`n") -Encoding ASCII
Write-Host "wrote installer/client-base.nsh  (need ~$([int]($needMb/1024)) GB free during install)"

# ---- 6. publish the client-base release ---------------
if ($Publish) {
    # host without ".7z" in the name (see note above) - use renamed copies
    $hosted = foreach ($v in $vols) {
        $suf = $v.Name -replace '.*\.7z\.', ''
        $h = Join-Path $out "$stem.$suf"
        Copy-Item $v.FullName $h -Force
        $h
    }
    $notes = "Full RazagathWoW client base $Version. Downloaded automatically by RazagathWoW-Setup.exe (full-client option). Not needed if you already have a 3.3.5a client."
    & $gh release view $tag --repo $Repo *> $null
    if ($LASTEXITCODE -eq 0) {
        & $gh release upload $tag @($hosted) --repo $Repo --clobber
    } else {
        & $gh release create $tag @($hosted) --repo $Repo --title "Client base $Version" --notes $notes
    }
    if ($LASTEXITCODE) { throw "gh release failed" }
    Remove-Item $hosted -Force
    git -C $RepoDir add installer/client-base.nsh
    git -C $RepoDir commit -m "client-base $Version ($($vols.Count) volumes)"
    git -C $RepoDir push
    Write-Host "`npublished $tag."
} else {
    Write-Host "`nnot published. Upload $out\*.7z.* with tools/upload-ia.ps1, then rebuild the installer."
}
