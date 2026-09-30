# Team Pass (any chatbot, no install)

For anyone producing the minutes **without** Claude Code. Two parts: reconcile (any chatbot) and
assemble (Word, no code). The maintainer supplies the team-specific blocks marked `[PASTE ...]`.

## Before you start

You need a **transcript of the meeting**. Free chatbots cannot transcribe audio. Get one of:
- the `*.whisper.txt` from someone with the full tool installed (most accurate), or
- Microsoft Teams' own meeting transcript (Recap, Transcript, download).

You also need the **weekly tracker** (.xlsx): export the relevant tabs to text/CSV, or paste the relevant cells.

**Data sensitivity:** transcripts and trackers contain student names, application numbers and commercial
terms. A free consumer chatbot sends that data outside your organisation. Prefer an in-tenant assistant
(for example Microsoft Copilot) where you can.

## HOW TO USE

1. Copy everything inside the dashed block below and fill the two `[PASTE ...]` lines from the maintainer's `roster.local.md`.
2. Paste it at the start of a new chat, then the transcript, then the tracker data, then say "produce the minutes".

## THE PASS

```
You are producing the weekly team meeting minutes for our organisation. These minutes are a COMPLIANCE RECORD reviewed in audit. Two things matter most: ACCURACY (an honest gap beats a confident wrong figure) and CONSISTENCY (same structure every week). Completeness is third.

I will paste: (1) a meeting transcript, (2) weekly-tracker data. Produce the minutes as a Markdown table I can paste into the Word template.

=== SOURCES ===
- Transcript = what was said. Primary source for names and terms.
- Weekly tracker = authoritative for spellings, numbers, identities. Use the column for the week BEFORE the meeting (the meeting reports on the prior week; the meeting-week column is planned items, not a record).

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
- Meeting value contradicts the tracker -> use the meeting's value, append "(differs from tracker)".
- Meeting itself unclear (people disagree, arithmetic muddled) -> write the range or "[to confirm]". Never pick one silently.

=== WRITING ===
No em-dashes or en-dashes (ranges as "to"). Short declarative sentences for facts. Active voice. Cut process narration and anything a table already shows; keep decision rationale. Bold any date or money amount inside a discussion line.

=== OUTPUT ===
A Markdown table: | S/N | Discussion Items | Action |. Section-heading rows as | **Heading** | | |. Each item: bold title line then "- " bullets in the Discussion cell; "- **Owner:** ..." bullets in the Action cell. Then an Appendix with the schedules the maintainer specified, numbers from the tracker. End with a list of every point you were unsure about.

Ready. Paste the transcript.
```

## ASSEMBLE (no code)

1. Get the blank template docx from the maintainer. It has the header block, a pre-styled 3-column table with section bands, the sign-off block and empty appendix schedules, all in house format.
2. Fill the header (date, time, venue, attendance, not-present).
3. For each item: copy a blank item row, fill the S/N, Discussion and Action cells from the chatbot output. Bold the title line and any dates/money.
4. Fill the appendix schedules.
5. Closing line, then the sign-off block: the preparer signs and dates; the approver's side is left blank.
6. Save as `DD-MM-YYYY meeting minutes.docx`. Keep the transcript and the tracker export in the same folder: that is the audit evidence trail.
7. Open in Word and check pagination: no bullet broken across a page; sign-off block whole.
