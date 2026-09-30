# Maintainer tool: packs the PRIVATE team files into one zip to share on Teams.
#   powershell -ExecutionPolicy Bypass -File tools\make-team-bundle.ps1 -Source <private folder> [-Out minutes-team-files.zip] [-IncludeVoices]
# The scribe downloads the zip; the setup wizard finds it in Downloads/Desktop/Documents/OneDrive by itself.
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [string]$Out = 'minutes-team-files.zip',
  [switch]$IncludeVoices
)
$ErrorActionPreference = 'Stop'
$need = 'roster.local.md', 'team.local.json'
foreach ($f in $need) { if (-not (Test-Path (Join-Path $Source $f))) { throw "missing $f in $Source" } }
$null = Get-Content (Join-Path $Source 'team.local.json') -Raw | ConvertFrom-Json   # must parse

$files = @($need | ForEach-Object { Join-Path $Source $_ })
if ($IncludeVoices) {
  $v = Join-Path $Source 'speaker_profiles.json'
  if (-not (Test-Path $v)) { throw 'speaker_profiles.json not found (voice prints are biometric data: only share with people who agreed)' }
  $files += $v
}

# never ship a credential by accident
foreach ($f in $files) {
  if ((Get-Content $f -Raw) -match 'hf_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|npm_[A-Za-z0-9]{20,}') { throw "$f contains something that looks like an access token. Remove it." }
}

if (Test-Path $Out) { Remove-Item $Out -Force }
Compress-Archive -Path $files -DestinationPath $Out
Write-Host "wrote $Out"
Get-ChildItem $Out | Select-Object Name, Length | Format-Table -AutoSize
Write-Host 'Contains:'; $files | ForEach-Object { Write-Host ('  ' + (Split-Path $_ -Leaf)) }
Write-Host 'Share it on Teams (a private channel or folder). Do not put it in the public repo.'
