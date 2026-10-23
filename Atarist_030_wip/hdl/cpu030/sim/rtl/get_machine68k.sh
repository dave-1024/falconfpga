#!/bin/sh
# Fetch machine68k 0.4.1 (Musashi-based 68k emulator, PyPI sdist) for the Musashi-vs-RTL write diffs
# (docs/history/investigations/float_panic/diff/mu*.py). Not needed by run_rtl.sh. Replaces the tarball
# that used to be committed here (same file, same SHA256).
set -e; cd "$(dirname "$0")"
F=machine68k-0.4.1.tar.gz
SHA=a58ae3f0f5f32639296e7eaf564f2aa96852462078e35b0c6d8e714d2510a9cb
[ -f "$F" ] || curl -fsSLo "$F" https://files.pythonhosted.org/packages/97/68/2503566b74f87ec968440432463791a75454f56b0f972231cafd13e8a12e/machine68k-0.4.1.tar.gz
echo "$SHA  $F" | sha256sum -c -
echo "Install with: pip install ./$F"
