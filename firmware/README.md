[Pico pinout](https://pico.pinout.xyz/#l=21aDIR;22aSTEP;23aCLK;24aMS2;25aMS1;26ePDN%2F1k;27ePDN;29aEN;36dVDD&i=upl)

## Calibration

- if opto on back off to opto off `<--`
- advance to opto on `-->`
- retreat slightly too far `<--`
- measure distance to opto on `-->`
- retreat the right distance `<--`

## References

[TMC2209 Datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/TMC2209_datasheet_rev1.09.pdf)

## Build

```sh
zig build buttons -Dconfig=etc/rp2040.old.cfg -Dprogram --watch
```
