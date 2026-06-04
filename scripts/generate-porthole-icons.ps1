# Generates 1-bit porthole metric icons for Connect IQ MIP
# Writes white-on-transparent and black-on-transparent (_light suffix).
Add-Type -AssemblyName System.Drawing

$size = 10
$outDir = Join-Path $PSScriptRoot "..\resources\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

function New-IconBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $s; $y++) {
        for ($x = 0; $x -lt $s; $x++) { $bmp.SetPixel($x, $y, $clear) }
    }
    return $bmp
}

function Set-Px($bmp, $x, $y, [int]$s, $ink) {
    if ($x -ge 0 -and $x -lt $s -and $y -ge 0 -and $y -lt $s) {
        $bmp.SetPixel($x, $y, $ink)
    }
}

function Fill-Rect($bmp, $x, $y, $w, $h, [int]$s, $ink) {
    for ($dy = 0; $dy -lt $h; $dy++) {
        for ($dx = 0; $dx -lt $w; $dx++) { Set-Px $bmp ($x + $dx) ($y + $dy) $s $ink }
    }
}

function Write-PortholeIcons($ink, $suffix) {
    $heart = New-IconBitmap $size
    foreach ($p in @(
        @(2,1), @(3,1), @(6,1), @(7,1),
        @(1,2), @(2,2), @(3,2), @(4,2), @(5,2), @(6,2), @(7,2), @(8,2),
        @(1,3), @(2,3), @(3,3), @(4,3), @(5,3), @(6,3), @(7,3), @(8,3),
        @(2,4), @(3,4), @(4,4), @(5,4), @(6,4), @(7,4),
        @(3,5), @(4,5), @(5,5), @(6,5),
        @(4,6), @(5,6),
        @(5,7)
    )) { Set-Px $heart $p[0] $p[1] $size $ink }
    $heart.Save((Join-Path $outDir "icon_heart$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $stepsSize = 12
    $steps = New-IconBitmap $stepsSize
    Fill-Rect $steps 2 2 3 4 $stepsSize $ink
    Fill-Rect $steps 2 7 3 2 $stepsSize $ink
    Fill-Rect $steps 7 4 3 4 $stepsSize $ink
    Fill-Rect $steps 7 9 3 2 $stepsSize $ink
    $steps.Save((Join-Path $outDir "icon_steps$suffix.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}

Write-PortholeIcons ([System.Drawing.Color]::White) ""
Write-PortholeIcons ([System.Drawing.Color]::Black) "_light"
Write-Host "Generated porthole icons in $outDir"
