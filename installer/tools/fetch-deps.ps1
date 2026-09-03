<#  Download the binary tools the installer bundles (kept out of git).
      7zr.exe    - standalone .7z extractor            (7-zip.org, ~0.6 MB)
      NScurl.dll - libcurl NSIS plugin: HTTPS + resume  (github negrutiu/nsis-nscurl, ~8 MB)
#>
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path "$Here\7zr.exe")) {
    Write-Host "downloading 7zr.exe ..."
    Invoke-WebRequest "https://www.7-zip.org/a/7zr.exe" -OutFile "$Here\7zr.exe"
}
if (-not (Test-Path "$Here\NScurl.dll")) {
    Write-Host "downloading NScurl.dll ..."
    $rel = Invoke-RestMethod "https://api.github.com/repos/negrutiu/nsis-nscurl/releases/latest" -Headers @{ "User-Agent" = "razagath" }
    $url = ($rel.assets | Where-Object { $_.name -eq "NScurl.zip" }).browser_download_url
    $zip = "$Here\NScurl.zip"
    Invoke-WebRequest $url -OutFile $zip
    $sz = "C:\Program Files\7-Zip\7z.exe"
    & $sz e -y $zip "Plugins/x86-unicode/NScurl.dll" "-o$Here" | Out-Null
    Remove-Item $zip
}
Get-ChildItem "$Here\7zr.exe","$Here\NScurl.dll" | ForEach-Object { "  {0}  {1:N0} bytes" -f $_.Name, $_.Length }
Write-Host "deps ready."
