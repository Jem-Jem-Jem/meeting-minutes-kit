# meeting-minutes-kit

Turn a meeting recording, plus any context that could help, into a signed, consistently formatted minutes document.
The audio is what the minutes are built from. An AI coding agent does the reading and writing, and your own PC does
the transcription.

**This tool needs a capable coding agent**: one that can run shell commands, read and write files, and follow long
written instructions reliably. It has many steps and a compliance-grade output, so a weak agent will do it badly.

**Works with:** Claude Code (as a plugin, or as plain skills) and any other coding agent that reads `SKILL.md`
skill folders and can run shell commands. Freebuff reads them natively and should work; that is untested so far.

> **Status: early release (0.3.x).** Expect rough edges; please report them.

## What it does

1. **Merges two table microphones** into one recording (optional; measured alignment, not file timecodes).
2. **Transcribes** the audio locally with WhisperX, labelled by speaker, on an NVIDIA GPU or just the CPU.
3. **Reconciles** the transcript against whatever context you give it: a tracker, an agenda, earlier minutes, notes, an
   attendee list, any file that could be relevant (the agent, following written rules: bare facts only,
   explicit action owners, honest gaps instead of guesses).
4. **Builds** a formatted `.docx` (Word), which you review and edit by hand.
5. **Signs** it with your signature image once you say the content is final.

Two agent skills make this up:
- `minutes-setup` checks your computer, installs what is missing and walks you through the human-only steps.
- `meeting-minutes` is the weekly workflow.

Audio is transcribed on your PC. The agent reads the transcript and your context files to write the minutes, as in any
agent session.

## Requirements

- Windows 10 (1809+) or 11, 64-bit. Desktop **Microsoft Word** (used to check page layout).
- An AI coding agent: Claude Code (on a plan that includes it, for example Pro; it needs Git for Windows on Windows)
  or Freebuff (free, no account) or a similar agent.
- 8 GB RAM or more and about 15 GB free disk (Python packages plus speech models).
- An NVIDIA GPU is optional. Without one, an hour of meeting can take an hour or more to transcribe.
- A free HuggingFace account: speaker identification uses a gated model whose licence you accept once.

The setup wizard installs Python, ffmpeg and poppler if they are missing, by direct download into your own user
folders. It needs **no administrator rights** and no winget. Node.js is needed only for install route 1 and git only
for route 2 (and for Claude Code itself on Windows); installing either normally asks for administrator approval once.
Install route 3 needs neither.

## Install (pick ONE route)

