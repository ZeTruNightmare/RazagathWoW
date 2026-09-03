<#  Build RazagathWoW.exe from RazagathLauncher.cs using the Roslyn C# compiler
    that ships with Visual Studio / Build Tools. No .NET SDK required; the output
    targets .NET Framework 4.8 which is present on every Win10 1903+/Win11 box.

    Usage:
      pwsh -File build.ps1 [-Version 1.0.0] [-ManifestUrl https://raw.../manifest.json] [-Out <path>]
#>
[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [string]$ManifestUrl = "",
    [string]$Out = "",
    [string]$Icon = ""
)
$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Here) { $Here = (Get-Location).Path }
if (-not $Out)  { $Out  = Join-Path $Here "..\dist\RazagathWoW.exe" }
if (-not $Icon) { $Icon = Join-Path $Here "razagath.ico" }
$Out = [System.IO.Path]::GetFullPath($Out)

function Find-Csc {
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\*\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files (x86)\MSBuild\*\Bin\Roslyn\csc.exe"
    )
    foreach ($c in $candidates) {
        $hit = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "Roslyn csc.exe not found. Install Visual Studio 2022 (or Build Tools) with the .NET desktop workload."
}

$csc = Find-Csc
Write-Host "csc: $csc"

$fw = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
$refs = @(
    "$fw\System.dll",
    "$fw\System.Core.dll",
    "$fw\System.Drawing.dll",
    "$fw\System.Windows.Forms.dll",
    "$fw\System.Web.Extensions.dll",
    "$fw\System.Net.Http.dll",
    "$fw\System.Xml.dll"
) | ForEach-Object { "/reference:$_" }

# stamp version attributes
$verFull = if ($Version -match '^\d+\.\d+\.\d+$') { "$Version.0" } else { $Version }
$verCs = @"
using System.Reflection;
[assembly: AssemblyVersion("$verFull")]
[assembly: AssemblyFileVersion("$verFull")]
[assembly: AssemblyInformationalVersion("$Version")]
"@
$verPath = Join-Path $Here "Version.g.cs"
Set-Content -Path $verPath -Value $verCs -Encoding UTF8

# optionally bake the manifest URL in
$srcPath = Join-Path $Here "RazagathLauncher.cs"
$work = $srcPath
if ($ManifestUrl) {
    $placeholder = "https://raw.githubusercontent.com/RAZAGATH_OWNER/RazagathWoW/main/manifest.json"
    $txt = (Get-Content $srcPath -Raw).Replace($placeholder, $ManifestUrl)
    $work = Join-Path $Here "RazagathLauncher.g.cs"
    Set-Content -Path $work -Value $txt -Encoding UTF8
}

$outDir = Split-Path $Out -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$args = @(
    "/nologo","/target:winexe","/platform:anycpu","/optimize+","/langversion:7.3",
    "/out:$Out",
    "/win32manifest:$(Join-Path $Here 'app.manifest')"
)
if (Test-Path $Icon) { $args += "/win32icon:$Icon" }
$logo = Join-Path $Here "logo.png"
if (Test-Path $logo) { $args += "/resource:$logo,RazagathWoW.logo.png" }
$hdr = Join-Path $Here "header-bg.png"
if (Test-Path $hdr) { $args += "/resource:$hdr,RazagathWoW.header-bg.png" }
$playpng = Join-Path $Here "play-button.png"
if (Test-Path $playpng) { $args += "/resource:$playpng,RazagathWoW.play-button.png" }
$panel = Join-Path $Here "panel-bg.jpg"
if (Test-Path $panel) { $args += "/resource:$panel,RazagathWoW.panel-bg.jpg" }
$content = Join-Path $Here "content-bg.jpg"
if (Test-Path $content) { $args += "/resource:$content,RazagathWoW.content-bg.jpg" }
$divider = Join-Path $Here "divider.png"
if (Test-Path $divider) { $args += "/resource:$divider,RazagathWoW.divider.png" }
$args += $refs
$args += $work
$args += $verPath

Write-Host "compiling -> $Out"
& $csc @args
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }

if ($work -ne $srcPath) { Remove-Item $work -ErrorAction SilentlyContinue }
Remove-Item $verPath -ErrorAction SilentlyContinue

$fi = Get-Item $Out
Write-Host ("OK  {0}  ({1:N0} bytes)  v{2}" -f $fi.FullName, $fi.Length, $Version)
