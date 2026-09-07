<#  Upload the large static HD client patches (Patch-F/G/H/S/T.MPQ) to
    archive.org and write hd-patches.json, which build-release.ps1 folds into
    the launcher manifest as extra `files` entries (served straight from IA,
    since GitHub Releases caps a single asset at 2 GB and Patch-H is over it).

    These MPQs never change, so this is a one-time upload; re-run only if you
    swap a patch. Existing IA files of the same size are skipped.

    Prereqs (same as upload-ia.ps1):
      archive.org S3 keys in a file:
          access=XXXX
          secret=YYYY

    Example:
      pwsh tools/upload-hd-patches.ps1 -Keys D:\rz-stage\ia-keys.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Keys,
    [string]$Identifier = "razagath-hd-client-patches",
    [string]$Source     = "C:\Users\ZomgM\Desktop\ChromieCraft_3.3.5a\Data",
    [string[]]$Files    = @("Patch-F.MPQ","Patch-G.MPQ","Patch-H.MPQ","Patch-S.MPQ","Patch-T.MPQ"),
    [string]$Title      = "RazagathWoW HD client patches"
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoDir = Split-Path -Parent $Here
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Identifier -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{4,99}$') { throw "bad -Identifier" }

$kv = @{}
Get-Content $Keys | ForEach-Object {
    if ($_ -match '^\s*(access|secret)\s*=\s*(.+?)\s*$') { $kv[$Matches[1]] = $Matches[2] }
}
if (-not $kv.access -or -not $kv.secret) { throw "keys file must have access= and secret= lines" }
$auth = "LOW $($kv.access):$($kv.secret)"

$local = foreach ($n in $Files) {
    $p = Join-Path $Source $n
    if (-not (Test-Path $p)) { throw "missing $p" }
    Get-Item $p
}

# what's already on the IA item (so a re-run resumes instead of re-uploading)
$present = @{}
try {
    $meta = Invoke-RestMethod "https://archive.org/metadata/$Identifier" -TimeoutSec 30
    foreach ($f in @($meta.files)) { $present[$f.name] = [int64]$f.size }
} catch { }

$curl = "curl.exe"
$first = $true
foreach ($f in $local) {
    if ($present[$f.Name] -eq $f.Length) {
        Write-Host "  $($f.Name)  already on archive.org ($([math]::Round($f.Length/1MB)) MB) - skip"
        $first = $false
        continue
    }
    Write-Host "  uploading $($f.Name)  ($([math]::Round($f.Length/1MB)) MB)..."
    $url = "https://s3.us.archive.org/$Identifier/$($f.Name)"
    $args = @(
        "--fail","--location","--retry","5","--retry-delay","10",
        "-H","authorization: $auth",
        "-H","x-amz-auto-make-bucket:1",
        "--upload-file",$f.FullName,$url,
        "-o","NUL","-w","    -> HTTP %{http_code}  (%{size_upload} bytes, %{time_total}s)`n"
    )
    if ($first) {
        $args += @(
            "-H","x-archive-meta-mediatype:software",
            "-H","x-archive-meta-title:$Title",
            "-H","x-archive-meta-noindex:true",
            "-H","x-archive-queue-derive:0"
        )
        $first = $false
    }
    & $curl @args
    if ($LASTEXITCODE) { throw "upload failed on $($f.Name) (curl $LASTEXITCODE)" }
}

# --- write hd-patches.json for build-release.ps1 -----------------
$baseUrl = "https://archive.org/download/$Identifier"
$entries = foreach ($f in $local) {
    [ordered]@{
        path   = "Data/$($f.Name)"
        url    = "$baseUrl/$($f.Name)"
        sha256 = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower()
        size   = $f.Length
    }
}
$json = ConvertTo-Json @($entries) -Depth 4
[System.IO.File]::WriteAllText("$RepoDir\hd-patches.json", $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "`nwrote hd-patches.json ($($entries.Count) entries -> $baseUrl)"
Write-Host "IA may take a few minutes to make new files downloadable."
Write-Host "next:  commit hd-patches.json, then run tools/build-release.ps1 for the next patch."
