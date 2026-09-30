# meeting-minutes-kit

Claude Code skills for the weekly meeting minutes: transcribe the recording, reconcile it against the
tracker, build the formatted docx, sign it.

Two skills:
- `minutes-setup`: checks your computer, installs what is missing, walks you through the human steps.
- `meeting-minutes`: the actual workflow.

This repo contains **no team data**. The roster, name spellings, signature and voice profiles are private
and come from the maintainer (Teams). They live on your machine in `%USERPROFILE%\.claude\meeting-minutes`
and updates never touch them.

## For the scribe

You need: Windows 10/11, desktop Microsoft Word, Claude Code with a Pro subscription. The wizard installs the rest.

**Install (pick ONE route, not both)**

Route A, plugin (needs git):
```
/plugin marketplace add Jem-Jem-Jem/meeting-minutes-kit
/plugin install meeting-minutes@meeting-minutes-kit
```
Route B, pnpm (needs pnpm; if you have no Node, install pnpm first with the standalone script from pnpm.io):
```
pnpm dlx meeting-minutes-kit@latest install
```

**Set up (once per computer).** In Claude Code say: `set up the minutes tool`. Claude checks your machine
and gives you one command to paste into a normal PowerShell window. That wizard asks for:
1. the team files the maintainer shared (`minutes-team-files.zip`: download it first and the wizard finds it in Downloads/Desktop/Documents/OneDrive by itself),
2. your name and job title,
3. a picture of your signature,
4. a free HuggingFace token (it tells you exactly which three pages to click).

It then transcribes a short test recording to prove everything works and tells you how long a real
meeting will take on your computer. If you have no NVIDIA graphics card it still works, just slower.

**Each week.** Put the audio and the tracker in a folder, then tell Claude: `write the meeting minutes`.
- Recorded with two separate mics? Put each mic's files in its own folder. Claude merges them, then asks you to
  listen to three short samples before it goes on.
- On a PC without an NVIDIA graphics card, transcription can take an hour or more. It keeps the PC awake and
  resumes if it is interrupted: just ask Claude to run it again.
- The first time, some voices will be unnamed. Claude shows two lines each and asks who it is, then remembers the
  voice so it is named automatically next time.

**Update.** Route A: `/plugin marketplace update meeting-minutes-kit`. Route B: `pnpm dlx meeting-minutes-kit@latest update`.
