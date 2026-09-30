# Maintaining the kit

## What is public and what is not

Public (this repo / npm package): the workflow rules, scripts, blank template, setup wizard.
Private, shared only through Teams: `roster.local.md`, `team.local.json`, optional
`speaker_profiles.json`. Keep them in a folder outside this repo (for example `../minutes-private/`).

Pack them for the scribes with one command, then share the zip in a private Teams channel:

```
powershell -ExecutionPolicy Bypass -File tools\make-team-bundle.ps1 -Source ..\minutes-private [-IncludeVoices]
```

`make-team-bundle.ps1` refuses to pack anything containing a token-shaped string. The setup wizard finds
`minutes-team-files.zip` in Downloads / Desktop / Documents / OneDrive by itself and offers it, so the scribe only
downloads it and presses Enter. Voice prints are biometric data: include them only for people who agreed.

Before EVERY publish, run the scrub check from the repo root and read what it prints:

```
grep -rniE "<staff surnames>|<venue names>|<regulator>|<partner names>|Users.<your username>" . -I
git ls-files | grep -iE "local|profiles|\.wav|\.mp3|whisper|signature"
npm pack --dry-run
```

All three must show nothing you would not put on a billboard. `.gitignore` and `package.json` `files` already
exclude the private patterns; the check catches mistakes in tracked text.

Start the public repo from a clean copy of this folder (`git init` fresh). Never copy git history from a
folder that ever held real data.

## Release

1. Bump `kitVersion` in `plugin/skills/minutes-setup/scripts/kit.json` (the single source for the wizard, the
   gate and the pins), and the same number in `package.json` and `plugin/.claude-plugin/plugin.json`.
   Changing `kitVersion` makes every scribe's gate say "kit was updated, re-run the setup wizard", which is
   what you want when pins change. For a docs-only change you may leave `kitVersion` alone.
2. `claude plugin validate .` and `claude plugin validate ./plugin` must both pass.
3. Commit, push. Plugin users update with `/plugin marketplace update meeting-minutes-kit`. Claude Code only re-fetches a
   plugin when its `version` changes, so bump `plugin/.claude-plugin/plugin.json` (and `package.json`) for ANY content
   change; `kitVersion` in `kit.json` changes only when the wizard or the pins change (it forces a wizard re-run).
4. npm route (the any-agent install; `pnpm dlx github:Jem-Jem-Jem/meeting-minutes-kit install` already works from the
   repo without it, verified 2026-09-30, but a registry release is cleaner for non-git machines): `npm login` (once), then
   `pnpm publish --access public --no-git-checks`. Users update with `pnpm dlx meeting-minutes-kit@latest update`.

## Install routes

`install.ps1` (repo root) is the no-prerequisite route: PowerShell only, no admin, no git, no Node. It mirrors `bin/cli.js`
(marker file, refuses to overwrite foreign folders). Keep the two in step. Fetching `main` means every push is live for
the next installer run, so test before pushing.

## Testing

- **No-GPU path on a GPU machine:** `MINUTES_FORCE_CPU=1` makes the preflight report `cpu`; put `"device": "cpu"`
  in `team.local.json` to force the transcriber onto the CPU. `MINUTES_HOME=<temp folder>` keeps the test away from
  your real data (`%USERPROFILE%\.claude\meeting-minutes`).
- **Clean machine:** the best test is the first real scribe's PC. Otherwise use Windows Sandbox (Windows 10/11
  Pro; enable it once from an admin PowerShell with
  `Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All`, then reboot). Copy the
  kit folder and the team zip into the sandbox and run `setup.ps1` by hand. A sandbox has no Word, so set
  `MINUTES_TEST_SKIP_WORD=1` (skips the Word check and render); it also has no winget, which exercises the
  direct-download installers. Leave the HuggingFace token empty to test the no-token path.
- **Resume:** start `transcribe.py` on a long file, kill it after the "transcribe done" line, run the same
  command again: it should print `[resume] reusing finished speech-to-text`.

## Pinned versions

`kit.json` pins whisperx 3.8.6, pyannote-audio 4.0.7, torch 2.8.0, faster-whisper 1.2.1, python-docx 1.2.0,
openpyxl 3.1.5. Bump them together, then rerun the end-to-end test.

## Known limits

- Word desktop is required (the pagination check uses it). There is no LibreOffice fallback.
- Voice profiles enrolled on one microphone match less well on another.
- Python, ffmpeg and poppler are installed by direct per-user download (no admin, no winget; winget is only the
  fallback). The zip unpack + bin detection is tested; the Python per-user installer run and the user-PATH edit
  are not, so the first clean PC is their real test. Node.js (MSI) and Git for Windows still need admin once.
- Two table mics never line up perfectly for every speaker (different distances), so always listen to the
  merge samples.
