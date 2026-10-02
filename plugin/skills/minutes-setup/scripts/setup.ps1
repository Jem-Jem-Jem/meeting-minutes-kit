# Meeting-minutes setup wizard.
# Run this in YOUR OWN PowerShell window (it asks you questions). It will not work
# inside an AI agent's tool window (that has no keyboard input).
#
#   powershell -ExecutionPolicy Bypass -File setup.ps1
#
# What it does: checks your machine, installs only what is missing (with your OK),
# picks up the team files the maintainer shared, then walks you through the parts only
# you can do (HuggingFace token, signature), then proves the whole chain works.
# Safe to re-run: it skips finished steps.
param([string]$TeamFiles)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is 10x+ faster without the progress bar (PS 5.1)

$Here = $PSScriptRoot
$Kit = Get-Content (Join-Path $Here 'kit.json') -Raw | ConvertFrom-Json
$KitVersion = $Kit.kitVersion
$MinutesScripts = Join-Path (Split-Path (Split-Path $Here)) 'meeting-minutes\scripts'
$Data = if ($env:MINUTES_HOME) { $env:MINUTES_HOME } else { Join-Path $env:USERPROFILE '.claude\meeting-minutes' }
$VenvDir = Join-Path $Data 'venv'
$VenvPy = Join-Path $VenvDir 'Scripts\python.exe'
$Tools = Join-Path $Data 'tools'
New-Item -ItemType Directory -Force -Path $Data | Out-Null

