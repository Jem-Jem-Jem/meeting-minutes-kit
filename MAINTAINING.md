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

**Someone leaves (or withdraws consent).** Delete their print from your own copies
(`speaker_profiles.py remove "Label"`, run once per profiles file you hold, including the private folder), add the
label to `removed_voices` in `team.local.json`, take them off the roster, rebuild the bundle and delete the old zip
from Teams. Each scribe's next wizard run deletes the print on their PC too. Someone who leaves the weekly meeting but
still joins other meetings can stay in the profiles and come off the roster only.

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
   gate and the pinned downloads), and the same number in `package.json` and `plugin/.claude-plugin/plugin.json`.
   Changing `kitVersion` makes every scribe's gate say "kit was updated, re-run the setup wizard", which is
   what you want when the lock or a download changes. For a docs-only change you may leave `kitVersion` alone.
2. `claude plugin validate .` and `claude plugin validate ./plugin` must both pass.
3. Commit, push. Plugin users update with `claude plugin marketplace update meeting-minutes-kit` then `claude plugin update meeting-minutes@meeting-minutes-kit` and a restart. Claude Code only re-fetches a
   plugin when its `version` changes, so bump `plugin/.claude-plugin/plugin.json` (and `package.json`) for ANY content
   change; `kitVersion` in `kit.json` changes only when the wizard, the lock or a download changes (it forces a wizard re-run).
4. npm: push a tag matching the version, for example `git tag v0.5.1 && git push origin v0.5.1`. GitHub Actions
   (`.github/workflows/publish.yml`) checks the tag equals `package.json`'s version and publishes with npm trusted
   publishing: no npm token anywhere, and the npm page shows provenance linking the release to its commit. The
   trusted publisher is set on npmjs.com (package Settings: GitHub Actions, `Jem-Jem-Jem/meeting-minutes-kit`,
   `publish.yml`). Do not publish from a local machine any more. Users update with
   `pnpm dlx meeting-minutes-kit@latest update`; pnpm 11 installs a release once it is a day old.

## Install routes

`pnpm dlx` (and `npx`) cache a fetched package for about a day, so a plain `pnpm dlx github:...` can install a stale version
(an old version was installed right after a newer one was pushed). Every documented pnpm command carries
`--config.dlx-cache-max-age=0` for that reason.

`install.ps1` (repo root) is the backup route for machines without Node or git: PowerShell only, no admin, no git, no Node. It mirrors `bin/cli.js`
(marker file, refuses to overwrite foreign folders). Keep the two in step. Fetching `main` means every push is live for
the next installer run, so test before pushing.

## Testing

- **No-GPU path on a GPU machine:** `MINUTES_FORCE_CPU=1` makes the preflight report `cpu`; put `"device": "cpu"`
  in `team.local.json` to force the transcriber onto the CPU. `MINUTES_HOME=<temp folder>` keeps the test away from
  your real data (`%USERPROFILE%\.claude\meeting-minutes`).
- **Clean machine:** the best test is a real second PC. Otherwise use Windows Sandbox (Windows 10/11
  Pro; enable it once from an admin PowerShell with
  `Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All`, then reboot). Copy the
  kit folder and the team zip into the sandbox and run `setup.ps1` by hand. A sandbox has no Word, so set
  `MINUTES_TEST_SKIP_WORD=1` (skips the Word check and render); it exercises the
  checked downloads end to end. Leave the HuggingFace token empty to test the no-token path.
- **Resume:** start `transcribe.py` on a long file, kill it after the "transcribe done" line, run the same
  command again: it should print `[resume] reusing finished speech-to-text`.

## Pinned versions (supply-chain safety)

Everything a scribe's PC downloads is fixed and checked, because the tool handles sensitive meeting audio:

- **Python packages:** `plugin/skills/minutes-setup/env/pyproject.toml` lists what the kit needs (CPU and NVIDIA
  builds of PyTorch as two extras, each from PyTorch's own index); `env/uv.lock` fixes all ~130 packages with
  their file hashes. The wizard runs `uv sync --frozen`, which refuses any file whose hash does not match.
  `constraint-dependencies` holds the rest of the set at the versions tested together.
- **Downloads:** uv itself, ffmpeg and poppler are fixed URLs with SHA-256 in `kit.json`; the wizard refuses a
  mismatch. uv installs its own Python into the data folder.
- **Models:** `MODEL_REVISIONS` in `meeting-minutes/scripts/speaker_profiles.py` pins each Hugging Face model to a
  commit.

To upgrade: change versions in `pyproject.toml` (or a URL + hash in `kit.json`, or a model commit), run `uv lock`
in `env/` with the same uv version as `kit.json`, install both extras into a temp folder
(`UV_PROJECT_ENVIRONMENT=<temp> uv sync --frozen --no-install-project --extra cpu|cu128`), transcribe a short clip with
each, bump `kitVersion`, release. Prefer releases that are a few weeks old. Hashes for a new download: check them
against the publisher's own (`gh api repos/<owner>/<repo>/releases/tags/<tag>` shows each asset's `digest`).

## Known limits

- Word desktop is required (the pagination check uses it). There is no LibreOffice fallback.
- Voice profiles enrolled on one microphone match less well on another.
- uv, its Python, the packages, ffmpeg and poppler all go into the data folder (no admin). Tested on the
  maintainer's PC into a temp data folder; the user-PATH edit for ffmpeg/poppler is not, so the first clean PC is
  its real test. Node.js (MSI) and Git for Windows still need admin once.
- Two table mics never line up perfectly for every speaker (different distances), so always listen to the
  merge samples.

## Testing with a non-Claude agent (for example Freebuff)

Nothing about a non-Claude agent has been run in this repo yet. When you try one:

1. Install with route 1 (or route 3), default target `~/.claude/skills`. Start the agent and ask what skills it has. If it
   doesn't list `meeting-minutes` and `minutes-setup`, reinstall with `--agents` / `-Agents`, or with `--dir` / `-Dir`
   into the project folder's `.agents/skills`, and start the agent from that folder.
2. The scribe runs the wizard themselves (it is interactive). Then `preflight.ps1 -Gate` must print READY.
3. On a short recording, watch for: reads `roster.local.md`; calls the venv Python, not a bare `python`; backgrounds the
   transcription or hands the command over; merges mics and stops for the listening check; asks who unnamed voices are
   instead of guessing; writes `meeting.json`; runs the linter; builds and renders the docx; lists what it was unsure
   about; does NOT sign before being told the content is final.
4. Score it against ground truth: replay a past meeting's audio and tracker and compare with its signed minutes (invented
   sentences, wrong action owner, wrong tracker column, misspelled names, numbers not in the sources).
5. If it is not good enough, do not lower the bar: use a better agent. The chat-only route in the README is a last resort.

New scribes' voices: each scribe's `speaker_profiles.json` grows locally as they name and enroll voices. Collect it if
you want the improved prints in the next team bundle (rebuild with `tools/make-team-bundle.ps1 -IncludeVoices`).
