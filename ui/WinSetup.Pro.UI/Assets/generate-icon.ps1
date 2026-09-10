#Requires -Version 5.1
<#
.SYNOPSIS
    Renders the WinSetup Pro app icon (app.ico + app-256.png) with GDI+ - no
    external tools. Windows 11 style: a blue Fluent tile with a white window
    that carries a blue checkmark (a Windows workstation, verified / configured).
.EXAMPLE
    pwsh -File .\ui\WinSetup.Pro.UI\Assets\generate-icon.ps1
#>
[CmdletBinding()]
param([string]$OutDir = $PSScriptRoot)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

function New-RoundedRectPath {
    param([single]$x, [single]$y, [single]$w, [single]$h, [single]$r)
    $d = [single]($r * 2)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-IconBitmap {
    param([int]$S)

    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # --- blue Fluent tile ---------------------------------------------------
    $inset = [single]($S * 0.045)
    $tileR = [single]($S * 0.225)
    $tw = [single]($S - 2 * $inset)
    $tile = New-RoundedRectPath $inset $inset $tw $tw $tileR
    $rect = New-Object System.Drawing.RectangleF($inset, $inset, $tw, $tw)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 41, 137, 208),
        [System.Drawing.Color]::FromArgb(255, 0, 83, 165),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillPath($grad, $tile)

    # very soft top sheen
    $g.SetClip($tile)
    $hi = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 255, 255, 255))
    $g.FillEllipse($hi, $inset - $tw * 0.35, $inset - $tw * 0.95, $tw * 1.7, $tw)
    $g.ResetClip()

    # --- white window -----------------------------------------------------
    $wW = [single]($S * 0.520)
    $wH = [single]($S * 0.440)
    $wX = [single](($S - $wW) / 2)
    $wY = [single](($S - $wH) / 2 + $S * 0.012)
    $wR = [single]($S * 0.070)
    $win = New-RoundedRectPath $wX $wY $wW $wH $wR
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillPath($white, $win)

    # title bar strip (clipped to the rounded window)
    $g.SetClip($win)
    $bar = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 205, 227, 246))
    $g.FillRectangle($bar, $wX, $wY, $wW, [single]($wH * 0.28))
    $g.ResetClip()

    # --- checkmark ------------------------------------------------------
    $bx = $wX
    $bodyTop = [single]($wY + $wH * 0.28)
    $bh = [single]($wH * 0.72)
    $p1 = New-Object System.Drawing.PointF([single]($bx + $wW * 0.22), [single]($bodyTop + $bh * 0.52))
    $p2 = New-Object System.Drawing.PointF([single]($bx + $wW * 0.42), [single]($bodyTop + $bh * 0.72))
    $p3 = New-Object System.Drawing.PointF([single]($bx + $wW * 0.80), [single]($bodyTop + $bh * 0.28))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 0, 103, 192), [single]([Math]::Max(1.6, $S * 0.088)))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    [System.Drawing.PointF[]]$pts = @($p1, $p2, $p3)
    $g.DrawLines($pen, $pts)

    $pen.Dispose(); $white.Dispose(); $bar.Dispose(); $hi.Dispose(); $grad.Dispose()
    $tile.Dispose(); $win.Dispose(); $g.Dispose()
    return $bmp
}

function Get-PngBytes {
    param([System.Drawing.Bitmap]$Bmp)
    $ms = New-Object System.IO.MemoryStream
    $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
    return , $bytes
}

# --- render every size ----------------------------------------------------
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$frames = foreach ($s in $sizes) {
    $b = New-IconBitmap -S $s
    [pscustomobject]@{ Size = $s; Png = (Get-PngBytes -Bmp $b); Bmp = $b }
}

# --- write .ico (PNG-compressed entries, Vista+) -------------------------
$icoPath = Join-Path $OutDir 'app.ico'
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $bw.Write([byte]($(if ($f.Size -ge 256) { 0 } else { $f.Size })))
    $bw.Write([byte]($(if ($f.Size -ge 256) { 0 } else { $f.Size })))
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$f.Png.Length)
    $bw.Write([uint32]$offset)
    $offset += $f.Png.Length
}
foreach ($f in $frames) { $bw.Write($f.Png) }
$bw.Flush(); $bw.Dispose(); $fs.Dispose()

# --- also a 256 PNG for the README / GitHub ----------------------------
($frames | Where-Object Size -eq 256).Bmp.Save((Join-Path $OutDir 'app-256.png'),
    [System.Drawing.Imaging.ImageFormat]::Png)

foreach ($f in $frames) { $f.Bmp.Dispose() }
Write-Host "Wrote $icoPath ($((Get-Item $icoPath).Length) bytes, $($frames.Count) sizes) and app-256.png" -ForegroundColor Green