**1. pnpm / npx (any agent; needs Node.js 16.7+, no git):**
```
pnpm --config.dlx-cache-max-age=0 dlx meeting-minutes-kit@latest install
```
`--config.dlx-cache-max-age=0` matters: pnpm otherwise reuses a cached copy for a day and can install an old version.
This copies the two skills into `~/.claude/skills` (read by Claude Code). Options: `--agents` (installs to
`~/.agents/skills`), `--dir <path>` (any folder, for example a project's `.agents/skills`), `uninstall`. Freebuff scans
`~/.claude/skills` when home skills are enabled; if your agent does not see the skills, use `--agents` or `--dir`.
Straight from the repo instead of the registry (needs git as well): `pnpm --config.dlx-cache-max-age=0 dlx github:Jem-Jem-Jem/meeting-minutes-kit install`.

**2. Claude Code plugin (needs git).** Use this *instead of* route 1, not as well:
```
/plugin marketplace add Jem-Jem-Jem/meeting-minutes-kit
/plugin install meeting-minutes@meeting-minutes-kit
```

**3. Backup, not recommended: PowerShell installer (no admin, no git, no Node).** Only for machines where routes 1 and 2
are impossible. If a PC cannot run Node or git, ask whether it can run a capable agent at all.
Paste into a normal PowerShell window:
```
iwr -useb https://raw.githubusercontent.com/Jem-Jem-Jem/meeting-minutes-kit/main/install.ps1 | iex
```
It downloads this repo as a zip and copies the same two skills. With options:
```
& ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/Jem-Jem-Jem/meeting-minutes-kit/main/install.ps1))) -Agents
```
`-Agents`, `-Dir <path>`, `-Uninstall`, `-Ref <branch-or-tag>`. Blocked from downloading? Get the zip in a browser, then run
`install.ps1 -ZipPath <the zip>`, or copy the folders inside `plugin/skills/` into your agent's skills folder by hand.
Re-running updates. It never overwrites a skill folder it did not create.

## Set up (once per computer)

Restart your agent, then tell it: `set up the minutes tool`. The agent checks your machine and gives you one command
to paste into a normal PowerShell window (the wizard asks questions, so it cannot run inside an agent). It asks for:

1. your team's files (see below), which it looks for in Downloads, Desktop, Documents and OneDrive by itself,
2. your name and job title,
3. a picture of your signature,
4. a free HuggingFace token (it tells you which three pages to click; Google sign-in works).

It finishes by building a sample document, testing the two-microphone merge and transcribing a short test
recording, then tells you how long a real meeting will take on your PC. Re-running the wizard is safe.

## If your agent cannot run commands on your PC

Some setups (a chat-only app, a locked-down PC) cannot run local commands. The scripts do not need an agent, so you
can run them yourself and use any chatbot only for the reading and writing step:

1. Run the setup wizard yourself in a normal PowerShell window (no admin needed). It is
   `plugin/skills/minutes-setup/scripts/setup.ps1`; run it with `powershell -ExecutionPolicy Bypass -File <path>`.
2. Merge mics and transcribe with the kit's Python (`%USERPROFILE%\.claude\meeting-minutes\venv\Scripts\python.exe`):
   `merge_mics.py`, then `transcribe.py`. Both print usage with `--help`.
3. Paste the "Team Pass" prompt (`plugin/skills/meeting-minutes/references/team-pass-template.md`), the transcript and the
   context into a chatbot. It answers with a `meeting.json`.
4. Save that as `meeting.json` and run `build_minutes.py meeting.json "DD-MM-YYYY meeting minutes.docx"`, review in Word,
   then `sign_minutes.py`.

## Your team's files

The kit contains no team data. Each team provides:

- `roster.local.md`: who is on the team, name spellings the transcriber gets wrong, recurring agenda areas,
  section headings, and any house rules. Free-form Markdown that the agent reads before every job.
- `team.local.json`: `org`, `meeting_title`, `venue`, `approver_name` (used in the document header and sign-off block).
- optionally `speaker_profiles.json`: voice prints so speakers are named automatically. Voice prints are
  biometric data: share them only with people who agreed, and only inside your organisation.

See `examples/team/` for fictional samples. The maintainer packs them with
`tools/make-team-bundle.ps1` into `minutes-team-files.zip` and shares that privately (for example on Teams).
They are copied to `%USERPROFILE%\.claude\meeting-minutes`, and updates never touch that folder.

## Each week

Put the recording in a folder together with any context that could be relevant (a tracker, an agenda, the last minutes,
notes) and tell your agent: `write the meeting minutes`.

- **The audio decides what was said.** Context only helps the agent get names, spellings and numbers right. It is
  optional: with none, the agent works from the audio alone and lists what it could not verify.
- **Trackers** laid out one week per row or column (sheet per person is fine) are cut down to the one week the meeting
  reports on.
- **Two mics?** Put each mic's files in its own folder. The agent merges them, then asks you to listen to three
  short samples before it continues. (Developed with DJI Mic 3 files saved in 30-minute chunks.)
- **Slow PC?** Transcription keeps the PC awake and resumes if it is interrupted: ask the agent to run it again.
- **Unnamed voices?** The agent shows two lines from each and asks who it is, then remembers the voice.
- **Review before signing.** The agent lists what it was unsure about. You check the `.docx` in Word, and only then
  does it sign.

The document layout is fixed (`build_minutes.py`); changing the look means editing that script.

## Update

Re-run the same install line you used. Claude Code plugin: `claude plugin marketplace update meeting-minutes-kit`, then `claude plugin update meeting-minutes@meeting-minutes-kit`,
then restart (the first only refreshes the listing; the second updates the plugin).
If the version changed, the next job asks you to re-run the wizard once.

## If something goes wrong

- Ask your agent to run the machine check, or run `preflight.ps1` from the `minutes-setup` skill folder.
- The wizard prints what failed on the last screen. Paste that screen to whoever maintains your copy (it holds no secrets).
- To start clean, delete `%USERPROFILE%\.claude\meeting-minutes` and run the wizard again.

## Credits and licence

MIT, see `LICENSE`. Built on WhisperX, faster-whisper, pyannote.audio (its diarization model is gated on HuggingFace
under its own licence), python-docx, openpyxl and ffmpeg. Not affiliated with Anthropic or Codebuff; Claude and Claude
Code are Anthropic's products, Freebuff is Codebuff's.
