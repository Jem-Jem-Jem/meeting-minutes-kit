# meeting-minutes-kit

This kit turns a meeting recording into a signed minutes document with a consistent format. The minutes come from the
audio. Other files can help the agent get names and numbers right. An AI coding agent reads and writes. Your own PC
does the transcription.

**This tool needs a capable coding agent.** The agent must run shell commands, read and write files, and follow long
written instructions. The job has many steps and the output must be of compliance quality. A weak agent does it badly.

**Works with:** Claude Code (as a plugin or as plain skills). It also works with other coding agents that read
`SKILL.md` skill folders and run shell commands. Freebuff reads these folders. We did not test Freebuff yet.

## What it does

1. **Merges two table microphones** into one recording. This step is optional. The kit measures the time offset
   between the two files. It does not use the timecodes in the files.
2. **Transcribes** the audio on your PC with WhisperX and labels each speaker. It uses an NVIDIA GPU if you have one,
   or the CPU.
3. **Reconciles** the transcript with your context files. Context files are any files that can help: a tracker, an
   agenda, earlier minutes, notes or an attendee list. The agent follows written rules: bare facts only, a named owner
   for each action, and an open gap instead of a guess.
4. **Builds** a formatted Word document (`.docx`). You review it and edit it by hand.
5. **Signs** the document with your signature image after you say that the content is final.

The kit has two agent skills:
- `minutes-setup` checks your PC, installs what is missing and guides you through the steps that only you can do.
- `meeting-minutes` is the weekly workflow.

**Privacy.** Your PC transcribes the audio. The agent then reads the transcript and your context files, as in any
agent session. The kit switches off the usage reporting of the transcription libraries (pyannote reports usage by
default, and so does Hugging Face). The transcription step sends nothing about your meetings to any server.

## Requirements

- Windows 10 (version 1809 or later) or Windows 11, 64-bit.
- Desktop **Microsoft Word**. The kit uses it to check the page layout.
- An AI coding agent: Claude Code or Freebuff, or a similar agent. Claude Code needs a plan that includes it (for
  example Pro). On Windows, Claude Code also needs Git for Windows. Freebuff is free and needs no account.
- 8 GB RAM or more.
- About 15 GB of free disk space for the Python packages and the speech models.
- A free Hugging Face account. Speaker identification uses a gated model: you accept its licence one time.
- An NVIDIA GPU is optional, but it makes a large difference. Measured times for one hour of meeting:
  - RTX 3060 Laptop GPU: about 8 minutes.
  - CPU of the same laptop (Intel Core i9-12900HK), no GPU: about 70 minutes.
  - Low-power laptop CPU: several hours.

  The setup wizard measures your PC and tells you its time.

**What the setup wizard installs.** The wizard installs all other parts into the kit's data folder
(`%USERPROFILE%\.claude\meeting-minutes`): Python (through uv), the Python packages, ffmpeg and poppler. It needs **no
administrator rights**. It does not change any other Python on your PC.

**Supply-chain safety.** The wizard checks each download against a fixed hash. If a file does not match, the wizard
refuses it. Thus a changed or hijacked package cannot get in. The speech models also have fixed versions.

**Node.js and git.** Install route 1 needs Node.js. Route 2 needs git (Claude Code on Windows needs git too). Each of
these installers usually asks for administrator approval one time. Route 3 needs neither.

## Install (use ONE route)

### Route 1: Node.js (any agent, no git)

You need Node.js 16.7 or later. Use npm or pnpm. Both give the same result.

**With npm** (npm comes with Node.js):
```
npx meeting-minutes-kit@latest install
```
npx asks "Ok to proceed?". Type `y`. A new version is available to npx as soon as it is published.

**With pnpm:**
```
pnpm --config.dlx-cache-max-age=0 dlx meeting-minutes-kit@latest install
```
Keep `--config.dlx-cache-max-age=0`. Without it, pnpm can use a cached copy for one day and install an old version.
pnpm 11 also waits until a release is one day old before it installs it. This is a safety default against hijacked
packages. Keep that default.

Both commands copy the two skills into `~/.claude/skills`, where Claude Code reads them. The package itself does not
stay installed.

Options (for npx and pnpm):
- `--agents`: install into `~/.agents/skills` instead.
- `--dir <path>`: install into a folder you choose, for example a project's `.agents/skills`.
- `uninstall` (in place of `install`): remove the skills.

