# Machine check. Read-only: installs nothing, changes nothing.
#   powershell -ExecutionPolicy Bypass -File preflight.ps1 [-Json]   full machine report
#   powershell -ExecutionPolicy Bypass -File preflight.ps1 -Gate     quick "can we work?" check, prints READY / NOT READY
# Works on Windows PowerShell 5.1. Exit code 0 (report) / 0 READY, 1 NOT READY (-Gate).
param([switch]$Json, [switch]$Gate)
$ErrorActionPreference = 'SilentlyContinue'

$Data = if ($env:MINUTES_HOME) { $env:MINUTES_HOME } else { Join-Path $env:USERPROFILE '.claude\meeting-minutes' }
$VenvPy = Join-Path $Data 'venv\Scripts\python.exe'
$Kit = Get-Content (Join-Path $PSScriptRoot 'kit.json') -Raw | ConvertFrom-Json
$Uv = Join-Path $Data 'bin\uv.exe'
$LockFile = Join-Path (Split-Path $PSScriptRoot) 'env\uv.lock'

function Find-Cmd($n) { $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $c.Source } else { $null } }

# ---- is the Python environment exactly the kit's locked one? (used by both modes)
# The wizard writes venv\.kit-lock (the SHA-256 of the env\uv.lock it installed) after a successful install.
function Test-Env {
  $stamp = Join-Path $Data 'venv\.kit-lock'
  if (-not (Test-Path $VenvPy) -or -not (Test-Path $stamp)) { return $false }
  return ((Get-Content $stamp -Raw).Split(' ')[0].Trim() -eq (Get-FileHash $LockFile -Algorithm SHA256).Hash)
}

# ---- quick gate: is the tool ready to produce minutes right now?
if ($Gate) {
  $why = @()
  $done = Join-Path $Data 'setup-complete.json'
  if (-not (Test-Path $done)) { $why += 'setup has not been completed' }
  else {
    $d = Get-Content $done -Raw | ConvertFrom-Json
    if ($d.kitVersion -ne $Kit.kitVersion) { $why += "kit was updated ($($d.kitVersion) -> $($Kit.kitVersion)); re-run the setup wizard" }
  }
  if (-not (Test-Env)) { $why += 'Python environment missing or not the locked one' }
  foreach ($f in 'config.json', 'roster.local.md', 'signature.png') { if (-not (Test-Path (Join-Path $Data $f))) { $why += "$f missing" } }
  if (-not (Find-Cmd 'ffmpeg')) { $why += 'ffmpeg not on PATH' }
  if ($why.Count) { Write-Host ('NOT READY: ' + ($why -join '; ')); exit 1 }
  # a newer team-files bundle (roster / approver / voice prints) sitting in Downloads etc.? tell the user, still READY
  $note = $null
  try {
    $oldStamp = $null
    $of = Join-Path $Data 'team-bundle.json'
    if (Test-Path $of) { $oldStamp = [string](Get-Content $of -Raw | ConvertFrom-Json).builtAt }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($r in 'Downloads', 'Desktop', 'Documents') {
      $dir = Join-Path $env:USERPROFILE $r
      if (-not (Test-Path $dir)) { continue }
      foreach ($z in (Get-ChildItem $dir -Filter 'minutes-team-files*.zip' -File -ErrorAction SilentlyContinue)) {
        $zip = [IO.Compression.ZipFile]::OpenRead($z.FullName)
        try {
          $e = $zip.Entries | Where-Object { $_.Name -eq 'bundle.json' } | Select-Object -First 1
          if ($e) {
            $sr = New-Object IO.StreamReader($e.Open()); $stamp = [string]((($sr.ReadToEnd()) | ConvertFrom-Json).builtAt); $sr.Dispose()
            if ($stamp -and ((-not $oldStamp) -or ($stamp -gt $oldStamp))) { $note = "a newer team-files bundle is at $($z.FullName); re-run the setup wizard to update the roster and team settings" }
          }
        } finally { $zip.Dispose() }
      }
    }
  } catch { }
  Write-Host 'READY'
  if ($note) { Write-Host ('NOTE: ' + $note) }
  exit 0
}

$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem
$drive = (Split-Path $env:USERPROFILE -Qualifier)
$disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $drive)
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name })
$nvsmi = Find-Cmd 'nvidia-smi'
$nvName = $null
if ($nvsmi) { $nvName = (& $nvsmi --query-gpu=name,memory.total --format=csv,noheader 2>$null | Select-Object -First 1) }

$uvOk = Test-Path $Uv
$envOk = Test-Env

$word = (Test-Path 'HKLM:\SOFTWARE\Classes\Word.Application\CLSID') -or ($env:MINUTES_TEST_SKIP_WORD -eq '1')   # the env flag is for testing installs on a PC/VM without Word
$hf = [Environment]::GetEnvironmentVariable('HF_TOKEN', 'User')
if (-not $hf) { $hf = $env:HF_TOKEN }

function Test-Url($u) { try { $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 8; return ($r.StatusCode -lt 400) } catch { return $false } }
$net = [ordered]@{}
foreach ($h in 'pypi.org', 'huggingface.co', 'download.pytorch.org', 'files.pythonhosted.org', 'github.com') { $net[$h] = Test-Url ("https://$h") }

$files = [ordered]@{}
foreach ($f in 'config.json', 'roster.local.md', 'signature.png', 'speaker_profiles.json', 'setup-complete.json') { $files[$f] = Test-Path (Join-Path $Data $f) }

