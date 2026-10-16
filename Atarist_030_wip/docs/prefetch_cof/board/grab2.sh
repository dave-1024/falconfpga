#!/bin/bash
# usage: grab2.sh name  -> name.png (1920x1080) + name_prev.png (960x540) in cwd
R=/tmp/g_$$.png
timeout 50 ssh -o "ProxyCommand=nc -X 5 -x localhost:1055 %h %p" dave@100.97.139.11 "ffmpeg -loglevel error -y -f v4l2 -input_format yuyv422 -video_size 1920x1080 -i /dev/video0 -vf select='gte(n\,60)' -frames:v 1 $R && cat $R && rm -f $R" > "$1.png"
python3 -c "from PIL import Image; Image.open('$1.png').convert('RGB').resize((960,540)).save('$1_prev.png')"
