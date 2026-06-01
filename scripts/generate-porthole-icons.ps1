# Generates 10x10 1-bit porthole metric icons (white on transparent) for Connect IQ MIP
Add-Type -AssemblyName System.Drawing

$size = 10
$outDir = Join-Path $PSScriptRoot "..\resources\images"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

function New-IconBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $s; $y++) {
        for ($x = 0; $x -lt $s; $x++) { $bmp.SetPixel($x, $y, $clear) }
    }
    return $bmp
}

function Set-Px($bmp, $x, $y, [int]$s) {
    if ($x -ge 0 -and $x -lt $s -and $y -ge 0 -and $y -lt $s) {
        $bmp.SetPixel($x, $y, $white)
    }
}

function Fill-Rect($bmp, $x, $y, $w, $h, [int]$s) {
    for ($dy = 0; $dy -lt $h; $dy++) {
        for ($dx = 0; $dx -lt $w; $dx++) { Set-Px $bmp ($x + $dx) ($y + $dy) $s }
    }
}

function Draw-Disc($bmp, $cx, $cy, $r, [int]$s) {
    for ($y = $cy - $r; $y -le $cy + $r; $y++) {
        for ($x = $cx - $r; $x -le $cx + $r; $x++) {
            $dx = $x - $cx; $dy = $y - $cy
            if (($dx * $dx + $dy * $dy) -le ($r * $r)) { Set-Px $bmp $x $y $s }
        }
    }
}

# Heart (10x10)
$heart = New-IconBitmap $size
foreach ($p in @(
    @(2,1), @(3,1), @(6,1), @(7,1),
    @(1,2), @(2,2), @(3,2), @(4,2), @(5,2), @(6,2), @(7,2), @(8,2),
    @(1,3), @(2,3), @(3,3), @(4,3), @(5,3), @(6,3), @(7,3), @(8,3),
    @(2,4), @(3,4), @(4,4), @(5,4), @(6,4), @(7,4),
    @(3,5), @(4,5), @(5,5), @(6,5),
    @(4,6), @(5,6),
    @(5,7)
)) { Set-Px $heart $p[0] $p[1] $size }
$heart.Save((Join-Path $outDir "icon_heart.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# Vertical shoeprints / steps (12x12) — two offset prints, toe + heel blocks
$stepsSize = 12
$steps = New-IconBitmap $stepsSize
# Left print: toe 3x4, heel 3x2
Fill-Rect $steps 2 2 3 4 $stepsSize
Fill-Rect $steps 2 7 3 2 $stepsSize
# Right print: toe 3x4, heel 3x2 (offset down-right)
Fill-Rect $steps 7 4 3 4 $stepsSize
Fill-Rect $steps 7 9 3 2 $stepsSize
$steps.Save((Join-Path $outDir "icon_steps.png"), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Generated porthole icons in $outDir"
