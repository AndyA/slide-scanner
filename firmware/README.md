[Pico pinout](https://pico.pinout.xyz/#l=01bDBG_TX;02bDBG_RX;03bDBG_GND;04cRED_LED;05cRED_SW;06aYEL_LED;07aYEL_SW;08iSW_GND;09fBLU_LED;10fBLU_SW;11iBLK_LED;12iBLK_SW;21aDIR;22aSTEP;23aCLK;24aMS2;25aMS1;26ePDN_TX%2F1k;27ePDN_RX;29aEN;36dVDD&i=pl)

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
