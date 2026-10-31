#!/bin/bash
# bv.sh T C0C C0F C1C C1F [EXTRA_DEFINE] : copy sd64_wt tree, set pll_sd phases, build
T=$1; set -e
rm -rf ~/bt_$T; mkdir -p ~/bt_$T; cd ~/sd64_wt; tar cf - --exclude=impl Atarist_030_wip | tar xf - -C ~/bt_$T
cd ~/bt_$T/Atarist_030_wip; P=hdl/tang/console138k/gowin_pll/pll_sd64_mod.v
sed -i "s/CLKOUT0_PE_COARSE = .*;/CLKOUT0_PE_COARSE = $2;/; s/CLKOUT0_PE_FINE = .*;/CLKOUT0_PE_FINE = $3;/; s/CLKOUT1_PE_COARSE = .*;/CLKOUT1_PE_COARSE = $4;/; s/CLKOUT1_PE_FINE = .*;/CLKOUT1_PE_FINE = $5;/" $P
if [ -n "$6" ]; then python3 - "$6" <<'P'
import sys; f="build_st_helper_hdn.tcl"; s=open(f).read(); k='puts $fh "`define SDRAM64"\n'
assert k in s; s=s.replace(k,k+'puts $fh "`define %s"\n'%sys.argv[1]); open(f,"w").write(s)
P
fi
grep -n "CLKOUT[01]_PE" $P; grep -n "define SD" build_st_helper_hdn.tcl
QT_QPA_PLATFORM=offscreen /opt/gowin/IDE/bin/gw_sh build_st_helper_hdn.tcl > ~/bt_$T.log 2>&1 || { echo "gw rc=$?"; exit 1; }
cp impl/pnr/st_helper.fs ~/fpga_bitstreams/st_helper_hdn_$T.fs; rm -rf ~/${T}_pnr; cp -r impl/pnr ~/${T}_pnr; echo BUILDDONE
