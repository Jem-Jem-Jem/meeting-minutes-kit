# -*- coding: utf-8 -*-
"""Meeting-minutes SCAFFOLD builder. Run ONCE per meeting.

    python build_minutes.py meeting.json "DD-MM-YYYY meeting minutes.docx"

Reads a meeting.json (see meeting.example.json), applies the house format and
readability pass (zebra rows, repeating header, fixed columns, section bands,
bold dates in prose, action bullets with bold owner, right-aligned counts),
and writes the .docx. After this first build, edit the .docx DIRECTLY (small
python-docx patch scripts or Word COM). Do NOT re-run this on a hand-edited file.

Org name, team name, venue default and sign-off names come from
~/.claude/meeting-minutes/config.json unless meeting.json overrides them.
"""
import json
import os
import re
import sys

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

HDR = '1F3864'      # top header row
BAND = '2E4B7A'     # thematic section band rows
ZEBRA = 'EEF1F6'    # alternate-row shading
DATA_DIR = os.environ.get('MINUTES_HOME') or os.path.join(os.path.expanduser('~'), '.claude', 'meeting-minutes')
DATE_RE = re.compile(r'(S\$\d[\d,\.]*k?|\b\d{1,2}\s(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)(?:\s\d{4})?\b)')
WHITE = RGBColor(0xFF, 0xFF, 0xFF)


def shade(cell, hexcolor):
    tcPr = cell._tc.get_or_add_tcPr()
    sh = OxmlElement('w:shd')
    sh.set(qn('w:val'), 'clear'); sh.set(qn('w:color'), 'auto'); sh.set(qn('w:fill'), hexcolor)
    tcPr.append(sh)


def cantsplit(row):
    row._tr.get_or_add_trPr().append(OxmlElement('w:cantSplit'))


def repeat_header(row):
    e = OxmlElement('w:tblHeader'); e.set(qn('w:val'), 'true')
    row._tr.get_or_add_trPr().append(e)


def tight(p):
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.space_before = Pt(0)
    cs = OxmlElement('w:contextualSpacing'); cs.set(qn('w:val'), '0')
    p._p.get_or_add_pPr().append(cs)
    # keepLines: this paragraph's own lines never split across a page break, while the
    # table row still breaks freely BETWEEN paragraphs. Do NOT use row-level cantSplit on
    # content rows instead - it forces whole items to jump pages and leaves large blank
    # gaps. See references/format.md, "Pagination".
    p._p.get_or_add_pPr().append(OxmlElement('w:keepLines'))


def add_bold_dates(p, text, size=10):
    last = 0
    for m in DATE_RE.finditer(text):
        if m.start() > last:
            p.add_run(text[last:m.start()]).font.size = Pt(size)
        r = p.add_run(m.group(0)); r.bold = True; r.font.size = Pt(size)
        last = m.end()
    if last < len(text):
        p.add_run(text[last:]).font.size = Pt(size)
    if not p.runs:
        p.add_run(text).font.size = Pt(size)


def action_bullet(cell, text, first):
    p = cell.paragraphs[0] if first else cell.add_paragraph()
    p.style = cell.part.document.styles['List Bullet']
    tight(p)
    if ': ' in text[:45]:
        head, rest = text.split(': ', 1)
        r = p.add_run(head + ': '); r.bold = True; r.font.size = Pt(10)
        p.add_run(rest).font.size = Pt(10)
    else:
        p.add_run(text).font.size = Pt(10)


def set_widths(table, widths):
    table.autofit = False
    for row in table.rows:
        for i, w in enumerate(widths):
            row.cells[i].width = Inches(w)


def cell_text(cell, text, bold=False, size=10.5, color=None, align=None):
    cell.text = ''
    p = cell.paragraphs[0]
    if align:
        p.alignment = align
    for j, line in enumerate(text.split('\n')):
        if j > 0:
            p = cell.add_paragraph()
            if align:
                p.alignment = align
        r = p.add_run(line)
        r.bold = bold; r.font.size = Pt(size)
        if color:
            r.font.color.rgb = color


def load_config():
    cfg = {}
    path = os.path.join(DATA_DIR, 'config.json')
    if os.path.exists(path):
        with open(path, encoding='utf-8-sig') as f:
            cfg = json.load(f)
    return cfg


