# Team Pass (any chatbot, no agent needed)

For anyone producing the minutes **without** a coding agent. Two parts: reconcile (any chatbot) and
assemble (Word, no code). The maintainer supplies the team-specific blocks marked `[PASTE ...]`.

## Before you start

You need a **transcript of the meeting**. Free chatbots cannot transcribe audio. Get one of:
- the `*.whisper.txt` from someone with the full tool installed (most accurate), or
- Microsoft Teams' own meeting transcript (Recap, Transcript, download).

Optionally add **context** that could be relevant: a tracker (export the relevant tabs to text/CSV, or paste the relevant cells), an agenda, earlier minutes, notes.

**Data sensitivity:** transcripts and context files contain student names, application numbers and commercial
terms. A free consumer chatbot sends that data outside your organisation. Prefer an in-tenant assistant
(for example Microsoft Copilot) where you can.

## HOW TO USE

1. Copy everything inside the dashed block below and fill the two `[PASTE ...]` lines from the maintainer's `roster.local.md`.
2. Paste it at the start of a new chat, then the transcript, then the context, then say "produce the minutes".

## THE PASS

```
You are producing the weekly team meeting minutes for our organisation. These minutes are a COMPLIANCE RECORD reviewed in audit. Two things matter most: ACCURACY (an honest gap beats a confident wrong figure) and CONSISTENCY (same structure every week). Completeness is third.

I will paste: (1) a meeting transcript, (2) any context files (a tracker, agenda, earlier minutes, notes). Produce the minutes as a Markdown table I can paste into the Word template.

=== SOURCES ===
- Transcript = what was said. Primary source for names and terms.
- Context files = authoritative for spellings, numbers and identities where they have them. If a context file is a weekly tracker, use the column for the week BEFORE the meeting (the meeting reports on the prior week; the meeting-week column is planned items, not a record).

=== NAMES, ROSTER, ITEM AREAS, SECTION HEADINGS ===
[PASTE the roster, name-garble table, recurring item areas and section headings from roster.local.md]

=== HEADER: derive or ask, never guess ===
- Date: from the meeting. Weekday: omit unless you can compute it.
- Time: ask me for the start time and the recording length. Do NOT write "(estimated)" or any hedge.
- Venue: ask me.
- Attendance = who actually spoke or was confirmed present. Record an absentee's reason exactly as stated in the meeting; do not infer "leave" or a cause the transcript does not give.

=== ITEMS: group by owner and topic area, numbered sequentially, only those with content ===

=== ACTION ITEMS ===
An action bullet is: "[the person the discussion says will do it]: [what they were told or agreed to do]".
- Owner = who was named as doing it, not whose topic it is.
- If nobody was assigned, the whole Action cell = "For noting."
- NOT actions (do not write these): a meeting already on the calendar; someone describing what they are already doing; a status/number report; an aspiration nobody owns. Invent no owners.

=== STATE BARE FACTS ===
Do not add linking sentences, rationales, footnotes or explanations that the transcript or tracker does not explicitly support.

=== CONTESTED VALUES ===
- Meeting value contradicts a context file -> use the meeting's value, append "(differs from tracker)" (or that source's name).
- Meeting itself unclear (people disagree, arithmetic muddled) -> write the range or "[to confirm]". Never pick one silently.

=== WRITING ===
No em-dashes or en-dashes (ranges as "to"). Short declarative sentences for facts. Active voice. Cut process narration and anything a table already shows; keep decision rationale. Bold any date or money amount inside a discussion line.

=== OUTPUT ===
Reply with ONE JSON object and nothing else (no code fence, no commentary), exactly this shape:
{
  "date": "1 October 2030",
  "time": "10:00 AM to 10:45 AM",
  "venue": "...",
  "attendance": ["Name, Job title"],
  "not_present": ["Name, Job title. Reason as stated in the meeting"],
  "items": [
    {"section": "Section heading"},
    {"title": "Item title (owner)", "discussion": ["bullet", "bullet"], "actions": ["Owner: what they will do"]}
  ],
  "closing": "There being no further business, the meeting concluded at 10:45 AM.",
  "schedules": [
    {"title": "Schedule 1: ...", "columns": ["Category", "Count"], "rows": [["...", "9"]]}
  ],
  "unsure": ["every point you were unsure about, one string each"]
}
Use an empty "actions" list when nobody was assigned (the builder writes "For noting."). Numbers in schedules come from the tracker. Do not add keys other than the ones shown.

Ready. Paste the transcript.
```

## BUILD THE DOCUMENT

**With the kit installed (recommended):** save the chatbot's reply as `meeting.json` and run
`<kit python> build_minutes.py meeting.json "DD-MM-YYYY meeting minutes.docx"` (see the README), then review it in Word and
run `sign_minutes.py` when the content is final.

## ASSEMBLE BY HAND (no code at all)

1. Get the blank template docx from the maintainer. It has the header block, a pre-styled 3-column table with section bands, the sign-off block and empty appendix schedules, all in house format.
2. Fill the header (date, time, venue, attendance, not-present).
3. For each item: copy a blank item row, fill the S/N, Discussion and Action cells from the chatbot output. Bold the title line and any dates/money.
4. Fill the appendix schedules.
5. Closing line, then the sign-off block: the preparer signs and dates; the approver's side is left blank.
6. Save as `DD-MM-YYYY meeting minutes.docx`. Keep the transcript and the context files in the same folder: that is the audit evidence trail.
7. Open in Word and check pagination: no bullet broken across a page; sign-off block whole.
