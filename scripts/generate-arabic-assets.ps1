# Renders Noto Kufi Arabic Bold to 1-bit PNG sprites for Connect IQ MIP.
# Large proportional ٠–٩ (digit_*), small ٠–٩ plus minus/meem/degree (sm_*),
# Hijri/Gregorian months and weekdays. Dark (white ink) and light (black ink).
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$fontPath = Join-Path $PSScriptRoot "fonts\NotoKufiArabic-Bold.ttf"
$outDir   = Join-Path $PSScriptRoot "..\resources\images"

if (-not (Test-Path $fontPath)) {
    Write-Error "Missing font: $fontPath"
    exit 1
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$family = $pfc.Families[0]
$style  = [System.Drawing.FontStyle]::Bold
$clear  = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)

function FromCp([int[]]$cp) {
    -join ($cp | ForEach-Object { [char]$_ })
}

function New-Font([float]$px) {
    return New-Object System.Drawing.Font($family, $px, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Get-InkBounds($bmp) {
    $minX = $bmp.Width; $minY = $bmp.Height; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            if ($bmp.GetPixel($x, $y).A -gt 64) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -lt 0) { return $null }
    return @{ L = $minX; T = $minY; R = $maxX; B = $maxY }
}

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

function Crop-ToInk($bmp, [int]$padX, [int]$padY, [int]$targetH, $ink) {
    Binarize-Bitmap $bmp $ink
    $b = Get-InkBounds $bmp
    if ($null -eq $b) {
        $bmp.Dispose()
        $empty = New-Object System.Drawing.Bitmap 3, [Math]::Max(3, $targetH), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        return $empty
    }
    $srcW = $b.R - $b.L + 1
    $srcH = $b.B - $b.T + 1
    $outH = if ($targetH -gt 0) { $targetH } else { $srcH + 2 * $padY }
    $outW = $srcW + 2 * $padX
    if ($outW -lt 1) { $outW = 1 }
    if ($outH -lt 1) { $outH = 1 }
    $dst = New-Object System.Drawing.Bitmap $outW, $outH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.Clear($clear)
    $g.Dispose()
    $offY = [int](($outH - $srcH) / 2)
    if ($offY -lt 0) { $offY = 0 }
    for ($y = 0; $y -lt $srcH; $y++) {
        $dy = $offY + $y
        if ($dy -lt 0 -or $dy -ge $outH) { continue }
        for ($x = 0; $x -lt $srcW; $x++) {
            $dst.SetPixel($padX + $x, $dy, $bmp.GetPixel($b.L + $x, $b.T + $y))
        }
    }
    $bmp.Dispose()
    return $dst
}

function Render-Text([string]$text, [float]$px, $ink, [bool]$rtl, [int]$canvasW, [int]$canvasH) {
    $font = New-Font $px
    $bmp = New-Object System.Drawing.Bitmap $canvasW, $canvasH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($clear)
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
    $fmt = New-Object System.Drawing.StringFormat([System.Drawing.StringFormat]::GenericTypographic)
    if ($rtl) {
        $fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::DirectionRightToLeft
    }
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $brush = New-Object System.Drawing.SolidBrush($ink)
    $g.DrawString($text, $font, $brush, (New-Object System.Drawing.RectangleF(0, 0, $canvasW, $canvasH)), $fmt)
    $g.Dispose()
    $brush.Dispose()
    $fmt.Dispose()
    $font.Dispose()
    return $bmp
}

function Find-SizeForHeight([string]$probe, [int]$wantH, [bool]$rtl, $ink, [int]$cw, [int]$ch, [float]$lo, [float]$hi) {
    $best = $lo
    for ($s = $hi; $s -ge $lo; $s -= 1.0) {
        $bmp = Render-Text $probe $s $ink $rtl $cw $ch
        Binarize-Bitmap $bmp $ink
        $b = Get-InkBounds $bmp
        $bmp.Dispose()
        if ($null -eq $b) { continue }
        $h = $b.B - $b.T + 1
        if ($h -le $wantH) { return $s }
        $best = $s
    }
    return $best
}

function New-DegreeBitmap([int]$h, $ink) {
    $ow = 5
    $oh = 5
    $bmp = New-Object System.Drawing.Bitmap 7, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($clear)
    $g.Dispose()
    $ox = 1
    $oy = [int]($h * 0.12)
    if ($oy + $oh -gt $h) { $oy = 1 }
    for ($x = 0; $x -lt $ow; $x++) {
        $bmp.SetPixel($ox + $x, $oy, $ink)
        $bmp.SetPixel($ox + $x, $oy + $oh - 1, $ink)
    }
    for ($y = 0; $y -lt $oh; $y++) {
        $bmp.SetPixel($ox, $oy + $y, $ink)
        $bmp.SetPixel($ox + $ow - 1, $oy + $y, $ink)
    }
    return $bmp
}

function Save-Bmp($bmp, [string]$name) {
    $path = Join-Path $outDir $name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("Wrote {0} ({1}x{2})" -f $name, $bmp.Width, $bmp.Height)
}

$AR = 0x0660..0x0669 | ForEach-Object { [char]$_ }
$hijri = @(
    (FromCp @(0x0645,0x062D,0x0631,0x0645)),
    (FromCp @(0x0635,0x0641,0x0631)),
    (FromCp @(0x0631,0x0628,0x064A,0x0639,0x0020,0x0627,0x0644,0x0623,0x0648,0x0644)),
    (FromCp @(0x0631,0x0628,0x064A,0x0639,0x0020,0x0627,0x0644,0x0622,0x062E,0x0631)),
    (FromCp @(0x062C,0x0645,0x0627,0x062F,0x0649,0x0020,0x0627,0x0644,0x0623,0x0648,0x0644,0x0649)),
    (FromCp @(0x062C,0x0645,0x0627,0x062F,0x0649,0x0020,0x0627,0x0644,0x0622,0x062E,0x0631,0x0629)),
    (FromCp @(0x0631,0x062C,0x0628)),
    (FromCp @(0x0634,0x0639,0x0628,0x0627,0x0646)),
    (FromCp @(0x0631,0x0645,0x0636,0x0627,0x0646)),
    (FromCp @(0x0634,0x0648,0x0627,0x0644)),
    (FromCp @(0x0630,0x0648,0x0020,0x0627,0x0644,0x0642,0x0639,0x062F,0x0629)),
    (FromCp @(0x0630,0x0648,0x0020,0x0627,0x0644,0x062D,0x062C,0x0629))
)
$greg = @(
    (FromCp @(0x064A,0x0646,0x0627,0x064A,0x0631)),
    (FromCp @(0x0641,0x0628,0x0631,0x0627,0x064A,0x0631)),
    (FromCp @(0x0645,0x0627,0x0631,0x0633)),
    (FromCp @(0x0623,0x0628,0x0631,0x064A,0x0644)),
    (FromCp @(0x0645,0x0627,0x064A,0x0648)),
    (FromCp @(0x064A,0x0648,0x0646,0x064A,0x0648)),
    (FromCp @(0x064A,0x0648,0x0644,0x064A,0x0648)),
    (FromCp @(0x0623,0x063A,0x0633,0x0637,0x0633)),
    (FromCp @(0x0633,0x0628,0x062A,0x0645,0x0628,0x0631)),
    (FromCp @(0x0623,0x0643,0x062A,0x0648,0x0628,0x0631)),
    (FromCp @(0x0646,0x0648,0x0641,0x0645,0x0628,0x0631)),
    (FromCp @(0x062F,0x064A,0x0633,0x0645,0x0628,0x0631))
)
$dow = @(
    (FromCp @(0x0627,0x0644,0x0623,0x062D,0x062F)),
    (FromCp @(0x0627,0x0644,0x0627,0x062B,0x0646,0x064A,0x0646)),
    (FromCp @(0x0627,0x0644,0x062B,0x0644,0x0627,0x062B,0x0627,0x0621)),
    (FromCp @(0x0627,0x0644,0x0623,0x0631,0x0628,0x0639,0x0627,0x0621)),
    (FromCp @(0x0627,0x0644,0x062E,0x0645,0x064A,0x0633)),
    (FromCp @(0x0627,0x0644,0x062C,0x0645,0x0639,0x0629)),
    (FromCp @(0x0627,0x0644,0x0633,0x0628,0x062A))
)
$meem  = (FromCp @(0x0645))
$minus = "-"
$longestMonth = $hijri[5]
$longestDow   = $dow[3]
$tallDigit    = $AR[8].ToString()

foreach ($variant in @(
    @{ Ink = [System.Drawing.Color]::White; Suffix = "" },
    @{ Ink = [System.Drawing.Color]::Black; Suffix = "_light" }
)) {
    $ink = $variant.Ink
    $sfx = $variant.Suffix
    Write-Host "=== variant '$sfx' ==="

    $clockPx = Find-SizeForHeight $tallDigit 42 $false $ink 96 96 28 64
    Write-Host "Clock font ${clockPx}px"
    $clockRaws = @()
    $maxClockH = 0
    for ($d = 0; $d -le 9; $d++) {
        $raw = Render-Text $AR[$d].ToString() $clockPx $ink $false 96 96
        Binarize-Bitmap $raw $ink
        $b = Get-InkBounds $raw
        $h = if ($null -eq $b) { 0 } else { $b.B - $b.T + 1 }
        if ($h -gt $maxClockH) { $maxClockH = $h }
        $clockRaws += $raw
    }
    $clockH = $maxClockH + 2
    for ($d = 0; $d -le 9; $d++) {
        $cropped = Crop-ToInk $clockRaws[$d] 1 1 $clockH $ink
        Save-Bmp $cropped ("digit_{0}{1}.png" -f $d, $sfx)
        $cropped.Dispose()
    }

    $smallPx = Find-SizeForHeight $tallDigit 15 $false $ink 48 40 9 24
    Write-Host "Small font ${smallPx}px"
    $smallRaws = @()
    $maxSmallH = 0
    for ($d = 0; $d -le 9; $d++) {
        $raw = Render-Text $AR[$d].ToString() $smallPx $ink $false 48 40
        Binarize-Bitmap $raw $ink
        $b = Get-InkBounds $raw
        $h = if ($null -eq $b) { 0 } else { $b.B - $b.T + 1 }
        if ($h -gt $maxSmallH) { $maxSmallH = $h }
        $smallRaws += $raw
    }
    $smallH = $maxSmallH + 2
    for ($d = 0; $d -le 9; $d++) {
        $cropped = Crop-ToInk $smallRaws[$d] 1 1 $smallH $ink
        Save-Bmp $cropped ("sm_{0}{1}.png" -f $d, $sfx)
        $cropped.Dispose()
    }

    $minusRaw = Render-Text $minus $smallPx $ink $false 48 40
    Save-Bmp (Crop-ToInk $minusRaw 1 1 $smallH $ink) ("sm_minus{0}.png" -f $sfx)

    $meemRaw = Render-Text $meem $smallPx $ink $true 48 40
    Save-Bmp (Crop-ToInk $meemRaw 1 1 $smallH $ink) ("sm_meem{0}.png" -f $sfx)

    $deg = New-DegreeBitmap $smallH $ink
    Save-Bmp $deg ("sm_degree{0}.png" -f $sfx)
    $deg.Dispose()

    $monthPx = Find-SizeForHeight $longestMonth 16 $true $ink 240 56 10 24
    Write-Host "Month font ${monthPx}px"
    for ($i = 0; $i -lt 12; $i++) {
        $raw = Render-Text $hijri[$i] $monthPx $ink $true 240 56
        $cropped = Crop-ToInk $raw 1 1 0 $ink
        if ($cropped.Width -gt 130) {
            $cropped.Dispose()
            $raw2 = Render-Text $hijri[$i] ($monthPx - 2) $ink $true 240 56
            $cropped = Crop-ToInk $raw2 1 1 0 $ink
        }
        Save-Bmp $cropped ("hijri_{0}{1}.png" -f ($i + 1), $sfx)
        $cropped.Dispose()
    }
    for ($i = 0; $i -lt 12; $i++) {
        $raw = Render-Text $greg[$i] $monthPx $ink $true 240 56
        $cropped = Crop-ToInk $raw 1 1 0 $ink
        Save-Bmp $cropped ("greg_{0}{1}.png" -f ($i + 1), $sfx)
        $cropped.Dispose()
    }

    $dowPx = Find-SizeForHeight $longestDow 20 $true $ink 240 64 12 28
    Write-Host "Weekday font ${dowPx}px"
    for ($i = 0; $i -lt 7; $i++) {
        $raw = Render-Text $dow[$i] $dowPx $ink $true 240 64
        $cropped = Crop-ToInk $raw 1 1 0 $ink
        Save-Bmp $cropped ("dow_{0}{1}.png" -f ($i + 1), $sfx)
        $cropped.Dispose()
    }
}

Write-Host "Done - Arabic sprites in $outDir"
