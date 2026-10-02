---
name: meeting-minutes
description: "Use when producing or revising the weekly team meeting minutes docx: transcribing the meeting audio, reconciling it with any context files (tracker, agenda, earlier minutes, notes), and building the signed minutes. Triggers: 'meeting minutes for [date]', 'write the minutes', a meeting audio file with or without context files, 'reconcile the minutes', 'write up the meeting'."
---

# Weekly meeting minutes

These instructions are for any coding agent that can run shell commands and read files (Claude Code, Freebuff,
and similar). "You" means the agent; "the user" is the person at the keyboard.

The minutes are a **compliance record** that is reviewed in audit. Two things matter above all:
**accuracy** (an honest gap beats a confident wrong figure) and **consistency** (same structure and
format every meeting). Completeness is third.

## Step 0: gate (do this first, every time)

1. Run the quick gate: `powershell -NoProfile -ExecutionPolicy Bypass -File "S\..\..\minutes-setup\scripts\preflight.ps1" -Gate`
   It prints `READY` or `NOT READY: <reason>` (setup never finished, the kit was updated and needs the wizard
   again, a package is missing, and so on). READY may be followed by a `NOTE:` that a newer team-files bundle has been
   downloaded: tell the user, and offer to run the setup wizard again to update the roster before you start. If it is
   not READY, STOP and use the `minutes-setup` skill. Do not
   try to install or repair things yourself.
2. Read `%USERPROFILE%\.claude\meeting-minutes\roster.local.md` in full. It holds the team's roster, name
   spellings, item areas, section bands, approver and any team-specific rules. Everything below assumes
   you have read it. If it is missing, STOP and use `minutes-setup`.
3. Read `references/format.md` (house format, naming, pagination).

In every command below, `PY` = `%USERPROFILE%\.claude\meeting-minutes\venv\Scripts\python.exe` and `S` = this
skill's `scripts` folder. Always call `PY`, never a bare `python`.

## Sources

0. **Two microphones? Merge them first.** If the meeting was recorded by two separate recorders (each mic saves its
   own files, often in 30-minute chunks), put each mic's files in its own folder and run
   `PY S\merge_mics.py --mic-a "<folder A>" --mic-b "<folder B>" --out "<meeting folder>\audio.wav" --samples`
   It joins each mic's chunks, measures the start offset by cross-correlating speech (not by file timecodes, which
   are unreliable), delays the earlier mic with `adelay`, verifies the residual offset is ~0 BEFORE mixing, then mixes
   to mono. It stops with a message if the mics disagree or the alignment does not land.
   **Then the user must listen** to the three `*.sample-*.wav` files it writes (merged, mic A, mic B). A hollow or
   phasey merged sample means comb filtering; rerun with `--single a` or `--single b` and use whichever mic has the better
   room pickup. Do not transcribe until the user says the merged sample sounds clean. With one mic, skip this step.
1. **Meeting audio to a speaker-labelled transcript.** Primary source for *what was said* and for names.
   `PY S\transcribe.py "<audio>" --attendees "Name1,Name2,..." --out "<folder>\<name>.whisper.txt"`
   - List the enrolled people who were actually present in `--attendees`; it pins the speaker count. Check
     the exact spellings with `PY S\speaker_profiles.py list`.
   - **Run it in the background** if your shell tool allows it (many stop foreground commands after about
     10 minutes), sending its output to a log file. If you cannot background it, give the user the exact
     command to run in their own terminal and wait for them. On a PC without an NVIDIA GPU it can take an hour or more; tell the user roughly
     how long (the setup wizard measured it: `rtf` in `setup-complete.json`, seconds of work per second of
     audio). There is no transcript to reconcile until it finishes.
   - It keeps the PC awake while running and checkpoints each stage. If the run is interrupted (the agent
     closed, power cut), run the SAME command again: it resumes. `--fresh` throws the checkpoint away.
   - **Name the unknown speakers.** The end of the output lists "speakers found". Any marked `NOT NAMED` is a
     voice with no saved profile. Show the user the two sample lines and ask who it is. Never guess. Then:
     `PY S\speaker_profiles.py relabel "<transcript>" SPEAKER_01="Full Name"` renames them in the transcript.
     Offer to remember the voice for next time (it is stored on this PC only, so ask first):
     `PY S\speaker_profiles.py enroll-cluster "<audio>" "<transcript>.segments.json" SPEAKER_01 "Full Name"`
     Use the exact name spelling the roster uses. If the user is unsure who a voice is, leave it as
     `SPEAKER_XX` and work it out from the content and the roster, and say so in the review list.
