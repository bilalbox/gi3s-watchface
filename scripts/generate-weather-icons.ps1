# Generates 24x24 1-bit style weather PNGs (white on transparent) for Connect IQ MIP
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot "..\resources\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

function New-IconBitmap {
    $bmp = New-Object System.Drawing.Bitmap 24, 24, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt 24; $y++) {
        for ($x = 0; $x -lt 24; $x++) { $bmp.SetPixel($x, $y, $clear) }
    }
    return $bmp
}

function Set-Px($bmp, $x, $y) {
    if ($x -ge 0 -and $x -lt 24 -and $y -ge 0 -and $y -lt 24) {
        $bmp.SetPixel($x, $y, $white)
    }
}

function Fill-Rect($bmp, $x, $y, $w, $h) {
    for ($dy = 0; $dy -lt $h; $dy++) {
        for ($dx = 0; $dx -lt $w; $dx++) { Set-Px $bmp ($x + $dx) ($y + $dy) }
    }
}

function Draw-Disc($bmp, $cx, $cy, $r) {
    for ($y = $cy - $r; $y -le $cy + $r; $y++) {
        for ($x = $cx - $r; $x -le $cx + $r; $x++) {
            $dx = $x - $cx; $dy = $y - $cy
            if (($dx * $dx + $dy * $dy) -le ($r * $r)) { Set-Px $bmp $x $y }
        }
    }
}

function Draw-Cloud($bmp) {
    Draw-Disc $bmp 6  15 4
    Draw-Disc $bmp 12 9  6
    Draw-Disc $bmp 18 14 4
    Fill-Rect $bmp 5 11 14 8
    Fill-Rect $bmp 9 8  6  6
    Fill-Rect $bmp 6 18 12 2
}

# Sun: bold core + 2px rays
$sun = New-IconBitmap
Draw-Disc $sun 12 12 5
foreach ($p in @(
    @(12,1,12,4), @(12,20,12,23), @(1,12,4,12), @(20,12,23,12),
    @(5,5,7,7), @(19,5,17,7), @(5,19,7,17), @(19,19,17,17)
)) { Fill-Rect $sun $p[0] $p[1] ([Math]::Abs($p[2]-$p[0])+1) ([Math]::Abs($p[3]-$p[1])+1) }
$sun.Save((Join-Path $outDir "weather_sun.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# Cloud
$cloud = New-IconBitmap
Draw-Cloud $cloud
$cloud.Save((Join-Path $outDir "weather_cloud.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# Rain: cloud + bold drops
$rain = New-IconBitmap
Draw-Cloud $rain
Fill-Rect $rain 8  20 2 3
Fill-Rect $rain 13 20 2 3
$rain.Save((Join-Path $outDir "weather_rain.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# Storm: cloud + lightning bolt (2px thick, within 24x24)
$storm = New-IconBitmap
Draw-Cloud $storm
foreach ($p in @(
    @(11,19,11,21), @(11,21,8,21), @(8,21,11,23), @(11,23,9,23)
)) {
    Fill-Rect $storm $p[0] $p[1] ([Math]::Abs($p[2]-$p[0])+2) ([Math]::Abs($p[3]-$p[1])+2)
}
$storm.Save((Join-Path $outDir "weather_storm.png"), [System.Drawing.Imaging.ImageFormat]::Png)

Write-Host "Generated weather icons in $outDir"
