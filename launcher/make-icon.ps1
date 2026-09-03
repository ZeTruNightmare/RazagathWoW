Add-Type -AssemblyName System.Drawing
$Here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$sizes = 16,24,32,48,64,128,256
$pngs = New-Object System.Collections.ArrayList
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $rect = New-Object System.Drawing.Rectangle 0, 0, $s, $s
    $c1 = [System.Drawing.Color]::FromArgb(70, 20, 120)
    $c2 = [System.Drawing.Color]::FromArgb(150, 60, 220)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c2, 45
    $g.FillEllipse($br, 0, 0, ($s - 1), ($s - 1))
    $fs = [int]($s * 0.62)
    $font = New-Object System.Drawing.Font 'Georgia', $fs, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $rf = New-Object System.Drawing.RectangleF 0, 0, $s, $s
    $g.DrawString('R', $font, [System.Drawing.Brushes]::White, $rf, $sf)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    [void]$pngs.Add($ms.ToArray())
    $bmp.Dispose()
}
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $out
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
for ($i = 0; $i -lt $pngs.Count; $i++) {
    $s = $sizes[$i]; $d = $pngs[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$d.Length); $bw.Write([uint32]$offset)
    $offset += $d.Length
}
foreach ($d in $pngs) { $bw.Write($d) }
$bw.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $Here 'razagath.ico'), $out.ToArray())
Write-Host ("wrote razagath.ico ({0} bytes)" -f $out.Length)
