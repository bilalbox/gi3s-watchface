# Renders Black Ops One 3-letter weekday labels (SUN..SAT) for Connect IQ MIP.
# Writes white-on-transparent and black-on-transparent (_light suffix).
Add-Type -AssemblyName System.Drawing

$fontPath = Join-Path $PSScriptRoot "fonts\BlackOpsOne-Regular.ttf"
$outDir   = Join-Path $PSScriptRoot "..\resources\images"
$fontSize = 24.0
$padX     = 6
$padY     = 4

$days = @(
    @{ File = "weekday_sun"; Text = "SUN" },
    @{ File = "weekday_mon"; Text = "MON" },
    @{ File = "weekday_tue"; Text = "TUE" },
    @{ File = "weekday_wed"; Text = "WED" },
    @{ File = "weekday_thu"; Text = "THU" },
    @{ File = "weekday_fri"; Text = "FRI" },
    @{ File = "weekday_sat"; Text = "SAT" }
)

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

$probeFont = New-Object System.Drawing.Font($family, $fontSize, $style, [System.Drawing.GraphicsUnit]::Pixel)
$probeBmp = New-Object System.Drawing.Bitmap 256, 64, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$probeG = [System.Drawing.Graphics]::FromImage($probeBmp)
$maxW = 0.0
$maxH = 0.0
foreach ($day in $days) {
    $sz = $probeG.MeasureString($day.Text, $probeFont)
    if ($sz.Width -gt $maxW) { $maxW = $sz.Width }
    if ($sz.Height -gt $maxH) { $maxH = $sz.Height }
}
$probeG.Dispose()
$probeBmp.Dispose()
$probeFont.Dispose()

$cellW = [int][Math]::Ceiling($maxW) + $padX
$cellH = [int][Math]::Ceiling($maxH) + $padY
Write-Host "Cell size ${cellW}x${cellH} (24px font; widest label $([int]$maxW)px)"

foreach ($variant in @(
    @{ Ink = [System.Drawing.Color]::White; Suffix = "" },
    @{ Ink = [System.Drawing.Color]::Black; Suffix = "_light" }
)) {
    $ink = $variant.Ink
    $suffix = $variant.Suffix
    Write-Host "Black Ops One ${fontSize}px (suffix '$suffix')"

    $font = New-Object System.Drawing.Font($family, $fontSize, $style, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $brush = New-Object System.Drawing.SolidBrush($ink)
    $rect = New-Object System.Drawing.RectangleF(0, 0, $cellW, $cellH)

    foreach ($day in $days) {
        $bmp = New-Object System.Drawing.Bitmap $cellW, $cellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear($clear)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
        $g.DrawString($day.Text, $font, $brush, $rect, $fmt)
        $g.Dispose()
        Binarize-Bitmap $bmp $ink
        $out = Join-Path $outDir ($day.File + $suffix + ".png")
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Host "Wrote $out"
    }

    $brush.Dispose()
    $font.Dispose()
}

Write-Host "Done - weekday sprites in $outDir"
