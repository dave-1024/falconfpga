# FreeMiNT memory protection test (MPTEST)

`./mkimg.sh` builds `mint_mp.st` (720 KB, not committed): TOS 2.06 boots it, `AUTO\STAGE0.PRG`
writes `A:\STAGE0.TXT`, `AUTO\MINT030.PRG` (FreeMiNT 1.19 snapshot 4a6b3e82, 020-060 archive,
pinned by `zip.sha256`) starts with `MEM_PROT=YES`, `WRITE_BOOT=YES` (`\MINT\1-19-CUR\BOOT.LOG`) and
`KERN_MPFLAGS=1` (MPF_STRICT), and runs `A:\MPTEST.PRG` as INIT (no GEM, no XaAES).
`MP=NO ./mkimg.sh mint_nomp.st` builds the same image with memory protection off (diagnostic only).

MPTEST writes `A:\MPTEST.TXT`:
- Ssystem(S_OSFEATURES) bit 0 = memory protection on;
- child V writes to the parent's private memory: MiNT must stop it (it raises SIGBUS for a
  memory violation; the child's handler exits $5A, $5B for SIGSEGV) and the parent's word stays;
- three children W run side by side (Syield between fill and check of their own 16 KB), exit 0.

Hatari (box): `hatari --machine ste --tos tos206uk.img --cpulevel 3 --cpuclock 16 --mmu true
--fpu none --compatible true --memsize 4 --disk-a mint_mp.st --fast-forward true`, then
`mtype -i mint_mp.st ::/MPTEST.TXT`.

Board: `up2.py mint_mp.st mint_mp.st`, `hc.py "mount a mint_mp.st" c`, then on linserver
`python3 rdst2.py mint_mp.st MPTEST.TXT` / `MINT/1-19-CUR/BOOT.LOG` / `STAGE0.TXT`.
