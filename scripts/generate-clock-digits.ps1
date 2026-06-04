# Renders Source Code Pro Bold digits 0-9 to 1-bit PNG sprites for Connect IQ MIP
# Writes white-on-transparent (dark theme) and black-on-transparent (_light suffix).
Add-Type -AssemblyName System.Drawing

$fontPath = Join-Path $PSScriptRoot "fonts\SourceCodePro-Bold.ttf"
$outDir   = Join-Path $PSScriptRoot "..\resources\images"
$cellW    = 28
$cellH    = 40

if (-not (Test-Path $fontPath)) {
    Write-Error "Missing font: $fontPath"
    exit 1
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$family = $pfc.Families[0]

$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
$style = [System.Drawing.FontStyle]::Regular

function Binarize-Bitmap($bmp, $ink) {
    # Alpha threshold only — a luminance gate drops black-ink glyphs.
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.A -gt 64) {
                $bmp.SetPixel($x, $y, $ink)
            } else {
                $bmp.SetPixel($x, $y, $clear)
            }
        }
    }
}

function Find-FontSize($family, [int]$w, [int]$h, $ink) {
    $size = 42.0
    while ($size -ge 18) {
        $font = New-Object System.Drawing.Font($family, $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
        $test = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($test)
        $g.Clear($clear)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $brush = New-Object System.Drawing.SolidBrush($ink)
        $rect = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
        $g.DrawString("8", $font, $brush, $rect, $fmt)
        $g.Dispose()
        $brush.Dispose()
        $font.Dispose()
        Binarize-Bitmap $test $ink
        $top = $h; $bottom = 0; $hasPx = $false
        for ($y = 0; $y -lt $h; $y++) {
            for ($x = 0; $x -lt $w; $x++) {
                if ($test.GetPixel($x, $y).A -gt 0) {
                    $hasPx = $true
                    if ($y -lt $top) { $top = $y }
                    if ($y -gt $bottom) { $bottom = $y }
                }
            }
        }
        $test.Dispose()
        if ($hasPx -and $top -ge 1 -and $bottom -le ($h - 2)) { return $size }
        $size -= 1.0
    }
    return 32.0
}

foreach ($variant in @(
    @{ Ink = [System.Drawing.Color]::White; Suffix = "" },
    @{ Ink = [System.Drawing.Color]::Black; Suffix = "_light" }
)) {
    $ink = $variant.Ink
    $suffix = $variant.Suffix
    $fontSize = Find-FontSize $family $cellW $cellH $ink
    Write-Host "Using Source Code Pro Bold at ${fontSize}px (${cellW}x${cellH}, suffix '$suffix')"

    $font = New-Object System.Drawing.Font($family, $fontSize, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $brush = New-Object System.Drawing.SolidBrush($ink)
    $rect = New-Object System.Drawing.RectangleF(0, 0, $cellW, $cellH)

    for ($d = 0; $d -le 9; $d++) {
        $bmp = New-Object System.Drawing.Bitmap $cellW, $cellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear($clear)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
        $g.DrawString($d.ToString(), $font, $brush, $rect, $fmt)
        $g.Dispose()
        Binarize-Bitmap $bmp $ink
        $out = Join-Path $outDir ("digit_{0}{1}.png" -f $d, $suffix)
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host "Wrote $out"
    }

    $brush.Dispose()
    $font.Dispose()
}

Write-Host "Done - digit sprites in $outDir"
