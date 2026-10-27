#!/usr/bin/env python3
"""Worst setup/hold slack per explicit report_timing clock pair in a Gowin timing report.

The Gowin "Total Negative Slack" table shows 0 for the related 68030 clock pairs even when the
explicit report_timing tables (atarist_st_helper.sdc, F58) list negative slack. Use this check,
not TNS alone. Usage: timing_pairs.py <impl/pnr dir or st_helper_tr_content.html>
Exit 1 if any listed pair has a negative worst slack.
"""
import html, os, re, sys
p = sys.argv[1]
if os.path.isdir(p): p = os.path.join(p, "st_helper_tr_content.html")
t = html.unescape(re.sub(r"<[^>]+>", " ", open(p, errors="replace").read())); t = re.sub(r"\s+", " ", t)
bad = 0
pat = (r"Paths Table\[\d+\]: Report Command:report_timing -(setup|hold) -max_paths \d+ -max_common_paths 1 "
       r"-from_clock \[get_clocks \{(\S+)\}\] -to_clock \[get_clocks \{(\S+)\}\] Path Number Path Slack "
       r"From Node To Node From Clock To Clock Relation Clock Skew Data Delay 1 (-?[\d.]+) (\S+) (\S+)")
for m in re.finditer(pat, t):
    kind, a, b, s, frm, to = m.groups(); s = float(s)
    flag = "FAIL" if s < 0 else "ok"; bad |= s < 0
    print("%-5s %-13s -> %-13s %8.3f %s  %s -> %s" % (kind, a, b, s, flag, frm.split("/")[-2], to.split("/")[-2]))
sys.exit(1 if bad else 0)
