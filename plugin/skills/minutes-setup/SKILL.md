---
name: minutes-setup
description: "Use when setting up or repairing the meeting-minutes tool on a computer: first-time setup, 'set up the minutes tool', 'minutes tool not working', missing dependencies, or when meeting-minutes says setup is not complete. Checks the machine, then hands the user an interactive wizard for the parts only they can do."
---

# Minutes tool setup

The setup wizard installs what is missing, walks the user through the human-only steps (HuggingFace
token, signature image, team files) and proves the whole chain works. **The wizard is interactive. You
cannot run it: your shell has no keyboard input. The user runs it in their own PowerShell window.**

`SETUP` = the `scripts` folder of this skill (its base directory is shown when this skill loads).

## Steps

1. **Check the machine (read-only, safe to run).**
   `powershell -NoProfile -ExecutionPolicy Bypass -File "SETUP\preflight.ps1"`
   (`-Gate` instead of nothing gives a one-line READY / NOT READY.) Summarise the result in plain words for the user: what is fine, what will be installed, whether the
   machine has an NVIDIA GPU (fast) or not (works, slower), and any blockers. Blockers you cannot fix:
   no desktop Word, too little disk or RAM, no network. Tell the user what to do about each.
2. **If `setup-complete.json` is missing or the check shows anything to install or fix**, tell the user to open a
   normal PowerShell window (Start menu, type "PowerShell") and run this, with the real path filled in:

   ```
   powershell -ExecutionPolicy Bypass -File "SETUP\setup.ps1"
   ```

   Tell them what it will ask: where the team files are (it looks in Downloads, Desktop, Documents and OneDrive
   first, so if the maintainer's `minutes-team-files.zip` is already downloaded it offers that path), their name
   and job title, a signature image, and a free HuggingFace token. Tell them the first run downloads several GB and can take a while.
3. **Wait.** When the user says it finished, run the preflight again and confirm: no blockers, nothing left to
   install, and `%USERPROFILE%\.claude\meeting-minutes\setup-complete.json` exists. Tell them to restart Claude
   Code once, then say "write the meeting minutes".

## Rules

- Never ask the user to paste the HuggingFace token, a password, or the contents of `config.json` into chat. The
  wizard takes the token in a hidden prompt on the user's own machine.
- Never read, print or echo the `HF_TOKEN` environment variable.
- Never install anything yourself. Every install goes through the wizard, with the user's consent.
- The wizard is safe to re-run; it skips finished steps.
- If the wizard fails, ask the user to paste the last screen of output (it contains no secrets) and diagnose from that.
- Team files (`minutes-team-files.zip`, or the loose `roster.local.md`, `team.local.json`, optional `speaker_profiles.json`) come from the maintainer.
  Never invent, edit or publish them.
