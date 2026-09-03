<#  Upload the full-client volumes to archive.org and wire installer/client-base.nsh
    to pull from there.

    Prereqs:
      1. A free archive.org account.
      2. S3-like keys from https://archive.org/account/s3.php  (log in first).
         Put them in a file (NOT in chat / not on the command line):
             access=XXXXXXXXXXXX
             secret=YYYYYYYYYYYY
      3. The volumes built by stage-client.ps1 (default D:\rz-stage\out\*.7z.*).

    Example:
      pwsh tools/upload-ia.ps1 -Keys D:\rz-stage\ia-keys.txt `
           -Identifier rzgcw-client-2026-09-04 -Volumes D:\rz-stage\out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Keys,
    [Parameter(Mandatory)] [string]$Identifier,      # 5-100 chars, a-z 0-9 - _ .
    [string]$Volumes = "D:\rz-stage\out",
    [string]$Title = "RazagathWoW client base",
    [switch]$NoIndex = $true
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Repo = Split-Path -Parent $Here
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Identifier -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{4,99}$') { throw "bad -Identifier" }

# --- read keys (kept out of shell history / chat) --------------------
$kv = @{}
Get-Content $Keys | ForEach-Object {
    if ($_ -match '^\s*(access|secret)\s*=\s*(.+?)\s*$') { $kv[$Matches[1]] = $Matches[2] }
}
if (-not $kv.access -or -not $kv.secret) { throw "keys file must have access= and secret= lines" }
$auth = "LOW $($kv.access):$($kv.secret)"

$vols = Get-ChildItem "$Volumes\*.7z.*" | Sort-Object Name
if (-not $vols) { throw "no *.7z.* volumes in $Volumes" }
Write-Host ("uploading {0} volumes to archive.org/details/{1}" -f $vols.Count, $Identifier)

# what's already on the item (so a re-run resumes instead of re-uploading)
$present = @{}
try {
    $meta = Invoke-RestMethod "https://archive.org/metadata/$Identifier" -TimeoutSec 30
    foreach ($f in @($meta.files)) { $present[$f.name] = [int64]$f.size }
} catch { }

# archive.org validates anything whose name ends in a known archive extension and
# rejects an incomplete split volume ("BadContent: error checking archive file").
# Upload each "<stem>.7z.00N" under the key "<stem>.00N"; the installer restores
# the ".7z" locally so 7zr can join them.
$curl = "curl.exe"
for ($i = 0; $i -lt $vols.Count; $i++) {
    $v = $vols[$i]
    $remote = $v.Name -replace '\.7z\.', '.'
    if ($present[$remote] -eq $v.Length) {
        Write-Host "  $remote  already on archive.org - skip"
        continue
    }
    $url = "https://s3.us.archive.org/$Identifier/$remote"
    $args = @(
        "--fail", "--location", "--retry", "5", "--retry-delay", "10",
        "-H", "authorization: $auth",
        "-H", "x-amz-auto-make-bucket:1",
        "--upload-file", $v.FullName, $url,
        "-o", "NUL", "-w", "  $($v.Name)  ->  HTTP %{http_code}  (%{size_upload} bytes, %{time_total}s)`n"
    )
    if ($i -eq 0) {
        $args += @(
            "-H", "x-archive-meta-mediatype:software",
            "-H", "x-archive-meta-title:$Title",
            "-H", "x-archive-queue-derive:0"
        )
        if ($NoIndex) { $args += @("-H", "x-archive-meta-noindex:true") }
    }
    & $curl @args
    if ($LASTEXITCODE) { throw "upload failed on $($v.Name) (curl $LASTEXITCODE)" }
}

# --- rewrite client-base.nsh to point at archive.org ---------------
$baseUrl = "https://archive.org/download/$Identifier"
$nsh = "$Repo\installer\client-base.nsh"
(Get-Content $nsh) |
    ForEach-Object { $_ -replace '^!define CLIENT_BASEURL ".*"$', "!define CLIENT_BASEURL `"$baseUrl`"" } |
    Set-Content $nsh -Encoding ASCII
Write-Host "`nclient-base.nsh -> $baseUrl"
Write-Host "next:  pwsh tools/build-installer.ps1 -Version <ver>   then commit client-base.nsh"
Write-Host "note:  archive.org may take a few minutes to make the files downloadable."