# has the maintainer's team-file bundle already been downloaded somewhere obvious?
$teamFiles = $null
if ($true) {
  $roots = @('Downloads', 'Desktop', 'Documents') | ForEach-Object { Join-Path $env:USERPROFILE $_ }
  $roots += @(Get-ChildItem $env:USERPROFILE -Directory -Filter 'OneDrive*' | ForEach-Object { $_.FullName })
  foreach ($r in $roots) {
    if (-not (Test-Path $r) -or $teamFiles) { continue }
    $hit = Get-ChildItem $r -Recurse -Depth 3 -File -Include 'roster.local.md', 'minutes-team-files*.zip' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($hit) {
      $teamFiles = if ($hit.Extension -eq '.zip') { [ordered]@{ kind = 'zip'; path = $hit.FullName } } else { [ordered]@{ kind = 'folder'; path = $hit.DirectoryName } }
    }
  }
}

$ffmpeg = Find-Cmd 'ffmpeg'
$ffprobe = Find-Cmd 'ffprobe'
$poppler = Find-Cmd 'pdftoppm'

$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$freeGB = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { $null }

$blockers = @()
if ($os.OSArchitecture -notmatch '64') { $blockers += 'Needs 64-bit Windows.' }
if ([int]$os.BuildNumber -lt 17763) { $blockers += 'Windows 10 version 1809 or newer is required.' }
if (-not $word) { $blockers += 'Microsoft Word (desktop) not found. Needed to check page layout. Cannot be auto-installed.' }
if ($ramGB -lt 7.5) { $blockers += "Only $ramGB GB RAM. 8 GB is the minimum for transcription." }
if ($freeGB -ne $null -and $freeGB -lt 15) { $blockers += "Only $freeGB GB free on $drive. About 15 GB is needed (packages plus speech models)." }
if ($env:USERPROFILE -match '[^\x00-\x7F]') { $blockers += 'Your Windows user folder path has non-English characters. Python packages may fail. Ask the maintainer.' }
if (-not $net['pypi.org'] -or -not $net['huggingface.co'] -or -not $net['github.com']) { $blockers += 'Cannot reach pypi.org, huggingface.co or github.com. Check the network or proxy.' }

$toInstall = @()
if (-not $uvOk) { $toInstall += 'uv' }
if (-not $ffmpeg -or -not $ffprobe) { $toInstall += 'ffmpeg' }
if (-not $poppler) { $toInstall += 'poppler' }
if (-not $envOk) { $toInstall += 'python-packages' }

$report = [ordered]@{
  kitVersion = $Kit.kitVersion
  os = "$($os.Caption) build $($os.BuildNumber) $($os.OSArchitecture)"
  powershell = $PSVersionTable.PSVersion.ToString()
  cpu = "$($cpu.Name.Trim()) ($($cpu.NumberOfLogicalProcessors) threads)"
  cpuThreads = [int]$cpu.NumberOfLogicalProcessors
  ramGB = $ramGB
  freeDiskGB = $freeGB
  gpu = $gpus
  nvidiaGpu = $nvName
  device = $(if ($nvsmi -and $nvName -and $env:MINUTES_FORCE_CPU -ne '1') { 'cuda' } else { 'cpu' })   # MINUTES_FORCE_CPU=1 is for testing the no-GPU path
  uv = $uvOk
  environment = $envOk
  ffmpeg = $ffmpeg
  ffprobe = $ffprobe
  poppler = $poppler
  word = $word
  hfTokenSet = [bool]$hf
  network = $net
  dataDir = $Data
  files = $files
  teamFilesFound = $teamFiles
  blockers = $blockers
  toInstall = $toInstall
}

if ($Json) { $report | ConvertTo-Json -Depth 5; return }

function Line($ok, $label, $detail) { $m = if ($ok) { '[ ok ]' } else { '[miss]' }; Write-Host ("{0} {1,-16} {2}" -f $m, $label, $detail) }
Write-Host ''
Write-Host "Machine check (kit $($Kit.kitVersion))"
Write-Host '-------------'
Line $true 'system' "$($report.os), $($report.cpu), $ramGB GB RAM, $freeGB GB free on $drive"
Line $true 'gpu' $(if ($nvName) { "NVIDIA: $nvName (fast path)" } else { "no NVIDIA GPU ($($gpus -join ', ')). CPU path: works, slower." })
Line $uvOk 'uv' $(if ($uvOk) { 'present (installs the locked Python environment)' } else { 'not yet' })
Line $envOk 'python env' $(if ($envOk) { 'matches the kit lock' } else { 'not installed or out of date' })
Line ([bool]($ffmpeg -and $ffprobe)) 'ffmpeg' $(if ($ffmpeg -and $ffprobe) { $ffmpeg } else { 'not found (ffmpeg + ffprobe)' })
Line ([bool]$poppler) 'poppler' $(if ($poppler) { $poppler } else { 'not found (pdftoppm)' })
Line $word 'Word' $(if ($word) { 'installed' } else { 'NOT FOUND (required)' })
Line ([bool]$hf) 'HF_TOKEN' $(if ($hf) { 'set' } else { 'not set (wizard will guide you)' })
foreach ($k in $files.Keys) { Line $files[$k] $k $(if ($files[$k]) { 'present' } else { 'not yet' }) }
if ($teamFiles) { Write-Host ("       team files look already downloaded: $($teamFiles.path)") }
Write-Host ''
if ($blockers.Count) { Write-Host 'BLOCKERS:'; $blockers | ForEach-Object { Write-Host "  - $_" } } else { Write-Host 'No blockers.' }
if ($toInstall.Count) { Write-Host ('To install: ' + ($toInstall -join ', ')) } else { Write-Host 'Nothing to install.' }
