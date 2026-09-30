# Installs (or updates) the meeting-minutes skills into an AI agent's skills folder.
# Needs NO Node.js, NO git and NO administrator rights: only PowerShell (built into Windows).
#
#   One line, default target (~/.claude/skills, read by Claude Code):
#     iwr -useb https://raw.githubusercontent.com/Jem-Jem-Jem/meeting-minutes-kit/main/install.ps1 | iex
#
#   With options (-Agents, -Dir <path>, -Uninstall, -Ref <branch-or-tag>, -ZipPath <local zip>):
#     & ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/Jem-Jem-Jem/meeting-minutes-kit/main/install.ps1))) -Agents
#
#   Offline / from a zip you downloaded yourself:
#     powershell -ExecutionPolicy Bypass -File install.ps1 -ZipPath C:\path\to\meeting-minutes-kit-main.zip
#
# Re-running updates. It never touches ~/.claude/meeting-minutes (roster, signature, venv, voice profiles),
# and never overwrites a skill folder this kit did not create.
param(
  [switch]$Uninstall,
  [switch]$Agents,
  [string]$Dir,
  [string]$Ref = 'main',
  [string]$ZipPath
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Marker = '.installed-by-meeting-minutes-kit'
$Repo = 'Jem-Jem-Jem/meeting-minutes-kit'

$home_ = $env:USERPROFILE
$defaultDest = Join-Path $home_ '.claude\skills'
$dest = if ($Dir) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Dir) }
        elseif ($Agents) { Join-Path $home_ '.agents\skills' }
        else { $defaultDest }

# ---- get the kit (zip from GitHub, or a local zip)
$tmp = Join-Path $env:TEMP ('mmk-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $zip = $ZipPath
  if (-not $zip) {
    $zip = Join-Path $tmp 'kit.zip'
    $refPath = if ($Ref -match '^v?\d') { "refs/tags/$Ref" } else { "refs/heads/$Ref" }
    $url = "https://github.com/$Repo/archive/$refPath.zip"
    Write-Host "downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
  }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $skillsSrc = Get-ChildItem $tmp -Recurse -Directory -Filter skills | Where-Object { $_.FullName -match '[\\/]plugin[\\/]skills$' } | Select-Object -First 1
  if (-not $skillsSrc) { throw 'plugin\skills not found in the zip: is this the meeting-minutes-kit repo?' }
  $kitRoot = Split-Path (Split-Path $skillsSrc.FullName)
  $version = (Get-Content (Join-Path $kitRoot 'package.json') -Raw | ConvertFrom-Json).version
  $names = Get-ChildItem $skillsSrc.FullName -Directory | ForEach-Object { $_.Name }

  if ($Uninstall) {
    foreach ($n in $names) {
      $d = Join-Path $dest $n
      if (Test-Path (Join-Path $d $Marker)) { Remove-Item $d -Recurse -Force; Write-Host "removed $n" }
    }
    Write-Host "skills removed from $dest. Your data in $home_\.claude\meeting-minutes was left alone."
    return
  }

  # the Claude Code plugin and a skills copy would both register the same skills
  if ($dest -eq $defaultDest) {
    $ip = Join-Path $home_ '.claude\plugins\installed_plugins.json'
    if ((Test-Path $ip) -and ((Get-Content $ip -Raw) -match 'meeting-minutes@meeting-minutes-kit')) {
      throw "The meeting-minutes plugin is already installed in Claude Code. Use one route, not both. Remove the plugin from '/plugin' first."
    }
  }

  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  foreach ($n in $names) {
    $d = Join-Path $dest $n
    if ((Test-Path $d) -and -not (Test-Path (Join-Path $d $Marker))) {
      throw "$d exists and was not installed by this kit. Rename or remove it first."
    }
  }
  foreach ($n in $names) {
    $d = Join-Path $dest $n
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    Copy-Item (Join-Path $skillsSrc.FullName $n) $d -Recurse -Force
    Set-Content -Path (Join-Path $d $Marker) -Value "meeting-minutes-kit $version" -Encoding ASCII
    Write-Host "installed skill: $n"
  }
  Write-Host ''
  Write-Host "meeting-minutes-kit $version -> $dest"
  Write-Host 'Next: open your AI agent, restart it if it was already running, and say: set up the minutes tool'
}
finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
