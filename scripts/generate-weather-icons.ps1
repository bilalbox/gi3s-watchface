# Generates 24x24 1-bit style weather PNGs for Connect IQ MIP
# Writes white-on-transparent and black-on-transparent (_light suffix).
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot "..\resources\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

function New-IconBitmap {
    $bmp = New-Object System.Drawing.Bitmap 24, 24, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt 24; $y++) {
        for ($x = 0; $x -lt 24; $x++) { $bmp.SetPixel($x, $y, $clear) }
    }
    return $bmp
}

function Set-Px($bmp, $x, $y, $ink) {
    if ($x -ge 0 -and $x -lt 24 -and $y -ge 0 -and $y -lt 24) {
        $bmp.SetPixel($x, $y, $ink)
    }
}

function Fill-Rect($bmp, $x, $y, $w, $h, $ink) {
    for ($dy = 0; $dy -lt $h; $dy++) {
        for ($dx = 0; $dx -lt $w; $dx++) { Set-Px $bmp ($x + $dx) ($y + $dy) $ink }
    }
}

function Draw-Disc($bmp, $cx, $cy, $r, $ink) {
    for ($y = $cy - $r; $y -le $cy + $r; $y++) {
        for ($x = $cx - $r; $x -le $cx + $r; $x++) {
            $dx = $x - $cx; $dy = $y - $cy
            if (($dx * $dx + $dy * $dy) -le ($r * $r)) { Set-Px $bmp $x $y $ink }
        }
    }
}

function Draw-Cloud($bmp, $ink) {
    Draw-Disc $bmp 6  15 4 $ink
    Draw-Disc $bmp 12 9  6 $ink
    Draw-Disc $bmp 18 14 4 $ink
    Fill-Rect $bmp 5 11 14 8 $ink
    Fill-Rect $bmp 9 8  6  6 $ink
    Fill-Rect $bmp 6 18 12 2 $ink
}

function Write-WeatherIcons($ink, $suffix) {
    $sun = New-IconBitmap
    Draw-Disc $sun 12 12 5 $ink
    foreach ($p in @(
        @(12,1,12,4), @(12,20,12,23), @(1,12,4,12), @(20,12,23,12),
        @(5,5,7,7), @(19,5,17,7), @(5,19,7,17), @(19,19,17,17)
    )) { Fill-Rect $sun $p[0] $p[1] ([Math]::Abs($p[2]-$p[0])+1) ([Math]::Abs($p[3]-$p[1])+1) $ink }
    $sun.Save((Join-Path $outDir "weather_sun$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $cloud = New-IconBitmap
    Draw-Cloud $cloud $ink
    $cloud.Save((Join-Path $outDir "weather_cloud$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $rain = New-IconBitmap
    Draw-Cloud $rain $ink
    Fill-Rect $rain 8  20 2 3 $ink
    Fill-Rect $rain 13 20 2 3 $ink
    $rain.Save((Join-Path $outDir "weather_rain$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $storm = New-IconBitmap
    Draw-Cloud $storm $ink
    foreach ($p in @(
        @(11,19,11,21), @(11,21,8,21), @(8,21,11,23), @(11,23,9,23)
    )) {
        Fill-Rect $storm $p[0] $p[1] ([Math]::Abs($p[2]-$p[0])+2) ([Math]::Abs($p[3]-$p[1])+2) $ink
    }
    $storm.Save((Join-Path $outDir "weather_storm$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}

Write-WeatherIcons ([System.Drawing.Color]::White) ""
Write-WeatherIcons ([System.Drawing.Color]::Black) "_light"
Write-Host "Generated weather icons in $outDir"
