<#  Build launcher\razagath.ico from launcher\icon-src.png (a square PNG with
    transparency). Produces a multi-resolution ICO (16..256) that Windows uses
    for the exe, the taskbar, and the launcher's own title-bar icon.
#>
Add-Type -AssemblyName System.Drawing
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$src  = Join-Path $Here "icon-src.png"
$out  = Join-Path $Here "razagath.ico"
if (-not (Test-Path $src)) { throw "no icon-src.png in $Here" }

$srcImg = [System.Drawing.Image]::FromFile($src)
$sizes  = 16, 24, 32, 48, 64, 128, 256
$pngs   = New-Object System.Collections.ArrayList

foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = 'AntiAlias'
    $g.InterpolationMode  = 'HighQualityBicubic'
    $g.PixelOffsetMode    = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    # tiny sizes: shave a pixel so the round crest doesn't clip at the edges
    $pad = if ($s -le 32) { 1 } else { 0 }
    $g.DrawImage($srcImg, $pad, $pad, $s - 2 * $pad, $s - 2 * $pad)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    [void]$pngs.Add($ms.ToArray())
    $bmp.Dispose()
}
$srcImg.Dispose()

$fs = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)   # ICONDIR
$offset = 6 + 16 * $pngs.Count
for ($i = 0; $i -lt $pngs.Count; $i++) {
    $s = $sizes[$i]; $d = $pngs[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim)         # width, height
    $bw.Write([byte]0); $bw.Write([byte]0)               # palette, reserved
    $bw.Write([uint16]1); $bw.Write([uint16]32)          # planes, bpp
    $bw.Write([uint32]$d.Length); $bw.Write([uint32]$offset)
    $offset += $d.Length
}
foreach ($d in $pngs) { $bw.Write($d) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($out, $fs.ToArray())
Write-Host ("wrote {0} ({1:N0} bytes, {2} sizes)" -f $out, $fs.Length, $pngs.Count)
