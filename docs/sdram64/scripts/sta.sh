#!/bin/bash
# sta.sh <pnr dir>: fmax, TNS, LUTs, sd64 crossing slacks and clock latencies
ssh linserver "cd $1 && python3 -" <<'P'
import re,html
t=html.unescape(re.sub(r"<[^>]+>"," ",open("st_helper_tr_content.html").read())); t=re.sub(r"\s+"," ",t)
i=t.find("Max Frequency Summary"); s=t[i:i+1800]
for c in ("clk32_core","clk_sd64","clk_cpu030 "):
    j=s.find(" "+c); print(s[j:j+45])
i=t.find("Total Negative Slack Summary"); print("nonzero TNS:", re.findall(r"(\S+) (Setup|Hold) (-[\d.]+) (\d+)", t[i:i+6000]))
for m in re.finditer(r"report_timing -(setup|hold)[^\]]*\[get_clocks \{(\w+)\}\] -to_clock \[get_clocks \{(\w+)\}\] Path Number.*?Data Delay 1 ([-\d.]+) (\S+) (\S+) (\S+) (\S+) ([-\d.]+) ([-\d.]+) ([-\d.]+)",t):
    if "sd64" in m.group(2)+m.group(3): print(m.group(1),m.group(2),"->",m.group(3),"slack",m.group(4),"skew",m.group(10),m.group(5)[-30:],m.group(6)[-30:],m.group(7),m.group(8))
for c in ("pll_sd/u_pll/PLL_inst/CLKOUT0","pll_hdmi/u_pll/PLL_inst/CLKOUT1"):
    j=t.find(c); print(t[j-60:j+40])
P
ssh linserver "grep -A1 'LUT,ALU' $1/st_helper.rpt.txt | head -2"
