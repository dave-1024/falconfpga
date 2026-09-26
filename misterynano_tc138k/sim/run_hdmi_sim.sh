#!/bin/bash
# HDMI encoder toggle check. Run from misterynano_tc138k/.
# Does not touch the Gowin project. Does not write into the repo.
echo "HDMI_SIM_NOTE: logic serializer, not the Gowin PLL or OSER10. PASS means the encoder toggles. It does not prove the placed pins."
if ! command -v iverilog >/dev/null 2>&1 || ! command -v vvp >/dev/null 2>&1; then
  echo "SIM_TOOL_MISSING iverilog"
  echo "HDMI_SIM NOT_RUN"
  exit 2
fi
iverilog -V
OUT=/tmp/hdmi_pin_sim
rm -rf "$OUT"
mkdir -p "$OUT"
iverilog -g2012 -DTMDS_BY_LOGIC -o "$OUT/hdmi.vvp" \
  hdmi/audio_clock_regeneration_packet.sv \
  hdmi/audio_info_frame.sv \
  hdmi/audio_sample_packet.sv \
  hdmi/auxiliary_video_information_info_frame.sv \
  hdmi/hdmi.sv \
  hdmi/packet_assembler.sv \
  hdmi/packet_picker.sv \
  hdmi/serializer.sv \
  hdmi/source_product_description_info_frame.sv \
  hdmi/tmds_channel.sv \
  sim/tb_hdmi_pins.sv
IV_EXIT=$?
echo "IV_EXIT:$IV_EXIT"
if [ "$IV_EXIT" -ne 0 ] || [ ! -f "$OUT/hdmi.vvp" ]; then
  echo "HDMI_SIM FAIL compile"
  exit 1
fi
vvp "$OUT/hdmi.vvp"
echo "VVP_EXIT:$?"
