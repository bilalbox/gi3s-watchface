# Draws simple 24x24 1-bit weather PNGs for Connect IQ MIP.
# Writes white-on-transparent (dark theme) and black-on-transparent (_light suffix).
Add-Type -AssemblyName System.Drawing

$size   = 24
$outDir = Join-Path $PSScriptRoot "..\resources\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

function New-IconBitmap {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) { $bmp.SetPixel($x, $y, $clear) }
    }
    return $bmp
}

function Set-Px($bmp, $x, $y, $ink) {
    if ($x -ge 0 -and $x -lt $size -and $y -ge 0 -and $y -lt $size) {
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

function Draw-Cloud($bmp, $cx, $cy, $ink) {
    Draw-Disc $bmp ($cx - 6) ($cy + 3) 4 $ink
    Draw-Disc $bmp $cx ($cy - 2) 5 $ink
    Draw-Disc $bmp ($cx + 6) ($cy + 2) 4 $ink
    Fill-Rect $bmp ($cx - 7) ($cy - 1) 15 7 $ink
    Fill-Rect $bmp ($cx - 3) ($cy - 4) 7 4 $ink
}

function Draw-Sun($bmp, $cx, $cy, $ink) {
    Draw-Disc $bmp $cx $cy 4 $ink
    Fill-Rect $bmp ($cx - 1) ($cy - 9) 3 5 $ink
    Fill-Rect $bmp ($cx - 1) ($cy + 5) 3 5 $ink
    Fill-Rect $bmp ($cx - 9) ($cy - 1) 5 3 $ink
    Fill-Rect $bmp ($cx + 5) ($cy - 1) 5 3 $ink
    foreach ($o in @(@(-6, -6), @(4, -6), @(-6, 4), @(4, 4))) {
        Fill-Rect $bmp ($cx + $o[0]) ($cy + $o[1]) 2 2 $ink
    }
}

function Draw-Gust($bmp, $y, $xStart, $length, $ink) {
    Fill-Rect $bmp $xStart $y $length 2 $ink
    Set-Px $bmp ($xStart + $length) ($y - 1) $ink
    Set-Px $bmp ($xStart + $length + 1) $y $ink
    Set-Px $bmp ($xStart + $length) ($y + 2) $ink
}

function Draw-Lightning($bmp, $ink) {
    foreach ($p in @(
        @(13, 15), @(13, 16), @(12, 17), @(11, 18), @(12, 19),
        @(13, 20), @(12, 21), @(11, 22), @(10, 22), @(11, 23)
    )) { Set-Px $bmp $p[0] $p[1] $ink }
    foreach ($p in @(
        @(14, 15), @(14, 16), @(13, 17), @(12, 18), @(13, 19),
        @(14, 20), @(13, 21), @(12, 22), @(11, 23)
    )) { Set-Px $bmp $p[0] $p[1] $ink }
}

function Draw-Snowflake($bmp, $cx, $cy, $ink) {
    Fill-Rect $bmp ($cx - 1) ($cy - 1) 3 3 $ink
    Set-Px $bmp $cx ($cy - 2) $ink
    Set-Px $bmp $cx ($cy + 2) $ink
    Set-Px $bmp ($cx - 2) $cy $ink
    Set-Px $bmp ($cx + 2) $cy $ink
}

function Write-WeatherIcons($ink, $suffix) {
    $clearIcon = New-IconBitmap
    Draw-Sun $clearIcon 12 12 $ink
    $clearIcon.Save((Join-Path $outDir "weather_clear$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $partly = New-IconBitmap
    Draw-Sun $partly 18 7 $ink
    Draw-Cloud $partly 10 14 $ink
    $partly.Save((Join-Path $outDir "weather_partly_cloudy$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $cloudy = New-IconBitmap
    Draw-Cloud $cloudy 12 12 $ink
    $cloudy.Save((Join-Path $outDir "weather_cloudy$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $wind = New-IconBitmap
    Draw-Gust $wind 6  3  11 $ink
    Draw-Gust $wind 11 6  11 $ink
    Draw-Gust $wind 16 9  11 $ink
    $wind.Save((Join-Path $outDir "weather_wind$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $rain = New-IconBitmap
    Draw-Cloud $rain 12 8 $ink
    Fill-Rect $rain 7  17 2 4 $ink
    Fill-Rect $rain 11 18 2 5 $ink
    Fill-Rect $rain 15 17 2 4 $ink
    $rain.Save((Join-Path $outDir "weather_rain$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $storm = New-IconBitmap
    Draw-Cloud $storm 12 7 $ink
    Draw-Lightning $storm $ink
    $storm.Save((Join-Path $outDir "weather_storm$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $snow = New-IconBitmap
    Draw-Cloud $snow 12 7 $ink
    Draw-Snowflake $snow 8  19 $ink
    Draw-Snowflake $snow 12 20 $ink
    Draw-Snowflake $snow 16 19 $ink
    $snow.Save((Join-Path $outDir "weather_snow$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}

Write-WeatherIcons ([System.Drawing.Color]::White) ""
Write-WeatherIcons ([System.Drawing.Color]::Black) "_light"
Write-Host "Generated weather icons in $outDir"
