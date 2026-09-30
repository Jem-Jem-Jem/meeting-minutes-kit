# Minutes house format, naming, pagination

Reference for the `meeting-minutes` skill. Team-specific names, titles, item areas and
section bands live in `~/.claude/meeting-minutes/roster.local.md`, not here.

**Standing facts vs per-meeting observations.** Only add something to this file or to
`roster.local.md` if it is confirmed across meetings or the maintainer stated it as a rule.
One meeting where someone left early, or an event fell on a certain date, is a fact *for that
meeting's minutes*, not a standing rule. Do not generalise single data points.

## House format

The minutes are a **compliance record**. Format must be consistent run to run.
`build_minutes.py` produces all of the following from `meeting.json`.

**Header block:** organisation name (centre, 14pt bold) / meeting title (centre, 12pt bold), both
from `config.json`. Then `Date:`, `Time:`, `Venue:` meta lines (bold label). `Attendance:` bullet
list; `Not present:` bullet list with a one-line reason each, only if a reason was given.

**Attendance / Not-present line format:** name + job title only, full stop. No qualifiers about
region or what the role covers. The roster table in `roster.local.md` is the detailed reference;
the document's own list stays bare.

**Discussion table:** 3 columns `S/N | Discussion Items | Action`.
- Header row navy `1F3864`, white bold, repeats on every page (`w:tblHeader`).
- Section band rows (merged, full width) navy `2E4B7A`, white bold. Include only bands that have items.
- Item rows: S/N centred bold; discussion cell = bold title line then `List Bullet` bullets; action
  cell = `List Bullet` bullets with the **owner:** prefix bold, or `For noting.` if no action.
- Zebra: even-numbered item rows shaded `EEF1F6`.
- Bullet spacing: 3pt after, 0 before, `contextualSpacing=0`.
- Fixed table layout, columns `0.4 / 4.3 / 1.8` inches.
- Any date or money amount inside discussion prose is bolded automatically (`3 Sep`, `31 Oct`, `S$1,000`).

**Closing line** (italic): `There being no further business, the meeting concluded at [time].`
Adapt if the meeting trailed into internal discussion.

**Sign-off block:** 2 columns, 3 rows. Row 1 `Prepared by:` / `Approved by:` bold. Row 2 preparer name /
approver name. Row 3 `Date: ___/___/____   Signature: ___`. The preparer signs (image + date) via
`sign_minutes.py`; the approver's side stays blank. All rows `cantSplit`.

**Appendix:** schedules defined in `meeting.json` (`schedules`). Navy headers, zebra rows,
right-aligned count column in 2-column schedules. Numbers come from the weekly tracker.

**Writing:** no em-dashes or en-dashes (ranges as "to"); short declarative sentences for facts;
active voice.

## Naming and storage

- File: `DD-MM-YYYY meeting minutes.docx` (for example `07-09-2026 meeting minutes.docx`).
- Keep in the same meeting folder: the source audio, the transcript (`*.whisper.txt`), and a snapshot
  of the weekly tracker used. That set is the audit evidence trail: how the minute was derived.
- Amendments after sign-off: add a dated note of what changed. Never silently overwrite a signed minute.
- Never create, move or edit anything in Teams, SharePoint or OneDrive on the user's behalf. The
  scribe files the finished minutes themselves.

## Scripts

- `scripts/build_minutes.py`: the scaffold builder. Run once per meeting, from a `meeting.json`.
- `scripts/sign_minutes.py`: signature image + date. Run only when content is FROZEN.
- `scripts/render_pdf.ps1`: Word to PDF to PNG pages, for a rough look at pagination.
- `scripts/merge_mics.py`: two mic recordings (with chunks) to one mono file.
- `scripts/transcribe.py`, `scripts/speaker_profiles.py`: audio to speaker-labelled transcript.

## Pagination: how to prevent mid-bullet page breaks

**Use `keepLines` on every bullet and title paragraph, plus `keepNext` on section band headers. Do
NOT use table-row `cantSplit` on the content rows, and do NOT manually split an item into
continuation rows.** `build_minutes.py`'s `tight()` helper sets `w:keepLines` on every paragraph it
touches, and the section-band code sets `w:keepNext`. Keep both when editing the builder.

Why this and not the alternatives (each was tried and rejected by the user on a real document):
- `cantSplit` on a whole item's row forces the ENTIRE row to the next page if it does not fit, even a
  12-bullet item, leaving large blank gaps.
- Pre-splitting a long item into small continuation rows bounds the gap but still leaves visible
  dead space, because Word can push a whole small chunk to a fresh page when most of it fit.
- `keepLines` is per paragraph: a paragraph's own lines never split, but the row breaks freely
  BETWEEN paragraphs, so content packs tightly and no bullet is ever cut mid-sentence. `keepNext`
  keeps a band header glued to the first bullet after it.

**Do not force a hard page break before the sign-off block or before the Appendix.** A forced break
fights the tight packing and can strand a near-empty page. The sign-off table's own row-level
`cantSplit` keeps it from being torn apart; let it flow.

**Do not trust an automated Word-to-PDF render as proof pagination is fixed.** On a real document the
automated render repeatedly looked clean while the user's own Word showed mid-bullet breaks at the
same spots. Treat the render as a rough first pass. When the user reports a break the render does not
reproduce, believe their screenshot over your pipeline.