function Say($t) { Write-Host $t }
function Head($t) { Write-Host ''; Write-Host ('=== ' + $t + ' ===') -ForegroundColor Cyan }
function Ok($t) { Write-Host ('  ok  ' + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ('  !!  ' + $t) -ForegroundColor Yellow }
function Bad($t) { Write-Host ('  XX  ' + $t) -ForegroundColor Red }
function YesNo($q, $defYes = $true) {
  $sfx = if ($defYes) { '[Y/n]' } else { '[y/N]' }
  while ($true) {
    $a = (Read-Host "$q $sfx").Trim().ToLower()
    if ($a -eq '') { return $defYes }
    if ($a -in 'y', 'yes') { return $true }
    if ($a -in 'n', 'no') { return $false }
  }
}
function Ask($q, $default = '') {
  $sfx = if ($default) { " [$default]" } else { '' }
  $a = (Read-Host "$q$sfx").Trim().Trim('"')
  if ($a -eq '') { return $default }
  return $a
}
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Add-UserPath($dir) {
  $old = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (($old -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', "$dir;$old", 'User') }
  Refresh-Path
}
function Write-Utf8($path, $text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false)) }
function Get-Preflight { (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here 'preflight.ps1') -Json | Out-String) | ConvertFrom-Json }
function Download($url, $out) {
  Say "  downloading $(Split-Path $url -Leaf) ..."
  try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 900; return (Test-Path $out) }
  catch { Bad "download failed: $($_.Exception.Message)"; return $false }
}
function Winget-Install($id, $label) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
  Say "  installing $label with winget ..."
  & winget install -e --id $id --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { Warn "winget could not install $label (code $LASTEXITCODE)"; return $false }  # -1978335189 = already installed
  Refresh-Path
  return $true
}
# Each installer tries winget first, then a direct download (for PCs without winget or where it is blocked).
function Install-Python {
  # Per-user install straight from python.org: needs no administrator rights and no winget.
  $v = $Kit.python.installVersion
  $exe = Join-Path $env:TEMP "python-$v-amd64.exe"
  if (Download "https://www.python.org/ftp/python/$v/python-$v-amd64.exe" $exe) {
    Say '  running the Python installer (per-user, no admin needed) ...'
    Start-Process -Wait -FilePath $exe -ArgumentList '/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_test=0', 'Include_launcher=1'
    Refresh-Path
    return $true
  }
  return (Winget-Install 'Python.Python.3.12' 'Python 3.12')
}
function Install-Zip-Tool($name, $url, $binPattern) {
  $zip = Join-Path $env:TEMP "$name.zip"
  if (-not (Download $url $zip)) { return $false }
  $dest = Join-Path $Tools $name
  Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  $bin = Get-ChildItem $dest -Recurse -File -Filter $binPattern | Select-Object -First 1
  if (-not $bin) { Bad "$name unpacked but $binPattern not found"; return $false }
  Add-UserPath $bin.DirectoryName
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  return $true
}
function Install-Ffmpeg {
  # Portable zip unpacked into the kit's own folder: no administrator rights needed.
  if (Install-Zip-Tool 'ffmpeg' 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' 'ffmpeg.exe') { return $true }
  return (Winget-Install 'Gyan.FFmpeg' 'ffmpeg')
}
function Install-Poppler {
  try {
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/oschwartz10612/poppler-windows/releases/latest' -UseBasicParsing -TimeoutSec 30
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if ($asset -and (Install-Zip-Tool 'poppler' $asset.browser_download_url 'pdftoppm.exe')) { return $true }
  } catch { Warn "poppler direct download failed: $($_.Exception.Message)" }
  return (Winget-Install 'oschwartz10612.Poppler' 'poppler')
}
function Pip($pipArgs) {
  & $VenvPy -m pip @pipArgs
  if ($LASTEXITCODE -ne 0) { Bad ('pip failed: ' + ($pipArgs -join ' ')); exit 1 }
}
function Expand-TeamSource($src) {
  # returns the folder that holds roster.local.md (unpacks a zip to a temp folder first)
  $folder = $src
  if ($src -like '*.zip') {
    $folder = Join-Path $env:TEMP 'minutes-team-files'
    Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -Path $src -DestinationPath $folder -Force
    $r = Get-ChildItem $folder -Recurse -File -Filter 'roster.local.md' | Select-Object -First 1
    if ($r) { $folder = $r.DirectoryName }
  }
  return $folder
}
function Get-BundleStamp($folder) {
  $p = Join-Path $folder 'bundle.json'
  if (Test-Path $p) { try { return [string](Get-Content $p -Raw | ConvertFrom-Json).builtAt } catch { } }
  return $null
}
function Import-TeamFiles($folder) {
  foreach ($f in 'roster.local.md', 'team.local.json') {
    $p = Join-Path $folder $f
    if (-not (Test-Path $p)) { Bad "Not found: $p"; return $false }
    Copy-Item $p (Join-Path $Data $f) -Force
    Ok "copied $f"
  }
  if (Test-Path (Join-Path $folder 'bundle.json')) { Copy-Item (Join-Path $folder 'bundle.json') (Join-Path $Data 'team-bundle.json') -Force }
  $vp = Join-Path $folder 'speaker_profiles.json'
  $local = Join-Path $Data 'speaker_profiles.json'
  if (Test-Path $vp) {
    if (-not (Test-Path $local)) {
      Say 'A voice-profile file is included. It lets the tool name the speakers automatically (works best when recorded on the same microphones).'
      if (YesNo 'Use it?') { Copy-Item $vp $local -Force; Ok 'voice profiles installed' }
    } else {
      # keep whatever this PC has learned; only add people it does not know yet
      & $VenvPy (Join-Path $MinutesScripts 'speaker_profiles.py') merge $vp 2>$null | Where-Object { $_ -like 'merged*' } | ForEach-Object { Ok $_ }
    }
  }
  # people the team file says to forget (left the team, or withdrew consent): delete their voice prints here too
  $gone = @((Get-Content (Join-Path $Data 'team.local.json') -Raw -Encoding UTF8 | ConvertFrom-Json).removed_voices | Where-Object { $_ })
  if ($gone.Count -gt 0 -and (Test-Path $local)) {
    & $VenvPy (Join-Path $MinutesScripts 'speaker_profiles.py') remove @gone 2>$null | Where-Object { $_ -like 'removed*' } | ForEach-Object { Ok $_ }
  }
  return $true
}

Write-Host ''
Write-Host 'Meeting-minutes setup wizard' -ForegroundColor Cyan
Write-Host "kit $KitVersion   data folder: $Data"

# ---------------------------------------------------------------- 1. machine check
Head '1/7  Checking this machine'
$pf = Get-Preflight
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here 'preflight.ps1') | Out-Host
if ($pf.blockers.Count -gt 0) {
  Bad 'Fix the blockers above, then run this wizard again.'
  exit 1
}
if ($pf.device -eq 'cpu') {
  Warn 'No NVIDIA GPU: transcription runs on the CPU. Same result, slower. The wizard will measure the speed and let you choose a model.'
}

# ---------------------------------------------------------------- 2. plan + consent
Head '2/7  What will be installed'
if ($pf.toInstall.Count -eq 0) {
  Ok 'Everything is already installed.'
} else {
  $sizes = @{ 'python' = 'about 100 MB'; 'ffmpeg' = 'about 150 MB'; 'poppler' = 'about 40 MB'; 'python-packages' = 'about 2 to 3 GB, into its own folder (does not touch your other Python)' }
  foreach ($t in $pf.toInstall) { Say ("  - {0}: {1}" -f $t, $sizes[$t]) }
  Say '  Speech models download on first use (about 3 to 4 GB more).'
  Say '  None of this needs administrator rights: everything goes into your own user folders.'
  if (-not (YesNo 'Install these now?')) { Say 'Nothing changed. Run the wizard again when ready.'; exit 0 }
}

