# Fill this folder

Git currently has the Console 138K *project* files:

- `atarist_tc138k.gprj`
- `build_tc138k.tcl` (device_version **C**, JTAG-as-GPIO, replicate on)
- `README.md`
- `.gitignore`

The HDL list in the `.gprj` is not on Git yet (~90 source files, ~1 MB). Drop them in with the **same relative paths** as the `.gprj` (`tang/console138k/top.sv`, `atarist/atarist.v`, …).

## Fastest on Windows (GitHub website)

1. Unzip `misterynano_tc138k` from the project artifacts (or copy that folder).
2. Open https://github.com/dave-1024/falconfpga/tree/main/misterynano_tc138k
3. Add file → Upload files.
4. Drag the *contents* of the unzipped folder (keep `tang/`, `atarist/`, `fx68k/`, …). Do not nest a second `misterynano_tc138k`.
5. Commit to `main`. Scroll and click **Commit changes** (the progress bar is not the commit).

## Local git

From the clone of `falconfpga`:

```powershell
# $src = unzipped clean tree that already contains tang/, atarist/, fx68k/, …
Copy-Item -Recurse -Force $src\* .\misterynano_tc138k\
git add misterynano_tc138k
git status
git commit -m "Add misterynano_tc138k Console 138K HDL"
git push
```

Then `gw_sh build_tc138k.tcl` from `misterynano_tc138k`.
