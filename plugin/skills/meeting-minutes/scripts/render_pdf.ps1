# Render a docx to PDF through desktop Word, then to PNG pages with pdftoppm.
# Rough sanity check only: Word's own on-screen layout is the truth (see references/format.md).
# Usage: powershell -ExecutionPolicy Bypass -File render_pdf.ps1 <docx> [-Dpi 100]
param([Parameter(Mandatory = $true)][string]$Docx, [int]$Dpi = 100)
$Docx = (Resolve-Path $Docx).Path
$pdf = [IO.Path]::ChangeExtension($Docx, '.pdf')
$word = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  $doc = $word.Documents.Open($Docx, $false, $true)   # read-only
  $doc.SaveAs2($pdf, 17)                               # wdFormatPDF
  $doc.Close($false)
} finally {
  if ($word) { $word.Quit() }
}
Write-Host "PDF: $pdf"
$pp = (Get-Command pdftoppm -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pp) { Write-Host 'pdftoppm not found: PDF made, no PNG pages.'; exit 0 }
$prefix = Join-Path (Split-Path $pdf) ([IO.Path]::GetFileNameWithoutExtension($pdf) + '-page')
& $pp -png -r $Dpi $pdf $prefix
Get-ChildItem ((Split-Path $pdf)) -Filter (([IO.Path]::GetFileNameWithoutExtension($pdf)) + '-page*.png') | ForEach-Object { Write-Host "PNG: $($_.FullName)" }
