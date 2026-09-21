# MacBookPro18,1

| | |
|---|---|
| Machine | MacBook Pro |
| SoC | Apple M1 Pro |
| Serial | `W37V7XX***` (last 3 characters withheld) |
| OS when recorded | 26.6.2 (25G83), Darwin 25.6.0 |
| Internal panel node | `disp0` |
| Recorded | 2026-09-21 |

## Framebuffer nodes

```
NAME      CLASS       ENTRY ID     KEYS  
disp0     AppleCLCD2  0x10000092a  196   (default target)
dispext0  AppleCLCD2  0x10000092b  149   
dispext1  AppleCLCD2  0x100000949  139   
```

## Panel and backlight hardware

From the backlight device node via `ioreg`, not from `AppleCLCD2`.

| key | value |
|---|---|
| `pwm-frequency` | 24000000 |
| `FPWM Frequency` | 0 |
| `DBVMin` | - |
| `backlight-level-encoding` | - bits |
| `new-backlight-architecture` | Yes |
| `DBV2NitsTable` | absent |
| `nits-to-pwm-percentage` | present |
| `backlight-marketing-table` | present |

Panel identity: "ManufacturerID"="00-10-fa","ProductID"=54100216591425,"LegacyManufacturerID"=1552

## Capability flags

| key | value |
|---|---|
| `IOMFBIsHiloDevice` | not published |
| `IOMFBSupportsLFC` | false |
| `IOMFBSupportsGPLite` | false |
| `IOMFBSupportsICC` | true |
| `ALSSSupported` | false |
| `SPLCSupported` | false |
| `IOMFBSwapAppleLookSupported` | true |
| `IOMFBBrightnessCompensationEnable` | true |
| `IOMFBTemperatureCompensationEnable` | true |

## Dimming and backlight properties

| key | value | risk |
|---|---|---|
| `BLMAHMode` | 2 | safe |
| `BLMAHOutputFreq` | 0 | safe |
| `BLMAHUPCount` | 0 | safe |
| `BLMPLimitCfg` | 1 | safe |
| `BLMPowergateEnable` | true | safe |
| `BLMVLEDManual` | 220 | risky |
| `BLNitsCap` | 26214400 (400.0000 q16) | risky |
| `brightnessCorrection` | 65536 (1.0000 q16) | safe |
| `brightnessCorrectionB` | 65536 (1.0000 q16) | safe |
| `enableAmbientLightSensorStatistics` | false | safe |
| `enableBLMSloper` | true | safe |
| `enableDither` | false | safe |
| `enablePulseWidthMaximization` | 0 | safe |
| `IOMFBBrightnessCompensationEnable` | true | safe |
| `IOMFBBrightnessLevel` | 9293857 (141.8130 q16) | risky |
| `IOMFBBrightnessLevelIDAC` | -1 (-0.0000 q16) | risky |
| `IOMFBBrightnessLevelMA` | -1 (-0.0000 q16) | risky |
| `IOMFBDigitalDimmingLevel` | 65536 (1.0000 q16) | risky |
| `IOMFBIndicatorBrightnessNits` | 65536 (1.0000 q16) | safe |
| `IOMFBIndicatorNitsCap` | 104857600 (1600.0000 q16) | safe |
| `limit_max_physical_brightness` | 104857600 (1600.0000 q16) | risky |
| `requestPixelBacklightModulation` | false | safe |
| `uniformity2D` | false | safe |

## macOS 27 dimming additions

| key | published here |
|---|---|
| `ccMinNitsConfig` | no |
| `DBVInterval` | no |
| `DBVValue` | no |
| `enableALSSFCAMStats` | no |
| `enableHBLD` | no |
| `HBLDDimmingFactorMin` | no |
| `HBLDNitsRRMax` | no |

## Accepted writes

`probe --write`: 70 accepted, 4 rejected of 74 published catalogued keys.

Rejected:

- `DCPIndex` - bad argument (wrong value type?) (0xe00002c2)
- `enableLinearToPanel` - unsupported (driver does not take this key) (0xe00002c7)
- `PCC2DLedAccelOut` - general error (0xe00002bc)
- `requestPixelBacklightModulation` - unsupported (driver does not take this key) (0xe00002c7)

## Notes

-
