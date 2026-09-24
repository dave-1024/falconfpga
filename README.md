# falconfpga

Private repo for the Tang Console 138K Atari Falcon FPGA work.

## Oracle (2026-09-24)

`rigsdram/` is the HDL tree that was rebuilt, flashed, and printed:

```
12345
RIGSDRAM GUEST
IMG=74D8E373
T0–T11 PASS
DONE P
```

- Top: `rigsdram/src/rigsdram_top.vhd`
- Device: GW5AST-LV138PG484AC1/I0 **Version C**
- `AUTO_WARM=1`, `TRIG_MODE=3`
- Gowin PnR: **Use Replicate Resources = TRUE**
- Do **not** use `rigsdram/src/New folder/`

## Chat / bot handshake

| File | Owner | Do not |
|---|---|---|
| `BUILD_REQUEST.md` | Grok chat (this lead) | Bot must not edit |
| `BUILD_REPORT.md` | Grok bot (Windows Gowin) | Chat must not edit except to reset the template after reading |

Cycle: chat pushes HDL + a new request → you tell the bot to build → bot pushes a report → you tell chat “read BUILD_REPORT.md”.

See `AGENT_PROTOCOL.md`.