# ---------------------------------------------------------------- 3. install
Head '3/7  Installing'
if ($pf.toInstall -contains 'python') { if (-not (Install-Python)) { Bad 'Could not install Python.'; exit 1 } }
if ($pf.toInstall -contains 'ffmpeg') { if (-not (Install-Ffmpeg)) { Bad 'Could not install ffmpeg.'; exit 1 } }
if ($pf.toInstall -contains 'poppler') { if (-not (Install-Poppler)) { Bad 'Could not install poppler.'; exit 1 } }

if ($pf.toInstall -contains 'python-packages') {
  $pf2 = Get-Preflight
  if (-not $pf2.python) { Bad 'Python is still not visible. Close this window, open a new PowerShell, run the wizard again.'; exit 1 }
  if (-not (Test-Path $VenvPy)) {
    Say "  creating private Python environment ($($pf2.python.version)) ..."
    & $pf2.python.path -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { Bad 'venv creation failed'; exit 1 }
  }
  $pin = $Kit.pins
  Pip @('install', '--upgrade', 'pip')
  if ($pf.device -eq 'cuda') {
    Say '  installing PyTorch (NVIDIA build) ...'
    Pip @('install', "torch==$($pin.torch)", "torchaudio==$($pin.torchaudio)", '--index-url', 'https://download.pytorch.org/whl/cu128')
    Pip @('install', 'nvidia-cublas-cu12', 'nvidia-cudnn-cu12')
  } else {
    Say '  installing PyTorch (CPU build) ...'
    Pip @('install', "torch==$($pin.torch)", "torchaudio==$($pin.torchaudio)", '--index-url', 'https://download.pytorch.org/whl/cpu')
  }
  Say '  installing speech and document packages ...'
  Pip @('install', "whisperx==$($pin.whisperx)", "pyannote-audio==$($pin.'pyannote-audio')", "faster-whisper==$($pin.'faster-whisper')",
        "python-docx==$($pin.'python-docx')", "openpyxl==$($pin.openpyxl)", 'markitdown[xlsx,docx,pdf]')
}
$pf = Get-Preflight
if ($pf.missingPackages.Count -gt 0) { Bad ('Still missing: ' + ($pf.missingPackages -join ', ')); exit 1 }
if (-not $pf.ffmpeg -or -not $pf.ffprobe) { Bad 'ffmpeg is installed but not visible yet. Close this window, open a new PowerShell, run the wizard again.'; exit 1 }
Ok 'All dependencies installed.'

# ---------------------------------------------------------------- 4. team files
Head '4/7  Team files from the maintainer'
$haveTeam = (Test-Path (Join-Path $Data 'roster.local.md')) -and (Test-Path (Join-Path $Data 'team.local.json'))
$candidate = if ($TeamFiles) { $TeamFiles } elseif ($pf.teamFilesFound) { $pf.teamFilesFound.path } else { '' }
if (-not $haveTeam) {
  Say 'The maintainer shares the team files on Teams (minutes-team-files.zip, or a folder with roster.local.md and team.local.json).'
  if ($candidate) { Say "  found one already downloaded: $candidate" }
  while ($true) {
    $src = Ask 'Path to the zip or folder (download it first if you have not)' $candidate
    if (-not $src -or -not (Test-Path $src)) { Bad 'Not found, try again.'; continue }
    if (Import-TeamFiles (Expand-TeamSource $src)) { break }
  }
} elseif ($candidate -and (Test-Path $candidate)) {
  # already set up: offer an update only when the bundle on disk is newer than the one installed
  $folder = Expand-TeamSource $candidate
  $newStamp = Get-BundleStamp $folder
  $oldStamp = $null
  $oldFile = Join-Path $Data 'team-bundle.json'
  if (Test-Path $oldFile) { try { $oldStamp = [string](Get-Content $oldFile -Raw | ConvertFrom-Json).builtAt } catch { } }
  if ($newStamp -and ((-not $oldStamp) -or ($newStamp -gt $oldStamp))) {
    Say "A newer team-files bundle was found ($newStamp): $candidate"
    if (YesNo 'Update the roster and team settings from it?') { [void](Import-TeamFiles $folder) }
  } else { Ok 'roster and team file already in place and up to date.' }
} else { Ok 'roster and team file already in place.' }

