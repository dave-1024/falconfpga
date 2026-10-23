#!/bin/bash
# go.sh X Y [click|click 2] : move ST pointer to 960x540-preview coords (home top-left, small linear steps)
X=$1; Y=$2; shift 2
dx=$(( X*10/${XS:-15} )); dy=$(( (Y-30)*10/25 ))
c=("mouse -127 -127" "mouse -127 -127" "mouse -127 -127" "mouse -127 -127")
while [ $dy -gt 0 ]; do s=$(( dy>10?10:dy )); c+=("mouse 0 $s"); dy=$((dy-s)); done
while [ $dx -gt 0 ]; do s=$(( dx>10?10:dx )); c+=("mouse $s 0"); dx=$((dx-s)); done
[ -n "$1" ] && c+=("sleep 0.5" "$*")
timeout 90 $(dirname $0)/../hc.sh "${c[@]}" >/dev/null 2>&1
