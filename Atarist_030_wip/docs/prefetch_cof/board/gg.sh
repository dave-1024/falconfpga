#!/bin/bash
# gg.sh name: grab until non-black (up to 12 tries), wiggle pointer net zero
for t in $(seq 12); do ./grab2.sh $1 >/dev/null 2>&1; m=$(python3 -c "from PIL import Image,ImageStat;print(int(ImageStat.Stat(Image.open('$1.png').convert('L')).mean[0]))" 2>/dev/null); [ -n "$m" ] && [ "$m" -ge 5 ] && { echo "$1 ok mean $m"; exit 0; }; timeout 20 ../hc.sh "mouse 1 0" >/dev/null 2>&1; timeout 20 ../hc.sh "mouse -1 0" >/dev/null 2>&1; sleep 6; done; echo "$1 BLACK"
