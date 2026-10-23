#!/bin/bash
# TTRAM whole-ST bench: prog_tt.s with TT-RAM on, then prog_bus.s TT on / TT off (ST timing must
# equal the build without TTRAM: compare the trace files). Usage: run_tt.sh <wf030.vg> [scratch]
set -e
H=$(cd "$(dirname "$0")" && pwd); NET=$(readlink -f $1); W=${2:-/tmp/simtt}
BUS_DEFS=-DTTRAM PROG=prog_tt PHASES=15625 $H/run_bus.sh $NET $W/tt bus +maxus=${MAXUS:-3000}