2. **Context files (optional, any kind).** The user may hand you anything that could be relevant: a tracker, an agenda,
   earlier minutes, a slide deck, notes, an attendee list. The audio is the base and decides what was said; context only
   helps you get names, spellings, numbers and identities right, and where it has them it is authoritative for those.
   Convert documents with `markitdown` first (in the kit's `venv\Scripts`). If nothing was supplied, ask once whether
   there is anything relevant; if not, carry on from the audio alone and list what you could not verify.
   **A weekly tracker workbook (.xlsx):** read the column for
   the week the meeting reports on, which is the week BEFORE the meeting. The meeting-week column and
   later hold planned items, not a record. Cut it down to that one week first (a full tracker can be 250 KB; the slice
   is a few KB and cannot leak the planned column):
   `PY S\tracker_slice.py "<tracker.xlsx>" --meeting-date YYYY-MM-DD -o "<folder>\tracker-slice.md"`, then read the `.md`.
   Read its "Skipped" list: a sheet with no matching week may need a look by hand. If the slice is empty or the layout is
   unusual, fall back to `markitdown.exe "<tracker.xlsx>" -o "<tracker>.md"` (in the kit's `venv\Scripts`) and pick the
   column yourself.
3. Manual notes, if any: a bonus spine for structure and ownership. Not required.
4. A Teams or Fireflies transcript, if present: a quick cross-check only. Auto-summaries garble names.

## Flow

1. **Transcribe** the audio (above).
2. **Reconcile** the transcript against the context files into a list of items, each with discussion bullets and
   action bullets (rules below). Write it as `meeting.json`: copy `S\meeting.example.json` and replace the content.
3. **Lint** the draft before building anything:
   `PY S\lint_minutes.py meeting.json --transcript "<transcript>" --context "<context file or tracker-slice.md>" [more context files]`
   Fix every ERROR (dashes, placeholders, owners not on the roster, hedged time). Go through every WARN against the sources:
   a number, name or reason word it flags is either wrong or needs to be true from the source. Whatever you keep goes on the
   review list for the user. A clean lint is not proof the minutes are right.
4. **Build** the docx once: `PY S\build_minutes.py meeting.json "DD-MM-YYYY meeting minutes.docx"`.
   **Layout (ask once, then remember).** If `config.json` has no `"layout"` key and there is no
   `%USERPROFILE%\.claude\meeting-minutes\template.docx`, ask the user which page layout to use:
   - **Bundled**: the kit's own layout. Set `"layout": "bundled"` in `config.json`.
   - **You make one**: ask for page size, margins, font, header and footer text, logo image, page numbers. Write
     a docx with exactly that (python-docx, no body text) to `template.docx` in that folder. Render it and show the user.
   - **Their example**: the user gives a .docx (past minutes, a letterhead). Copy it to `template.docx`.
   With `template.docx` present, the builder keeps its page size, margins, fonts, headers and footers, drops its body
   text, and fits the tables to its page width. The table layout itself always comes from the builder. Set
   `"layout": "template"`. The user can change their mind any time: delete `template.docx` and the `layout` key.
5. **Verify**: `powershell -ExecutionPolicy Bypass -File S\render_pdf.ps1 "<docx>"`, then read the PDF/PNG pages:
   pagination, no bullet broken mid-page, sign-off block whole. This is a rough check only (see references/format.md).
6. **Human review gate.** Before anything is signed, give the user the list of points you were unsure about
   (`[to confirm]` items, unresolved speakers, values that differ from the context). The user checks the docx
   in Word against the recording where needed. Do not sign until they say the content is frozen.
7. **Sign**: `PY S\sign_minutes.py "<docx>" --date D/M/YYYY`. File as `DD-MM-YYYY meeting minutes.docx` with the
   audio, transcript and copies of the context files used beside it.

After the first build, **edit the .docx directly** (small python-docx patch scripts or Word COM). Do not re-run
`build_minutes.py`: once it is hand-edited, the docx is the source of truth.

## Reconcile rules

**Header facts: derive or ask, never guess.**
- Time: start from the calendar entry or the user's statement; end = start + recording length. No
  "(estimated)" or hedges in a compliance header. Resolve it or ask.
- Weekday: omit unless you actually compute it from the date.
- Venue: confirm the room and the join setup with the user. Do not assume last meeting's.
- Approver: ask the user who approves this week's minutes. `config.json` holds a default, but it can change;
  put the confirmed name in `meeting.json` as `"approver"`.
- Attendance = who actually spoke or was confirmed present. Record an absentee's reason exactly as stated in
  the meeting; do not infer "leave" or a cause the transcript does not give. If the transcript garbles the
  reason, decode conservatively or write `[reason unclear]`. Blank is fine when no reason was given.
  `roster.local.md` says who is reference-only and never attends.

**Items: group discussion by owner and recurring topic area, numbered sequentially.** The count varies by
meeting. Adjust to what was actually discussed; one topic per row. The recurring areas and section bands for
this team are in `roster.local.md`. Use only the bands that have content.

**Action items.** An action bullet is `[the person the discussion says will do it]: [what they were told or agreed to do]`.
- Owner = who was named as doing it, not who the topic belongs to. If Alex says "I'll review it", the owner
  is Alex even under someone else's item.
- If nobody was assigned, the whole cell is `For noting.`
- **Not an action** (do not write these as bullets): a meeting already on the calendar; someone describing
  what they are already doing; a number or status report; a tentative "we should / we might need to think
  about X" with no owner and no firm commitment, even from the chair; a general aspiration nobody owns.
  Invent no owners. If it was agreed but unowned, phrase it without a name prefix. An open point the meeting
  defers to a later forum ("raise at the HOD meeting") is an action on the chair even without an explicit
  "X will raise it".

**State bare facts only.** Every added sentence is a claim, and an inferred one can be wrong. Do not add
linking sentences, rationales, footnotes, or explanations of who joined how or why unless the transcript or
a context file explicitly supports them. If two facts might be connected, write them as separate bullets. Cross-check
every proper noun against the context files' own spelling and `roster.local.md` before trusting the transcript.

**Contested values.**
- Meeting value contradicts a context file: use the meeting's value for that meeting's decisions and append
  `(differs from tracker)` (or the name of that context source).
- The meeting itself is unclear (people disagree, arithmetic muddled): write the range or `[to confirm]`.
  Never pick one silently.

**Writing:** no em-dashes or en-dashes (ranges as "to"); short declarative sentences for facts; cut process
narration and anything a table already shows; keep decision rationale.

## Common mistakes

- With a weekly tracker: reading the meeting-week column (planned items) instead of the prior week.
- Attributing an action to the item's owner instead of the person who said they would do it.
- Turning a scheduled meeting or a status report into an action bullet.
- Guessing the start time or weekday; leaving "(estimated)" in the header.
- Inferring an absence reason, or a reason someone joined late, that the transcript did not give.
- Running `build_minutes.py` again after hand-editing the docx.
- Signing before the user has confirmed the content is frozen.
- Mixing two mics with `-itsoffset` inside an `amix` graph (silently ignored, gives an audible echo) or trusting the mics' embedded timecodes. Use `merge_mics.py`.
- Promoting a single meeting's detail into a standing rule. Per-meeting facts belong in that meeting's minutes.
- Using a shortened name where `roster.local.md` says the full name is required.

## Updating this skill

Claude Code plugin route: `claude plugin marketplace update meeting-minutes-kit`, then `claude plugin update meeting-minutes@meeting-minutes-kit`, then restart
(or use the `/plugin` menu).
Skills route: re-run the install line from the README (the PowerShell one-liner, or `pnpm --config.dlx-cache-max-age=0 dlx github:Jem-Jem-Jem/meeting-minutes-kit install`,
with the same `-Agents` / `-Dir` option if the skills were installed somewhere other than `~/.claude/skills`). Neither touches
`%USERPROFILE%\.claude\meeting-minutes`.
