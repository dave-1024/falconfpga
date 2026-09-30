# Licence notes for Atarist_030_wip

This folder does not have one licence. Each part keeps the licence it came
with, and the header inside a file always wins. See `NOTICE.md` and
`LICENSE-ORIGINAL.md` at the top of the repository for the project as a whole.

| Part | Author / origin | Licence |
|---|---|---|
| Atari ST core and support files copied from MiSTeryNano (see `UPSTREAM.md`) | MiSTeryNano / MiSTery authors | Each file's own header. MiSTeryNano had no top-level licence file at the imported commit, so files without a header have no stated licence of their own. |
| `fx68k/` (the 68000, used when `CPU_030` is off) | Jorge Cwik | GPL-3.0, text in `fx68k/LICENSE` |
| `fdc1772/`, `jt49/` and other files with a GPL header | Till Harbaum, Jose Tejada and others | GPL-3.0-or-later, as stated in each header |
| `hdmi/` | Sameer Puri (hdl-util/hdmi) | MIT OR Apache-2.0 (as stated upstream) |
| `cpu030/wf68k30L_*.vhd` (the 68030 core) | Wolfgang Foerster, Inventronik GmbH | CERN OHL v1.2, as stated in the VHDL headers. Keep those headers. Any changes we make to the core (such as adding the caches) should be marked in the changed files, as the OHL asks. |
| `cpu030/cpu030_st_bridge.v` (the ST bus bridge) | New for this project, modelled on TerribleFire TF534 by Stephen J. Leary | GPL-2.0-only, like TF534. Text in `cpu030/LICENSE-GPL2-TF534` |
| Frame buffer and DVI output (`tang/console138k/st_framebuffer.v`, `hdmi_640.sv`, `hdmi_testpattern_640.sv`, `video_testpattern_640.v`), the CPU selection and wiring changes, docs and scripts | David Dunne | GPL-3.0-or-later (`LICENSE-ORIGINAL.md`), unless a file header says otherwise |

Not included: Atari TOS, EmuTOS images, bitstreams and build outputs.

## Open question before any public release

The bridge is GPL-2.0-only, while fx68k and most of the ST core are GPL-3.
The GPL-2-only and GPL-3 licences are not compatible with each other, so a
single bitstream that contains both may not be distributable as it stands.
It is also unclear how well CERN OHL v1.2 combines with the GPL. This does
not matter while the work stays private, but it must be settled before the
repository or any bitstream is made public. Possible ways forward:

1. Ask Stephen J. Leary for permission to use the TF534-derived parts under
   GPL-3 (or "GPL-2 or later").
2. Rewrite the bridge from the Motorola 68000 and 68030 manuals, without
   TF534 as a source, and release it as GPL-3.0-or-later.

This is a summary to help decide, not legal advice.
