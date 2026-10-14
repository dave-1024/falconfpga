O="--std=08 -fsynopsys -frelaxed --workdir=work"
r=$(ghdl -r $O tb030 -gROMFILE=s$1.hex -gIPL_MODE=2 -gTRIG6=$2 -gVEC6=69 -gWS=$3 -gWSRND=$4 -gIRQ_DLY=$5 -gMAXCLK=8000 -gQUIET=1 -gSTOPDONE=1 2>/dev/null | grep -E "DONE|TIMEOUT|WR   A=0000500[08]|IACK")
echo "$* :: $(echo "$r"|tr '\n' ' ')"
