#!/bin/bash
# cold boot, medium res, GEMBENCH, Test>CPU (Float Math). Log to /tmp/run_fm.log
P="python3 /tmp/st.py"
$P "c" sleep25 "key ctrl+r" sleep2 "key ret" sleep6 "key alt+a" sleep4 "mouse -15 -45" "click" sleep3 "mouse 36 -6" "click 2" sleep20 \
   "mouse -120 -120" "mouse -120 -120" "mouse -120 -120" "mouse 80 0" "mouse 85 0" sleep1 "mouse 0 5" "mouse 0 10" "mouse 0 10" "click" sleep40
echo DONE