Freebuff reads `~/.claude/skills` when its home skills setting is on. If your agent does not show the skills, use
`--agents` or `--dir`.

Do not use `npm i meeting-minutes-kit`. That command only downloads the package into a `node_modules` folder. It does
not install the skills.

To install from the GitHub repository instead of the npm registry (this also needs git):
`pnpm --config.dlx-cache-max-age=0 dlx github:Jem-Jem-Jem/meeting-minutes-kit install`.

### Route 2: Claude Code plugin (needs git)

Use this route *instead of* route 1. Do not use both. In Claude Code, type:
```
/plugin marketplace add Jem-Jem-Jem/meeting-minutes-kit
/plugin install meeting-minutes@meeting-minutes-kit
```

### Route 3: PowerShell installer (backup, not recommended)

This route needs no administrator rights, no git and no Node.js. Use it only if routes 1 and 2 are not possible. If a
PC cannot run Node.js or git, ask if it can run a capable agent at all.

Paste this line into a normal PowerShell window:
```
iwr -useb https://raw.githubusercontent.com/Jem-Jem-Jem/meeting-minutes-kit/main/install.ps1 | iex
```
It downloads this repository as a zip file and copies the same two skills. To add options, use this form:
```
& ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/Jem-Jem-Jem/meeting-minutes-kit/main/install.ps1))) -Agents
```
Options: `-Agents`, `-Dir <path>`, `-Uninstall`, `-Ref <branch-or-tag>`.

If your PC blocks the download:
1. Download the zip file in a browser.
2. Run `install.ps1 -ZipPath <the zip>`.

Or copy the folders in `plugin/skills/` into the skills folder of your agent by hand.

To update, run the installer again. It never replaces a skill folder that it did not create.

## Set up (one time for each PC)

1. Restart your agent.
2. Tell it: `set up the minutes tool`.
3. The agent checks your PC and gives you one command.
4. Paste that command into a standalone PowerShell window.

The setup wizard asks you questions, so it cannot run inside an agent. Do not use a terminal panel inside the Claude
app or inside an editor. The speed test uses all of the PC's power, and it froze such a terminal one time.

The wizard asks for:
1. Your team's files (see "Your team's files"). It looks for them in Downloads, Desktop, Documents and OneDrive.
2. Your name and job title.
3. An image of your signature.
4. A free Hugging Face token. The wizard shows you the three pages to open. Google sign-in works.

At the end, the wizard builds a sample document, tests the merge of two microphones and transcribes a short test
recording. Then it tells you how long a real meeting will take on your PC. You can safely run the wizard again.

## If your agent cannot run commands on your PC

Some setups cannot run local commands, for example a chat-only app or a locked PC. The scripts do not need an agent.
You can run them yourself and use any chatbot for the reading and writing step:

1. Run the setup wizard in a normal PowerShell window. It needs no administrator rights. The file is
   `plugin/skills/minutes-setup/scripts/setup.ps1`. Run it with `powershell -ExecutionPolicy Bypass -File <path>`.
2. Use the kit's Python (`%USERPROFILE%\.claude\meeting-minutes\venv\Scripts\python.exe`). Run `merge_mics.py`, then
   `transcribe.py`. Each script shows its usage with `--help`.
3. Paste the "Team Pass" prompt (`plugin/skills/meeting-minutes/references/team-pass-template.md`), the transcript and
   the context files into a chatbot. The chatbot gives back a `meeting.json`.
4. Save the answer as `meeting.json`.
5. Run `build_minutes.py meeting.json "DD-MM-YYYY meeting minutes.docx"`.
6. Review the document in Word.
7. Run `sign_minutes.py`.

## Your team's files

The kit contains no team data. The files of another team do not work for you: your team writes its own files. Start
from the fictional samples in `examples/team/` and replace all of their content. You need:

- `roster.local.md`: the team members, the names that the transcriber spells wrong, the recurring agenda topics, the
  section headings and any house rules. This is free-form Markdown. The agent reads it before each job.
- `team.local.json`: `org`, `meeting_title`, `venue` and `approver_name`. The document header and the sign-off block
  use these values. An optional key, `removed_voices`, lists voice-print labels to delete. The wizard deletes these
  voice prints on each scribe's PC at the next run. Use it when a person leaves the team or withdraws consent.
