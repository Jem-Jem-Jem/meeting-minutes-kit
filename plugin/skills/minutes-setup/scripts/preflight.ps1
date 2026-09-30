# Machine check. Read-only: installs nothing, changes nothing.
#   powershell -ExecutionPolicy Bypass -File preflight.ps1 [-Json]   full machine report
#   powershell -ExecutionPolicy Bypass -File preflight.ps1 -Gate     quick "can we work?" check, prints READY / NOT READY
# Works on Windows PowerShell 5.1. Exit code 0 (report) / 0 READY, 1 NOT READY (-Gate).
param([switch]$Json, [switch]$Gate)
$ErrorActionPreference = 'SilentlyContinue'

$Data = if ($env:MINUTES_HOME) { $env:MINUTES_HOME } else { Join-Path $env:USERPROFILE '.claude\meeting-minutes' }
$VenvPy = Join-Path $Data 'venv\Scripts\python.exe'
$Kit = Get-Content (Join-Path $PSScriptRoot 'kit.json') -Raw | ConvertFrom-Json

function Find-Cmd($n) { $c = Get-Command $n -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $c.Source } else { $null } }

# ---- installed pins vs kit.json (used by both modes)
function Get-PackageState {
  $pkgs = @{}
  $bad = @()
  if (Test-Path $VenvPy) {
    $j = & $VenvPy -m pip list --format=json 2>$null | Out-String
    if ($j) { foreach ($p in ($j | ConvertFrom-Json)) { $pkgs[$p.name.ToLower().Replace('_', '-')] = ($p.version -replace '\+.*$', '') } }
  }
  foreach ($p in $Kit.pins.PSObject.Properties) {
    if ($pkgs[$p.Name] -ne $p.Value) { $bad += $p.Name }
  }
  foreach ($u in $Kit.unpinned) { if (-not $pkgs[$u]) { $bad += $u } }
  return $bad
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
  if (-not (Test-Path $VenvPy)) { $why += 'Python environment missing' }
  else { $bad = Get-PackageState; if ($bad.Count) { $why += ('packages missing or wrong version: ' + ($bad -join ', ')) } }
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

function Get-PyInfo($exe, $prefixArgs) {
  if (-not $exe) { return $null }
  $out = & $exe @prefixArgs -c "import sys,struct;print('%d.%d.%d|%d|%s'%(sys.version_info[0],sys.version_info[1],sys.version_info[2],struct.calcsize('P')*8,sys.executable))" 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }   # Microsoft Store stub fails here
  $p = ($out | Select-Object -Last 1) -split '\|'
  $v = [version]$p[0]
  [pscustomobject]@{ version = $p[0]; bits = [int]$p[1]; path = $p[2]
    ok = ($v.Major -eq 3 -and $v.Minor -ge $Kit.python.minMinor -and $v.Minor -le $Kit.python.maxMinor -and [int]$p[1] -eq 64) }
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

# python: prefer 'py' launcher versions, then PATH
$py = $null
foreach ($ver in '3.12', '3.13', '3.11', '3.10') {
  $pyl = Find-Cmd 'py'
  if ($pyl) { $i = Get-PyInfo $pyl @("-$ver"); if ($i -and $i.ok) { $py = $i; break } }
}
if (-not $py) { foreach ($n in 'python', 'python3') { $i = Get-PyInfo (Find-Cmd $n) @(); if ($i -and $i.ok) { $py = $i; break } } }
$pyAny = $null
if (-not $py) { $i = Get-PyInfo (Find-Cmd 'python') @(); if ($i) { $pyAny = $i } }

$venvOk = Test-Path $VenvPy
$missingPkgs = @(Get-PackageState)

$word = (Test-Path 'HKLM:\SOFTWARE\Classes\Word.Application\CLSID') -or ($env:MINUTES_TEST_SKIP_WORD -eq '1')   # the env flag is for testing installs on a PC/VM without Word
$hf = [Environment]::GetEnvironmentVariable('HF_TOKEN', 'User')
if (-not $hf) { $hf = $env:HF_TOKEN }

function Test-Url($u) { try { $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 8; return ($r.StatusCode -lt 400) } catch { return $false } }
$net = [ordered]@{}
foreach ($h in 'pypi.org', 'huggingface.co', 'download.pytorch.org', 'files.pythonhosted.org') { $net[$h] = Test-Url ("https://$h") }

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

$winget = Find-Cmd 'winget'
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
if (-not $net['pypi.org'] -or -not $net['huggingface.co']) { $blockers += 'Cannot reach pypi.org or huggingface.co. Check the network or proxy.' }

$toInstall = @()
if (-not $py) { $toInstall += 'python' }
if (-not $ffmpeg -or -not $ffprobe) { $toInstall += 'ffmpeg' }
if (-not $poppler) { $toInstall += 'poppler' }
if (-not $venvOk -or $missingPkgs.Count -gt 0) { $toInstall += 'python-packages' }

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
  winget = [bool]$winget
  python = $py
  pythonUnsupported = $pyAny
  venv = $venvOk
  missingPackages = $missingPkgs
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
Line ([bool]$py) 'python' $(if ($py) { "$($py.version) at $($py.path)" } elseif ($pyAny) { "found $($pyAny.version), unsupported (need 3.10 to 3.13, 64-bit)" } else { 'not found' })
Line $venvOk 'kit venv' $(if ($venvOk) { 'present' } else { 'not created yet' })
Line ($missingPkgs.Count -eq 0 -and $venvOk) 'packages' $(if ($missingPkgs.Count) { 'missing/wrong: ' + ($missingPkgs -join ', ') } else { 'all pinned versions present' })
Line ([bool]($ffmpeg -and $ffprobe)) 'ffmpeg' $(if ($ffmpeg -and $ffprobe) { $ffmpeg } else { 'not found (ffmpeg + ffprobe)' })
Line ([bool]$poppler) 'poppler' $(if ($poppler) { $poppler } else { 'not found (pdftoppm)' })
Line $word 'Word' $(if ($word) { 'installed' } else { 'NOT FOUND (required)' })
Line ([bool]$winget) 'winget' $(if ($winget) { 'available' } else { 'not found (the wizard will download installers directly)' })
Line ([bool]$hf) 'HF_TOKEN' $(if ($hf) { 'set' } else { 'not set (wizard will guide you)' })
foreach ($k in $files.Keys) { Line $files[$k] $k $(if ($files[$k]) { 'present' } else { 'not yet' }) }
if ($teamFiles) { Write-Host ("       team files look already downloaded: $($teamFiles.path)") }
Write-Host ''
if ($blockers.Count) { Write-Host 'BLOCKERS:'; $blockers | ForEach-Object { Write-Host "  - $_" } } else { Write-Host 'No blockers.' }
if ($toInstall.Count) { Write-Host ('To install: ' + ($toInstall -join ', ')) } else { Write-Host 'Nothing to install.' }
