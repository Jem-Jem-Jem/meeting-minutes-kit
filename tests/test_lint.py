"""Runnable check for lint_minutes.py and tracker_slice.py (fictional data): python tests/test_lint.py"""
import datetime, json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
S = os.path.join(HERE, "..", "plugin", "skills", "meeting-minutes", "scripts")
tmp = tempfile.mkdtemp()
env = {**os.environ, "MINUTES_HOME": os.path.join(tmp, "none")}

def w(name, text):
    p = os.path.join(tmp, name); open(p, "w", encoding="utf-8").write(text); return p

transcript = w("t.txt", "[0.0-5.0] Alex Example: Good morning. Partner A asked for the programme fact sheet on the twenty eighth of December.\n"
    "[5.0-9.0] Sam Sample: Twelve applications were submitted and nine were approved. The budget of two thousand dollars is confirmed.\n"
    "[9.0-12.0] Sam Sample: I will review the creative before the fifth of February.\n")
tracker = w("k.md", "- Applications submitted: 12\n- Applications approved: 9\n- Pending documents: 3\n")
roster = w("r.md", "| Alex Example | Team Lead |\n| Sam Sample | Marketing Manager |\n| Riley Placeholder | BD Executive |\n")

good = {"date": "1 October 2030", "time": "10:00 AM to 10:45 AM", "venue": "Room", "attendance": ["Alex Example, Team Lead", "Sam Sample, Marketing Manager"],
        "not_present": ["Riley Placeholder, BD Executive."], "closing": "There being no further business, the meeting concluded at 10:45 AM.",
        "items": [{"section": "Pipeline"},
                  {"title": "Partner engagement (Sam)", "discussion": ["Partner A asked for the programme fact sheet on 28 Dec.", "12 applications were submitted and 9 approved; 3 await documents."],
                   "actions": ["Sam: Review the creative before 5 Feb."]}],
        "schedules": [{"title": "Schedule 1: Intake", "columns": ["Category", "Count"], "rows": [["Approved", "9"]]}]}
bad = json.loads(json.dumps(good))
bad["time"] = "about 10:00 AM to 10:45 AM"
bad["items"][1]["discussion"] += ["Budget rose to S$2,500 because Sam Simple asked for more \u2014 agreed.", "Zed will phone Partner B."]
bad["items"][1]["actions"] += ["Zed: Phone Partner B.", "[Action placeholder]"]

def run(cfg, extra=()):
    p = w("m.json", json.dumps(cfg))
    return subprocess.run([sys.executable, os.path.join(S, "lint_minutes.py"), p, "--transcript", transcript, "--context", tracker, "--roster", roster, *extra],
                          capture_output=True, text=True, env=env)

r = run(good); assert r.returncode == 0 and "0 error" in r.stdout, r.stdout + r.stderr
r = run(bad); out = r.stdout
assert r.returncode == 1, out
for needle in ("time is hedged", "dash character", "number 2500", "reason word 'because'", "'Simple'", "action owner 'Zed'", "template placeholder"):
    assert needle in out, f"missing expected finding {needle!r}\n{out}"
print("lint_minutes: clean file passes; all 7 planted problems are caught")

# tracker slicer: one sheet weeks-as-columns, one weeks-as-rows
import openpyxl
wb = openpyxl.Workbook(); a = wb.active; a.title = "Cols"
a.append(["", "WEEK OF 8 SEP", "WEEK OF 15 SEP", "WEEK OF 22 SEP"]); a.append(["Leads", 4, 7, 99]); a.append(["Note", "x", "seen last week", "planned only"])
b = wb.create_sheet("Rows"); b.append(["", "DONE", "NEXT"]); b.append(["WEEK OF 15 SEP", "finished the thing", "n/a"]); b.append(["WEEK OF 22 SEP", "planned only", ""])
xl = os.path.join(tmp, "t.xlsx"); wb.save(xl)
r = subprocess.run([sys.executable, os.path.join(S, "tracker_slice.py"), xl, "--meeting-date", "2026-09-23", "--year", "2026"], capture_output=True, text=True, env=env)
assert "seen last week" in r.stdout and "finished the thing" in r.stdout, r.stdout + r.stderr
assert "planned only" not in r.stdout and "99" not in r.stdout, "the meeting-week column leaked into the slice:\n" + r.stdout
print("tracker_slice: reads the week BEFORE the meeting from both layouts and leaves the meeting week out")