def build(m, cfg, out):
    org = m.get('org') or cfg.get('org') or 'Organisation Name'
    team = m.get('title') or cfg.get('meeting_title') or 'Team Meeting Minutes'
    preparer = m.get('preparer') or cfg.get('scribe_name') or ''
    approver = m.get('approver') or cfg.get('approver_name') or ''

    doc = Document()
    st = doc.styles['Normal']
    st.font.name = 'Calibri'
    st.font.size = Pt(10.5)

    h = doc.add_paragraph(); h.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = h.add_run(org); r.bold = True; r.font.size = Pt(14)
    h2 = doc.add_paragraph(); h2.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = h2.add_run(team); r.bold = True; r.font.size = Pt(12)

    def meta(label, value):
        p = doc.add_paragraph(); p.paragraph_format.space_after = Pt(2)
        r = p.add_run(label + '  '); r.bold = True; r.font.size = Pt(10.5)
        p.add_run(value).font.size = Pt(10.5)

    meta('Date:', m['date'])
    meta('Time:', m['time'])
    meta('Venue:', m.get('venue') or cfg.get('venue') or '')

    p = doc.add_paragraph(); p.paragraph_format.space_after = Pt(2)
    p.add_run('Attendance:').bold = True
    for name in m.get('attendance', []):
        b = doc.add_paragraph(style='List Bullet'); b.paragraph_format.space_after = Pt(0)
        b.add_run(name).font.size = Pt(10.5)

    p = doc.add_paragraph(); p.paragraph_format.space_before = Pt(4); p.paragraph_format.space_after = Pt(2)
    p.add_run('Not present:').bold = True
    for name in m.get('not_present', []):
        b = doc.add_paragraph(style='List Bullet'); b.paragraph_format.space_after = Pt(0)
        b.add_run(name).font.size = Pt(10.5)
    for note in m.get('notes', []):
        p = doc.add_paragraph(); p.paragraph_format.space_after = Pt(2)
        p.add_run(note).font.size = Pt(10.5)

    doc.add_paragraph()

    # ---------- Discussion table ----------
    table = doc.add_table(rows=1, cols=3)
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for c, t in zip(table.rows[0].cells, ['S/N', 'Discussion Items', 'Action']):
        cell_text(c, t, bold=True, color=WHITE, align=WD_ALIGN_PARAGRAPH.CENTER)
        shade(c, HDR)
    cantsplit(table.rows[0])
    repeat_header(table.rows[0])

    item_no = 0
    for entry in m.get('items', []):
        row = table.add_row()
        cells = row.cells
        if 'section' in entry:
            a = cells[0].merge(cells[1]).merge(cells[2])
            cell_text(a, entry['section'], bold=True, color=WHITE)
            shade(a, BAND)
            # keepNext: a band header is never stranded alone at the bottom of a page.
            a.paragraphs[0]._p.get_or_add_pPr().append(OxmlElement('w:keepNext'))
            continue
        item_no += 1
        cell_text(cells[0], str(item_no), bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)
        dc = cells[1]; dc.text = ''
        p = dc.paragraphs[0]
        r = p.add_run(entry['title']); r.bold = True; r.font.size = Pt(10.5)
        tight(p)
        for pt in entry.get('discussion', []):
            bp = dc.add_paragraph(style='List Bullet')
            tight(bp)
            add_bold_dates(bp, pt, size=10)
        ac = cells[2]; ac.text = ''
        actions = entry.get('actions') or ['For noting.']
        for i, a in enumerate(actions):
            action_bullet(ac, a, i == 0)
        if item_no % 2 == 0:
            for c in cells:
                shade(c, ZEBRA)

    tblPr = table._tbl.tblPr
    lay = OxmlElement('w:tblLayout'); lay.set(qn('w:type'), 'fixed'); tblPr.append(lay)
    set_widths(table, [0.4, 4.3, 1.8])

    # No forced page break before the closing line or the sign-off block: the sign-off
    # table's own row-level cantSplit protects it, and keepLines/keepNext already pack
    # the discussion table. A forced break can strand a near-empty page.
    p = doc.add_paragraph()
    p.add_run(m['closing']).italic = True

    doc.add_paragraph()

    sign = doc.add_table(rows=3, cols=2)
    sign.style = 'Table Grid'
    for _row in sign.rows:
        cantsplit(_row)
    cell_text(sign.rows[0].cells[0], 'Prepared by:', bold=True)
    cell_text(sign.rows[0].cells[1], 'Approved by:', bold=True)
    cell_text(sign.rows[1].cells[0], '\n\n' + preparer)
    cell_text(sign.rows[1].cells[1], '\n\n' + approver)
    cell_text(sign.rows[2].cells[0], 'Date: ___/___/____        Signature: __________')
    cell_text(sign.rows[2].cells[1], 'Date: ___/___/____        Signature: __________')

    # ---------- Appendix ----------
    schedules = m.get('schedules', [])
    if schedules:
        p = doc.add_paragraph(); r = p.add_run('Appendix'); r.bold = True; r.font.size = Pt(12)
        p._p.get_or_add_pPr().append(OxmlElement('w:keepNext'))
    for si, s in enumerate(schedules):
        if si:
            doc.add_paragraph()
        p = doc.add_paragraph(); p.add_run(s['title']).bold = True
        p._p.get_or_add_pPr().append(OxmlElement('w:keepNext'))  # title never stranded above its table
        cols = s['columns']
        t = doc.add_table(rows=1, cols=len(cols)); t.style = 'Table Grid'
        for i, name in enumerate(cols):
            cell_text(t.rows[0].cells[i], name, bold=True, color=WHITE); shade(t.rows[0].cells[i], HDR)
        right_last = len(cols) == 2 and s.get('right_align_count', True)
        for n, rowvals in enumerate(s['rows']):
            row = t.add_row().cells
            for i, v in enumerate(rowvals):
                al = WD_ALIGN_PARAGRAPH.RIGHT if (right_last and i == 1) else None
                cell_text(row[i], v, align=al)
            if n % 2 == 1:
                for c in row:
                    shade(c, ZEBRA)
        widths = s.get('widths') or ([4.5, 1.5] if len(cols) == 2 else [6.5 / len(cols)] * len(cols))
        set_widths(t, widths)
        if s.get('note'):
            doc.add_paragraph(s['note']).runs[0].italic = True

    doc.save(out)
    print('SAVED', out)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: python build_minutes.py meeting.json out.docx')
    with open(sys.argv[1], encoding='utf-8-sig') as f:
        meeting = json.load(f)
    build(meeting, load_config(), sys.argv[2])