# config.json = this scribe's details + the team file (the team file wins for the keys it defines, so updates apply)
$cfgPath = Join-Path $Data 'config.json'
$team = Get-Content (Join-Path $Data 'team.local.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$cfg = @{}
if (Test-Path $cfgPath) { foreach ($p in (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties) { $cfg[$p.Name] = $p.Value } }
foreach ($p in $team.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
if (-not $cfg['scribe_name']) { $cfg['scribe_name'] = Ask 'Your full name as it should appear on the minutes' }
if (-not $cfg['scribe_title']) { $cfg['scribe_title'] = Ask 'Your job title' }
if (-not $cfg['model']) { $cfg['model'] = 'large-v3' }
if (-not $cfg['device']) { $cfg['device'] = 'auto' }
Write-Utf8 $cfgPath (($cfg | ConvertTo-Json -Depth 5))
Ok "saved $cfgPath"

# ---------------------------------------------------------------- 5. signature
Head '5/7  Your signature image'
$sigPath = Join-Path $Data 'signature.png'
if (Test-Path $sigPath) { Ok 'signature.png already in place.' }
else {
  Say 'A photo or scan of your signature on white paper, cropped close. PNG or JPG.'
  while ($true) {
    $src = Ask 'Path to your signature image'
    if (-not (Test-Path $src)) { Bad 'File not found, try again.'; continue }
    try {
      Add-Type -AssemblyName System.Drawing
      $img = [System.Drawing.Image]::FromFile((Resolve-Path $src).Path)
      $img.Save($sigPath, [System.Drawing.Imaging.ImageFormat]::Png)
      $img.Dispose()
      Ok 'signature saved.'
      break
    } catch { Bad 'That file is not a readable image, try again.' }
  }
}

# ---------------------------------------------------------------- 6. HuggingFace
Head '6/7  HuggingFace access (identifies who is speaking)'
function Test-HF($tok) {
  $h = @{ Authorization = "Bearer $tok" }
  try { $w = Invoke-RestMethod -Uri 'https://huggingface.co/api/whoami-v2' -Headers $h -TimeoutSec 15 } catch { return 'token' }
  try { Invoke-WebRequest -Uri 'https://huggingface.co/pyannote/speaker-diarization-community-1/resolve/main/config.yaml' -Headers $h -UseBasicParsing -TimeoutSec 15 | Out-Null; return "ok:$($w.name)" }
  catch { return 'terms' }
}
$tok = [Environment]::GetEnvironmentVariable('HF_TOKEN', 'User')
$state = if ($tok) { Test-HF $tok } else { 'none' }
if ($state -like 'ok:*') { Ok ("token works (" + $state.Substring(3) + ")") }
else {
  Say 'This is free. It needs a free HuggingFace account (Google sign-in works), one licence click, and one token.'
  Say '  a) Create the account (skip if you have one):  https://huggingface.co/join'
  Say '  b) Open this page, click "Agree and access repository":'
  Say '     https://huggingface.co/pyannote/speaker-diarization-community-1'
  Say '  c) Create a token: https://huggingface.co/settings/tokens  ->  Create new token -> type "Read" -> copy it.'
  if (YesNo 'Open these pages in your browser now?') {
    Start-Process 'https://huggingface.co/join'
    Start-Process 'https://huggingface.co/pyannote/speaker-diarization-community-1'
    Start-Process 'https://huggingface.co/settings/tokens'
  }
  while ($true) {
    $sec = Read-Host 'Paste the token here (typing is hidden), or press Enter to skip' -AsSecureString
    $tok = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    if (-not $tok) { Warn 'Skipped. Speaker names will not work until this is done. Re-run the wizard later.'; break }
    $r = Test-HF $tok
    if ($r -like 'ok:*') {
      [Environment]::SetEnvironmentVariable('HF_TOKEN', $tok, 'User'); $env:HF_TOKEN = $tok
      Ok ("token works and is saved (" + $r.Substring(3) + ")"); break
    }
    if ($r -eq 'terms') { Bad 'Token is valid but you have not accepted the licence on the pyannote page (step b). Do that, then paste again.' }
    else { Bad 'HuggingFace rejected that token. Check you copied all of it.' }
  }
}
$tok = $null

# ---------------------------------------------------------------- 7. proof
Head '7/7  Proving the whole chain works'
if (-not $env:HF_TOKEN) { $env:HF_TOKEN = [Environment]::GetEnvironmentVariable('HF_TOKEN', 'User') }
$skipDiar = -not $env:HF_TOKEN
if ($skipDiar) { Warn 'No token: testing transcription without speaker labels.' }

Say '  a) document builder + Word + page render'
$tmp = Join-Path $env:TEMP 'minutes-proof'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$demo = Join-Path $tmp 'proof.docx'
& $VenvPy (Join-Path $MinutesScripts 'build_minutes.py') (Join-Path $MinutesScripts 'meeting.example.json') $demo
if ($LASTEXITCODE -ne 0) { Bad 'document builder failed'; exit 1 }
& $VenvPy (Join-Path $MinutesScripts 'sign_minutes.py') $demo --date 1/1/2030
if ($LASTEXITCODE -ne 0) { Bad 'signing step failed'; exit 1 }
if ($env:MINUTES_TEST_SKIP_WORD -eq '1') { Warn 'MINUTES_TEST_SKIP_WORD is set: skipping the Word render (test machines only).' }
else {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $MinutesScripts 'render_pdf.ps1') $demo | Out-Host
  if (-not (Test-Path (Join-Path $tmp 'proof.pdf'))) { Bad 'Word could not export a PDF. Open Word once manually (sign in / accept prompts), then re-run.'; exit 1 }
  Ok 'document builds, signs, and renders in Word.'
}

Say '  b) two-microphone merge'
& $VenvPy (Join-Path $Here 'smoke_test.py') --merge-check
if ($LASTEXITCODE -ne 0) { Bad 'The two-microphone merge check failed. Copy the output above and send it to the maintainer.'; exit 1 }
Ok 'two-microphone merge works.'

function Run-Smoke($model, $repeat = 1) {
  $a = @((Join-Path $Here 'smoke_test.py'), '--repeat', $repeat)
  if ($model) { $a += @('--model', $model) }
  if ($skipDiar) { $a += '--no-diarize' }
  $out = & $VenvPy @a | Tee-Object -Variable lines
  $line = $lines | Where-Object { $_ -like 'SMOKE_RESULT *' } | Select-Object -Last 1
  if (-not $line) { return $null }
  return ($line.Substring(13) | ConvertFrom-Json)
}
$model = $cfg['model']
Say "  c) speech-to-text with model '$model' (first run downloads models, this can take a while)"
$warm = Run-Smoke $model
if (-not $warm -or -not $warm.ok) { Bad 'Transcription test failed. Copy the output above and send it to the maintainer.'; exit 1 }
Say '     timing runs (short clip, then a longer one, to separate fixed start-up cost from real speed) ...'
$res = Run-Smoke $model 1
$long = Run-Smoke $model 3
if (-not $res -or -not $res.ok -or -not $long -or -not $long.ok) { Bad 'Transcription timing run failed.'; exit 1 }
$slope = ($long.elapsed_s - $res.elapsed_s) / ($long.audio_s - $res.audio_s)      # seconds of work per second of audio
if ($slope -lt 0.05) { $slope = 0.05 }
$overhead = [math]::Max(0, $res.elapsed_s - $slope * $res.audio_s)
$est = [math]::Round(($overhead + $slope * 3600) / 60, 0)
Ok ("works. A 60 minute meeting will take about $est minutes to transcribe on this machine (rough estimate).")
if ($res.speakers.Count -gt 1) { Ok ('speaker separation works (' + ($res.speakers -join ', ') + ')') }
elseif (-not $skipDiar) { Warn 'Only one speaker label came back on the two-voice test. Tell the maintainer.' }

if ($est -gt 90 -and $model -eq 'large-v3') {
  Warn 'That is slow. A smaller model is faster but makes a few more mistakes.'
  Say '  1) keep large-v3 (most accurate)   2) medium.en (about 3x faster)   3) small.en (about 6x faster)'
  $c = Ask 'Choose 1, 2 or 3' '1'
  $new = @{ '1' = 'large-v3'; '2' = 'medium.en'; '3' = 'small.en' }[$c]
  if ($new -and $new -ne $model) { $cfg['model'] = $new; Write-Utf8 $cfgPath (($cfg | ConvertTo-Json -Depth 5)); Ok "model set to $new" }
}

$done = @{ kitVersion = $KitVersion; date = (Get-Date -Format 's'); device = $pf.device; model = $cfg['model']; rtf = [math]::Round($slope, 2); hfToken = [bool]$env:HF_TOKEN }
Write-Utf8 (Join-Path $Data 'setup-complete.json') (($done | ConvertTo-Json))
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
if (-not (Test-Path (Join-Path $Data 'speaker_profiles.json'))) {
  Say 'Note: no voice profiles yet. After your first meeting the tool will show you who each unknown speaker is and save their voices for next time.'
}
Say 'Go back to your AI agent (restart it once so it sees the new settings) and say:  write the meeting minutes'
