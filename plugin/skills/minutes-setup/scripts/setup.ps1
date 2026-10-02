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
$Uv = Join-Path $Data 'bin\uv.exe'
$EnvDir = Join-Path (Split-Path $Here) 'env'
$LockFile = Join-Path $EnvDir 'uv.lock'
# uv keeps its Python, its download cache and the environment inside the data folder, and ignores any
# uv settings elsewhere on this PC (so nothing can point it at another package index).
$env:UV_PYTHON_INSTALL_DIR = Join-Path $Data 'python'
$env:UV_CACHE_DIR = Join-Path $Data 'uv-cache'
$env:UV_PROJECT_ENVIRONMENT = $VenvDir
$env:UV_PYTHON_PREFERENCE = 'only-managed'
$env:UV_NO_CONFIG = '1'
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
function Get-Verified($name, $spec) {
  # download a pinned file and refuse it unless its SHA-256 matches kit.json
  $out = Join-Path $env:TEMP (Split-Path $spec.url -Leaf)
  if (-not (Download $spec.url $out)) { return $null }
  if ((Get-FileHash $out -Algorithm SHA256).Hash -ne $spec.sha256) {
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    Bad "$name download does not match its expected checksum. Refused, nothing installed. Tell the maintainer."
    return $null
  }
  return $out
}
function Install-Zip-Tool($name) {
  # portable zip unpacked into the data folder: no administrator rights needed
  $spec = $Kit.$name
  $zip = Get-Verified $name $spec
  if (-not $zip) { return $false }
  $dest = Join-Path $Tools $name
  Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  $bin = Get-ChildItem $dest -Recurse -File -Filter $spec.bin | Select-Object -First 1
  if (-not $bin) { Bad "$name unpacked but $($spec.bin) not found"; return $false }
  Add-UserPath $bin.DirectoryName
  return $true
}
function Install-Uv {
  $zip = Get-Verified 'uv' $Kit.uv
  if (-not $zip) { return $false }
  Expand-Archive -Path $zip -DestinationPath (Split-Path $Uv) -Force
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  return (Test-Path $Uv)
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
  $sizes = @{ 'uv' = 'about 20 MB (the tool that installs the Python parts)'; 'ffmpeg' = 'about 150 MB'; 'poppler' = 'about 40 MB'; 'python-packages' = 'about 2 to 3 GB, with its own copy of Python (does not touch any other Python on this PC)' }
  foreach ($t in $pf.toInstall) { Say ("  - {0}: {1}" -f $t, $sizes[$t]) }
  Say '  Speech models download on first use (about 3 to 4 GB more).'
  Say '  None of this needs administrator rights. It all goes into the data folder, and every download is checked'
  Say '  against a fixed checksum before it is used.'
  if (-not (YesNo 'Install these now?')) { Say 'Nothing changed. Run the wizard again when ready.'; exit 0 }
}

# ---------------------------------------------------------------- 3. install
Head '3/7  Installing'
if ($pf.toInstall -contains 'uv') { if (-not (Install-Uv)) { Bad 'Could not install uv.'; exit 1 } }
if ($pf.toInstall -contains 'ffmpeg') { if (-not (Install-Zip-Tool 'ffmpeg')) { Bad 'Could not install ffmpeg.'; exit 1 } }
if ($pf.toInstall -contains 'poppler') { if (-not (Install-Zip-Tool 'poppler')) { Bad 'Could not install poppler.'; exit 1 } }

if ($pf.toInstall -contains 'python-packages') {
  $extra = if ($pf.device -eq 'cuda') { 'cu128' } else { 'cpu' }
  # an environment from an older kit (or one that is not the locked set) is replaced, not patched
  Remove-Item $VenvDir -Recurse -Force -ErrorAction SilentlyContinue
  Say "  installing Python $($Kit.python) and the locked packages ($(if ($extra -eq 'cu128') { 'NVIDIA build' } else { 'CPU build' })) ..."
  Say '  every file is checked against the hash in the kit lock; anything that does not match is refused.'
  & $Uv sync --frozen --no-install-project --extra $extra --project $EnvDir --python $Kit.python
  if ($LASTEXITCODE -ne 0) { Bad 'Installing the Python packages failed (see above).'; exit 1 }
  Write-Utf8 (Join-Path $VenvDir '.kit-lock') ((Get-FileHash $LockFile -Algorithm SHA256).Hash + " $extra")
}
$pf = Get-Preflight
if (-not $pf.environment) { Bad 'The Python environment is still not the locked one.'; exit 1 }
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

# the unpacked zip may hold voice prints (biometric data): keep only the copies in the data folder
Remove-Item (Join-Path $env:TEMP 'minutes-team-files') -Recurse -Force -ErrorAction SilentlyContinue

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