- `speaker_profiles.json` (optional): voice prints that let the tool name the speakers. Voice prints are biometric
  data. Share them only with people who agreed, and only inside your organisation.

The person who maintains your team's copy packs these files into `minutes-team-files.zip` with
`tools/make-team-bundle.ps1`. That person shares the zip privately with the team's scribes, for example on Teams.

If you work alone, you do not need the zip. Give the wizard the folder that holds your files.

The wizard copies the files into the data folder (`%USERPROFILE%\.claude\meeting-minutes`). Updates never change that
folder.

**Page layout.** On the first run, the agent asks which layout to use:
- The layout that comes with the kit.
- A layout that the agent makes from your description.
- A copy of an example `.docx` that you give it, for example past minutes or a letterhead.

The kit saves a custom layout as `%USERPROFILE%\.claude\meeting-minutes\template.docx`. The minutes keep its page
size, margins, fonts, headers, footers and page numbers. The kit does not use its body text.

## Each week

Put the recording in a folder. Add any context files that can help, for example a tracker, an agenda, the last minutes
or notes. Then tell your agent: `write the meeting minutes`.

- **The audio decides what was said.** Context files only help the agent get names, spellings and numbers right.
  They are optional. Without them, the agent works from the audio alone and lists what it could not check.
- **Trackers** can show one week for each row or for each column, and a sheet for each person is fine. The kit cuts
  the tracker down to the week of the meeting.
- **Two microphones?** Put the files of each microphone in a separate folder. The agent merges them. Then it asks you
  to listen to three short samples before it continues. (We developed this with DJI Mic 3 files saved in 30-minute
  parts.)
- **Slow PC?** Transcription keeps the PC awake. If something stops it, ask the agent to run it again. It continues
  from the last finished stage.
- **Unnamed voices?** The agent shows two lines from each unnamed voice and asks who it is. Then the tool remembers
  that voice.
- **Review before signing.** The agent lists the points it was not sure about. You check the `.docx` in Word. The agent
  signs only after that.

The table structure is fixed in `build_minutes.py`. The page size, fonts, letterhead, headers and footers come from the
layout you chose (see "Page layout").

## Update

There are two types of update. If both arrive together, do them in this order.

**1. New team files.** This applies only if your team shares a `minutes-team-files.zip`, and the person who maintains
it sends a new one. A new zip can change the roster or the approver, or add or remove voice prints.
1. Download the new zip into Downloads, Desktop or Documents.
2. Delete the old zip.
3. Start your next job. The tool reads the zip only during setup, so the next job tells you that a newer zip is there.
4. When it offers to run the wizard again, say yes.

If you work alone, edit your files in `%USERPROFILE%\.claude\meeting-minutes` directly. You do not need to run
anything again.

**2. New kit version.** Run the line for the route that you used to install:
- Route 1 with npm: `npx meeting-minutes-kit@latest update`
- Route 1 with pnpm: `pnpm --config.dlx-cache-max-age=0 dlx meeting-minutes-kit@latest update` (keep the cache
  setting, or pnpm can use the copy from the day before).
- Route 2 (Claude Code plugin): run `claude plugin marketplace update meeting-minutes-kit`. Then run
  `claude plugin update meeting-minutes@meeting-minutes-kit`. Then restart Claude Code. The first command only
  refreshes the list. The second command updates the plugin.
- Route 3: run the same PowerShell line again.

If the new version changes the setup, the next job stops and asks you to run the wizard again. The wizard skips all
parts that are already installed, but it does the short speed test again. An update never changes your data folder
(`%USERPROFILE%\.claude\meeting-minutes`).

## If something goes wrong

- Ask your agent to run the machine check. Or run `preflight.ps1` from the `minutes-setup` skill folder yourself.
- The last screen of the wizard shows what failed. Send that screen to the person who maintains your copy. It contains
  no secrets.
- To start again from nothing, delete `%USERPROFILE%\.claude\meeting-minutes`. Then run the wizard again.

## Credits and licence

MIT, see `LICENSE`. The kit uses WhisperX, faster-whisper, pyannote.audio, python-docx, openpyxl and ffmpeg. The
pyannote diarization model is gated on Hugging Face and has its own licence. This kit has no connection with Anthropic
or Codebuff. Claude and Claude Code are products of Anthropic. Freebuff is a product of Codebuff.
