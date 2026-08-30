# Renders Noto Kufi Arabic Bold to 1-bit PNG sprites for Connect IQ MIP.
#
# Four TABULAR digit tiers - every glyph in a tier shares one cell width, so a
# multi-digit string never changes width as its value changes:
#   digit_ 30x37  clock      sm_ 14x17  Hijri day
#   md_    11x13  steps,     xs_  9x11  heart rate, Gregorian day, 5-digit steps
#                 temperature (md_ also carries minus / degree / meem)
# Plus Hijri and Gregorian month names and weekdays. Gregorian renders ~12%%
# smaller than Hijri. Cell sizes are derived from the widest ink actually
# rendered, never hardcoded. Dark (white ink) and light (black ink).
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

# Pads ink into a fixed cell, centred on both axes. This is what makes a digit set
# tabular: every glyph occupies the same advance, so multi-digit strings never change
# width as their value changes.
function Fit-ToCell($bmp, [int]$cellW, [int]$cellH, $ink) {
    Binarize-Bitmap $bmp $ink
    $b = Get-InkBounds $bmp
    $dst = New-Object System.Drawing.Bitmap $cellW, $cellH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.Clear($clear)
    $g.Dispose()
    if ($null -ne $b) {
        $srcW = $b.R - $b.L + 1
        $srcH = $b.B - $b.T + 1
        $offX = [int](($cellW - $srcW) / 2)
        $offY = [int](($cellH - $srcH) / 2)
        if ($offX -lt 0) { $offX = 0 }
        if ($offY -lt 0) { $offY = 0 }
        for ($y = 0; $y -lt $srcH; $y++) {
            $dy = $offY + $y
            if ($dy -lt 0 -or $dy -ge $cellH) { continue }
            for ($x = 0; $x -lt $srcW; $x++) {
                $dx = $offX + $x
                if ($dx -lt 0 -or $dx -ge $cellW) { continue }
                $dst.SetPixel($dx, $dy, $bmp.GetPixel($b.L + $x, $b.T + $y))
            }
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

function New-DegreeBitmap([int]$h, $ink, [int]$ring = 5) {
    $ow = $ring
    $oh = $ring
    $bmp = New-Object System.Drawing.Bitmap ($ring + 2), $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
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

# Widest and tallest ink across 0-9 at a given font size. Measurement only - reads
# alpha directly rather than binarizing, so the size search stays cheap.
function Measure-DigitInk([float]$px, $ink, [int]$cw, [int]$ch) {
    $maxW = 0
    $maxH = 0
    for ($d = 0; $d -le 9; $d++) {
        $raw = Render-Text $AR[$d].ToString() $px $ink $false $cw $ch
        $b = Get-InkBounds $raw
        $raw.Dispose()
        if ($null -eq $b) { continue }
        $w = $b.R - $b.L + 1
        $h = $b.B - $b.T + 1
        if ($w -gt $maxW) { $maxW = $w }
        if ($h -gt $maxH) { $maxH = $h }
    }
    return @{ W = $maxW; H = $maxH }
}

# Emits one tabular digit set at an exact target cell height. The font size is
# searched for (largest size whose tallest digit still fits), then the cell width is
# derived from the widest ink actually rendered - never hardcoded, so swapping the
# font or changing a target height stays correct.
function Emit-TabularDigits(
    [string]$prefix, [int]$targetCellH, $ink, [string]$sfx,
    [int]$cw, [int]$ch, [float]$lo, [float]$hi
) {
    $wantInk = $targetCellH - 2
    $px = $lo
    $m  = $null
    for ($s = $hi; $s -ge $lo; $s -= 0.5) {
        $probe = Measure-DigitInk $s $ink $cw $ch
        if ($probe.H -gt 0 -and $probe.H -le $wantInk) { $px = $s; $m = $probe; break }
    }
    if ($null -eq $m) {
        $px = $lo
        $m  = Measure-DigitInk $px $ink $cw $ch
    }
    $cellW = $m.W + 2
    $cellH = $targetCellH
    Write-Host ("  {0}*  font {1}px  cell {2}x{3}  (widest ink {4}px, tallest {5}px)" -f `
        $prefix, $px, $cellW, $cellH, $m.W, $m.H)
    for ($d = 0; $d -le 9; $d++) {
        $raw  = Render-Text $AR[$d].ToString() $px $ink $false $cw $ch
        $cell = Fit-ToCell $raw $cellW $cellH $ink
        Save-Bmp $cell ("{0}{1}{2}.png" -f $prefix, $d, $sfx)
        $cell.Dispose()
    }
    return @{ Px = $px; CellW = $cellW; CellH = $cellH }
}
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

    # ── Tabular digit tiers ──────────────────────────────────────────────────
    #   digit_ : stacked HH/MM clock          sm_ : Hijri day
    #   md_    : porthole steps, temperature  xs_ : porthole HR, Gregorian day
    # Clock and sm_ keep the cell heights they have today (37 / 17); md_ and xs_ are
    # new, sized so the porthole's worst-case content clears the circle.
    $clock = Emit-TabularDigits "digit_" 37 $ink $sfx 96 96 28 64
    $sm    = Emit-TabularDigits "sm_"    17 $ink $sfx 48 40  9 24
    $md    = Emit-TabularDigits "md_"    13 $ink $sfx 40 32  6 20
    $xs    = Emit-TabularDigits "xs_"    11 $ink $sfx 32 28  5 18

    # md_ also carries the temperature sign and unit. These stay proportional -
    # only digits need a uniform advance.
    $mdH  = $md.CellH
    $mdPx = $md.Px
    Save-Bmp (Crop-ToInk (Render-Text $minus $mdPx $ink $false 40 32) 1 1 $mdH $ink) ("md_minus{0}.png" -f $sfx)
    Save-Bmp (Crop-ToInk (Render-Text $meem  $mdPx $ink $true  40 32) 1 1 $mdH $ink) ("md_meem{0}.png"  -f $sfx)

    $deg = New-DegreeBitmap $mdH $ink 4
    Save-Bmp $deg ("md_degree{0}.png" -f $sfx)
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
    # Gregorian is the secondary calendar: render it ~12% smaller than Hijri so the
    # two rows read as a hierarchy, and so the stack regains the vertical room the
    # increased leading needs.
    $gregPx = [Math]::Max(8.0, [Math]::Round($monthPx * 0.88, 1))
    Write-Host "Gregorian month font ${gregPx}px (Hijri ${monthPx}px)"
    for ($i = 0; $i -lt 12; $i++) {
        $raw = Render-Text $greg[$i] $gregPx $ink $true 240 56
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
