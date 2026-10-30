import re,sys,html,os
KW=re.compile(r'fetch_state|ew_ack|dr_in_use|store_adr_format',re.I)
def short(n): return n.replace('misterynano/atarist/cpu030/i_wf68k30l/','')
out=["# Worst timing paths touching FETCH_STATE / NEXT_FETCH_STATE / EW_ACK / DR_IN_USE / STORE_ADR_FORMAT\n",
"Extracted from each build's `st_helper.timing_paths` (Gowin PnR output, the explicit report_timing paths, 95 per build). Any path whose start, end, or intermediate node name contains one of those keywords (case-insensitive) is listed, worst slack first. Clock pair comes from matching slack + start + end in `st_helper_tr_content.html`; '?' if no match. Times in ns. Node prefix `misterynano/atarist/cpu030/i_wf68k30l/` removed. Note: Gowin renames combinational nets (`NEXT_FETCH_STATE_16_s7` etc. are LUTs that came from that signal), so only names that survived synthesis can be found.\n"]
for b in ["f97n","f97p1","f97B","f97fx","f97C","f97fw"]:
    t=open(f"{b}/st_helper.timing_paths").read().split("=====")
    h=html.unescape(re.sub(r"<[^>]+>"," ",open(f"{b}/st_helper_tr_content.html",errors="replace").read())); h=re.sub(r"\s+"," ",h)
    rows=re.findall(r" \d+ (-?\d+\.\d+) (\S+)/\w+ (\S+)/\w+ (\S+?):\[\w\] (\S+?):\[\w\]",h)
    cmap={(r[0],r[1],r[2]):(r[3],r[4]) for r in rows}
    paths=[]
    for blk in t:
        l=[x for x in blk.strip().split("\n") if x.strip()]
        if len(l)<6: continue
        kind,slack=l[0],l[1]; nodes=[x for x in l[4:] if not re.match(r'^-?[\d.]+$',x)]
        hits=[n for n in nodes if KW.search(n)]
        if not hits: continue
        ck=cmap.get((slack,nodes[0],nodes[-1]),('?','?'))
        paths.append((float(slack),kind,nodes,hits,ck))
    paths.sort(key=lambda p:(p[1],p[0]))
    out.append(f"\n## {b}\n\n{len(paths)} matching path(s) of {len([x for x in t if x.strip()])}.\n")
    for s,k,n,hits,ck in paths:
        out.append(f"- **{k} slack {s:.3f}** ({ck[0]} -> {ck[1]}), {len(n)} nodes: `{short(n[0])}` -> `{short(n[-1])}`")
        out.append(f"  - matching nodes: " + ", ".join(f"`{short(x)}`" for x in dict.fromkeys(hits)))
open("paths_excerpt.md","w").write("\n".join(out)+"\n")
