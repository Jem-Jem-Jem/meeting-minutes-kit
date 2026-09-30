# meeting-minutes-kit

Turn a meeting recording and a weekly tracker into a signed, consistently formatted minutes document. An AI
coding agent does the reading and writing, and your own PC does the transcription.

**Works with:** Claude Code (as a plugin, or as plain skills) and any other coding agent that reads `SKILL.md`
skill folders and can run shell commands. Freebuff reads them natively and should work; that is untested so far.

> **Status: early release (0.2.0).** Built and tested on one Windows 10 PC. A clean-machine test on a second PC is
> still pending, so expect rough edges in the installer.

## What it does

1. **Merges two table microphones** into one recording (optional; measured alignment, not file timecodes).
2. **Transcribes** the audio locally with WhisperX, labelled by speaker, on an NVIDIA GPU or just the CPU.
3. **Reconciles** the transcript against your weekly tracker (the agent, following written rules: bare facts only,
   explicit action owners, honest gaps instead of guesses).
4. **Builds** a formatted `.docx` (Word), which you review and edit by hand.
5. **Signs** it with your signature image once you say the content is final.

Two agent skills make this up:
- `minutes-setup` checks your computer, installs what is missing and walks you through the human-only steps.
- `meeting-minutes` is the weekly workflow.

Audio is transcribed on your PC. The agent reads the transcript and the tracker to write the minutes, as in any
agent session.

## Requirements

- Windows 10 (1809+) or 11, 64-bit. Desktop **Microsoft Word** (used to check page layout).
- An AI coding agent: Claude Code (on a plan that includes it, for example Pro; it needs Git for Windows on Windows)
  or Freebuff (free, no account) or a similar agent.
- **Node.js 16.7 or newer** for the install command below (`winget install OpenJS.NodeJS.LTS`). pnpm or npm both work.
- 8 GB RAM or more and about 15 GB free disk (Python packages plus speech models).
- An NVIDIA GPU is optional. Without one, an hour of meeting can take an hour or more to transcribe.
- A free HuggingFace account: speaker identification uses a gated model whose licence you accept once.

The setup wizard installs Python, ffmpeg and poppler if they are missing (with winget, or direct downloads when
winget is unavailable).

## Install

**Any agent (recommended).** Copies the two skills into your agent's skills folder:
```
pnpm dlx meeting-minutes-kit@latest install
```
- Default target is `~/.claude/skills`, which Claude Code reads. Freebuff scans it too when home skills are enabled; if
  your agent does not see the skills, use `--agents`, or `--dir` with a project's `.agents/skills`.
- `--agents` installs to `~/.agents/skills` instead; `--dir <path>` to any folder (for example a project's
  `.agents/skills`).
- No npm access? Download this repo as a zip and copy the folders inside `plugin/skills/` into your agent's skills
  folder by hand.

**Claude Code plugin (alternative; needs git).** Use this route *instead of* the one above, not as well:
```
/plugin marketplace add Jem-Jem-Jem/meeting-minutes-kit
/plugin install meeting-minutes@meeting-minutes-kit
```

## Set up (once per computer)

Restart your agent, then tell it: `set up the minutes tool`. The agent checks your machine and gives you one command
to paste into a normal PowerShell window (the wizard asks questions, so it cannot run inside an agent). It asks for:

1. your team's files (see below), which it looks for in Downloads, Desktop, Documents and OneDrive by itself,
2. your name and job title,
3. a picture of your signature,
4. a free HuggingFace token (it tells you which three pages to click; Google sign-in works).

It finishes by building a sample document, testing the two-microphone merge and transcribing a short test
recording, then tells you how long a real meeting will take on your PC. Re-running the wizard is safe.

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

Put the audio and the tracker in a folder and tell your agent: `write the meeting minutes`.

- **Two mics?** Put each mic's files in its own folder. The agent merges them, then asks you to listen to three
  short samples before it continues. (Developed with DJI Mic 3 files saved in 30-minute chunks.)
- **Slow PC?** Transcription keeps the PC awake and resumes if it is interrupted: ask the agent to run it again.
- **Unnamed voices?** The agent shows two lines from each and asks who it is, then remembers the voice.
- **Review before signing.** The agent lists what it was unsure about. You check the `.docx` in Word, and only then
  does it sign.

The document layout is fixed (`build_minutes.py`); changing the look means editing that script.

## Update

Any agent: `pnpm dlx meeting-minutes-kit@latest update` (same `--agents` / `--dir` flags as install). Claude Code plugin:
`/plugin marketplace update meeting-minutes-kit`.
If the version changed, the next job asks you to re-run the wizard once.

## If something goes wrong

- Ask your agent to run the machine check, or run `preflight.ps1` from the `minutes-setup` skill folder.
- The wizard prints what failed on the last screen. Paste that screen to whoever maintains your copy (it holds no secrets).
- To start clean, delete `%USERPROFILE%\.claude\meeting-minutes` and run the wizard again.

## Credits and licence

MIT, see `LICENSE`. Built on WhisperX, faster-whisper, pyannote.audio (its diarization model is gated on HuggingFace
under its own licence), python-docx, openpyxl and ffmpeg. Not affiliated with Anthropic or Codebuff; Claude and Claude
Code are Anthropic's products, Freebuff is Codebuff's.
