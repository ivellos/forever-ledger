Add-Type -AssemblyName System.Drawing
# Draws Forever Ledger's outline icons (white, 64 px, 32-bit TGA) into media\icons.
# Run from the repository root: powershell -ExecutionPolicy Bypass -File tools\make-icons.ps1
# Our own drawings in the style of outline icon sets (October 4); add new ones at the end.
$out = Join-Path (Get-Location) "media\icons"
New-Item -ItemType Directory -Force $out | Out-Null
$S = 64 / 24.0   # drawn on a 24-unit grid like outline icon sets, scaled to 64 px

function New-Canvas {
  $bmp = New-Object System.Drawing.Bitmap 64, 64, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.ScaleTransform($S, $S)
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 1.9
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  return @($bmp, $g, $pen)
}

# A 32-bit TGA (BGRA, origin top-left): every WoW client reads it.
function Save-Tga($bmp, $path) {
  $w = $bmp.Width; $h = $bmp.Height
  $bytes = New-Object byte[] (18 + $w * $h * 4)
  $bytes[2] = 2
  $bytes[12] = $w -band 255; $bytes[13] = $w -shr 8
  $bytes[14] = $h -band 255; $bytes[15] = $h -shr 8
  $bytes[16] = 32; $bytes[17] = 0x28
  $i = 18
  for ($y = 0; $y -lt $h; $y++) { for ($x = 0; $x -lt $w; $x++) {
    $c = $bmp.GetPixel($x, $y)
    $bytes[$i] = $c.B; $bytes[$i+1] = $c.G; $bytes[$i+2] = $c.R; $bytes[$i+3] = $c.A; $i += 4 } }
  [IO.File]::WriteAllBytes($path, $bytes)
}

function Finish($parts, $name) {
  $parts[1].Dispose()
  Save-Tga $parts[0] (Join-Path $out "$name.tga")
  $parts[0].Dispose()
}

# Gear: eight rounded teeth around a ring, and a hole in the middle.
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
for ($k = 0; $k -lt 8; $k++) {
  $a = $k * [Math]::PI / 4
  foreach ($d in @(-0.30, -0.17, 0.17, 0.30)) {
    $r = if ([Math]::Abs($d) -gt 0.2) { 7.0 } else { 9.6 }
    $pts.Add((New-Object System.Drawing.PointF ([single](12 + $r * [Math]::Cos($a + $d))), ([single](12 + $r * [Math]::Sin($a + $d)))))
  }
}
$g.DrawPolygon($pen, $pts.ToArray())
$g.DrawEllipse($pen, 9, 9, 6, 6)
Finish $p "global"

# Two people: a full one in front, one half behind on the right.
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$g.DrawEllipse($pen, 5, 3, 8, 8)
$g.DrawArc($pen, 3, 14, 12, 12, 180, 180)
$g.DrawLine($pen, 3, 20, 3, 21); $g.DrawLine($pen, 15, 20, 15, 21)
$g.DrawArc($pen, 13, 3, 8, 8, -70, 140)
$g.DrawArc($pen, 15, 14, 8, 10, 230, 130)
$g.DrawLine($pen, 21, 20.5, 21, 21)
Finish $p "profiles"

# Palette: a rounded board with a thumb notch and three paint dots.
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$g.DrawArc($pen, 3, 3, 18, 18, 75, 285)
$g.DrawArc($pen, 13, 14, 6, 6, 260, -160)
$fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
foreach ($c in @(@(7, 9), @(11.5, 6.5), @(16, 9))) { $g.FillEllipse($fill, $c[0] - 1.3, $c[1] - 1.3, 2.6, 2.6) }
Finish $p "appearance"

# Change marks for What's new (owner, October 5), after the usual software convention:
# a bold delta for a major change, a single plus for something new, a pencil for a
# change, a wrench for a fix.

# Major: a bold delta (a thicker line than the others, so it reads as the big one).
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$pen.Width = 2.7
$g.DrawPolygon($pen, @((New-Object System.Drawing.PointF 12, 3.8), (New-Object System.Drawing.PointF 20.8, 19.6), (New-Object System.Drawing.PointF 3.2, 19.6)))
Finish $p "change-major"

# New: a single plus.
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$pen.Width = 2.3
$g.DrawLine($pen, 12, 5, 12, 19)
$g.DrawLine($pen, 5, 12, 19, 12)
Finish $p "change-new"

# Changed: a pencil, pointing down to the left.
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$g.TranslateTransform(12, 12); $g.RotateTransform(45); $g.TranslateTransform(-12, -12)
$g.DrawPolygon($pen, @((New-Object System.Drawing.PointF 9.8, 2.5), (New-Object System.Drawing.PointF 14.2, 2.5),
  (New-Object System.Drawing.PointF 14.2, 16), (New-Object System.Drawing.PointF 12, 21), (New-Object System.Drawing.PointF 9.8, 16)))
$g.DrawLine($pen, 9.8, 6, 14.2, 6)
$g.DrawLine($pen, 9.8, 16, 14.2, 16)
Finish $p "change-edit"

# Fixed: a wrench, its open jaw up to the right.
$p = New-Canvas; $g = $p[1]; $pen = $p[2]
$g.TranslateTransform(12, 12); $g.RotateTransform(45); $g.TranslateTransform(-12, -12)
$g.DrawArc($pen, 7.5, 2, 9, 9, 295, 310)
$g.DrawLines($pen, @((New-Object System.Drawing.PointF 10.1, 2.4), (New-Object System.Drawing.PointF 10.7, 5.6),
  (New-Object System.Drawing.PointF 13.3, 5.6), (New-Object System.Drawing.PointF 13.9, 2.4)))
$g.DrawLine($pen, 10.6, 10.8, 10.6, 19.5)
$g.DrawLine($pen, 13.4, 10.8, 13.4, 19.5)
$g.DrawArc($pen, 10.6, 18.1, 2.8, 2.8, 0, 180)
Finish $p "change-fix"

Get-ChildItem $out | Select-Object Name, Length
