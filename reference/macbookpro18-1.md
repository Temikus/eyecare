# MacBookPro18,1

| | |
|---|---|
| Machine | MacBook Pro |
| SoC | Apple M1 Pro |
| Serial | `W37V7XX***` (last 3 characters withheld) |
| OS when recorded | 27.0.1 (26A434), Darwin 27.0.0 |
| Internal panel node | `disp0` |
| Recorded | 2026-10-15 |

## Framebuffer nodes

```
NAME      CLASS       ENTRY ID     KEYS  
disp0     AppleCLCD2  0x10000099e  209   (default target)
dispext0  AppleCLCD2  0x1000009a1  162   
dispext1  AppleCLCD2  0x1000009a0  147   
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
| `IOMFBIsHiloDevice` | false |
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
| `BLNitsCap` | 39321604 (600.0001 q16) | risky |
| `brightnessCorrection` | 65536 (1.0000 q16) | safe |
| `brightnessCorrectionB` | 65536 (1.0000 q16) | safe |
| `enableAmbientLightSensorStatistics` | false | safe |
| `enableBLMSloper` | true | safe |
| `enableDither` | false | safe |
| `enablePulseWidthMaximization` | 0 | safe |
| `IOMFBBrightnessCompensationEnable` | true | safe |
| `IOMFBBrightnessLevel` | 31407546 (479.2411 q16) | risky |
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

`probe --write`: 82 accepted, 3 rejected of 85 published catalogued keys.

Rejected:

- `enableLinearToPanel` - unsupported (driver does not take this key) (0xe00002c7)
- `PCC2DLedAccelOut` - general error (0xe00002bc)
- `requestPixelBacklightModulation` - unsupported (driver does not take this key) (0xe00002c7)

## Notes

Recorded on 26.6.2 (25G83) 2026-09-21, regenerated on 27.0.1 (26A434) 2026-10-15. disp0 went from
196 to 209 published keys; the dimming values below are unchanged apart from `BLNitsCap`.

### Panel

- 16" mini-LED ProMotion panel with 2D local dimming: `uniformity2D` and `enableDither` are on
  (both off on the M2 IPS). No Touch Bar node. `IOMFBIsHiloDevice` is unpublished on 26 and
  published `false` on 27, so "Hilo" does not mean local dimming.
- Measured SDR ceiling is 400 nits (`IOMFBBrightnessLevel` at slider maximum), not the 500 Apple
  quotes. `BLNitsCap` read 300 then 400 on 26.6.2 and 600 on 27.0.1, so it is not the SDR cap.
  Driving the panel through the EDR headroom (BetterDisplay direct brightness / XDR upscaling) takes
  `IOMFBBrightnessLevel` to 1601 with plateaus at 1230 and 1601, so the property does track the
  physical backlight target.
- Flicker meter, white field: PWM at roughly 14 kHz at every level. Duty cycle 22% at 1230 nits,
  38% at 1600 nits. Peak output is still 38% duty, so continuous drive is unreachable by raising
  brightness; every level-shaped knob can only move between those two figures.
- Backlight node carries `backlight-calibration-parameters` (lMinPanel 260799 = 3.98, lMidProduct,
  lMaxPanel, current-for-mid-backlight, current-for-max-backlight, hardware-max-current-limit
  1146880 = 17.5 in 16.16), `backlight-update-policy`, the `nits2mAmps*Coef` triple, the
  `milliAmps2DAC*` tables and `iDAC2MilliAmpsTable`. `DBVMin`, `backlight-level-encoding` and
  `DBV2NitsTable` are absent, unlike the M2 IPS. `lMinPulseWidthMaximization`, the calibration
  parameter the DCP firmware pairs with `enablePulseWidthMaximization`, is absent.

### Runtime writes, both builds

- Accepted, stored, read back and inert against the meter (duty at fixed nits unchanged after a
  brightness nudge): `BLMVLEDManual` 150/180/200/240, `BLMPLimitCfg` 0/2/3,
  `IOMFBBrightnessLevelMA` 3.2q16, `enablePulseWidthMaximization` 1, `enableDither` false,
  `uniformity2D` false, `BLMAHMode`, `BLMAHOutputFreq`, `enableBLMSloper` false. These keys are
  bookkeeping the backlight path does not consult.
- Rejected: `forcePixelBacklightModulation` (uncatalogued, published as `2`) returns unsupported
  (0xe00002c7), the same as `requestPixelBacklightModulation`, so pixel-domain backlight modulation
  is absent from this DCP configuration. `ModeBlm` (published as `0`) refuses every write with
  general error (0xe00002bc), like `PCC2DLedAccelOut`: a read-only status field.
- Other uncatalogued published keys: `BLMStandbyEnable` false, `QMSVRREnableConfig` 0,
  `APTLimitRefreshRate` false, `IOMFBSupportsLFC` false, `APTFixedRR` 0, `AODFixedRR` 0.

### macOS 27.0.1

- None of the seven macOS 27 dimming keys is published, on disp0 or either external node, and each
  rejects writes of both types with bad argument (0xe00002c2): `enableHBLD` true/1,
  `HBLDDimmingFactorMin` 0.5q16/1, `HBLDNitsRRMax` 100.0q16, `ccMinNitsConfig` 2.0q16/2,
  `DBVValue` 100, `DBVInterval` 1, `enableDBTH` true/1. Same rule as the M2: settable set equals
  published set.
- Probe went from 70/74 to 82/85 accepted; `DCPIndex` is now accepted. New on disp0: `enableGenLock`,
  `genLockFrequency`, `IOMFBIsHiloDevice`, `IOMFBSupportsSecureIndicator`, `MaxUABoost`,
  `calibrationType`, `DCPResetLoop*`, `DisableInternalAppleLook`, `forceEnableLPRSwaps`, `primary`,
  `APTEventsMaskHi`, `BICSDaemonPanicOnStartFail`. Nothing new in the dimming category.
- The 321 runtime keys come from the DCP firmware (`t600xdcp.im4p`, LZFSE payload): every
  `iomfb_RuntimeProperty_<name>` string is there, next to `IOMobileFramebuffer::parse_RTP_boot_args()`,
  `IOMFB::get_RTP_boot_arg_name(RuntimeProperty)` and the log line "applying boot-arg RTP %s with
  value 0x%x returned 0x%x". The boot-arg route is therefore real at the firmware level. `HBLDEnable`
  and friends sit in the firmware's feature table beside `IRDC*`, `PTUC*` and `VUCEnable`, so the
  firmware implements HBLD and this panel's configuration leaves it off. Whether a boot-arg can turn
  on a feature the configuration disables is untested.
- `/chosen/allowed-boot-args` here is `trace,trace_wake,kperf,-x,-v,trm_enabled,trace_typefilter,
  nox86exec`, so with SIP on no `iomfb_RuntimeProperty_*` arg reaches the DCP. Permissive Security
  is required. `iomfb_override_max_brightness` is another boot-arg-shaped name in the firmware.
- Conclusion: on this panel the nits-to-duty mapping sits below the runtime property layer on both
  builds. The one untried software route is the boot-arg, and the honest expectation is that the
  flicker is a fixed property of the LED driver.
- Snapshots (local, gitignored): `snapshots/macbookpro18-1-26.6.2.json`,
  `snapshots/macbookpro18-1-27.0.1.json`. Baselines: `baseline-26.6.2-25G83.json`,
  `baseline-27.0.1-26A434.json`.
