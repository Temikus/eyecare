# Flicker testing plan

Candidate IOMFB keys for reducing backlight PWM, ranked, with the values measured on this machine.

- Hardware: MacBook Pro 13" M2 (T8112), internal panel `disp0` (`AppleCLCD2`)
- OS: macOS 27.0 (26A428), Darwin 27.0.0
- Values captured 2026-09-19 with `pwmctl get`; acceptance from `pwmctl probe --write`
- Origin column is a string diff of this build's kernel collection against the pre-update one
  (Darwin 25.6.0), both from `/System/Volumes/Preboot`

Re-measure with `pwmctl get` before trusting any value below: everything here is runtime state.

## Before you start

```sh
pwmctl baseline save        # known-good state, per OS build
pwmctl baseline diff        # what has drifted since
pwmctl baseline restore     # the reset button
```

Use `--revert-after N` on every experiment. It restores the previous value after N seconds and on
`^C`, so a knob that blacks out the panel recovers without a reboot.

## Tier 1

| key | now | try | origin | why |
|---|---|---|---|---|
| `enablePulseWidthMaximization` | `0` | `1` | pre-27 | Maximizing the pulse width is the mitigation, by name. Start here. |
| `requestPixelBacklightModulation` | `false` | `true` | pre-27 | Dim in the pixel domain rather than chopping the backlight. |
| `forcePixelBacklightModulation` | `2` | `1`, then `0` | pre-27 | Companion to the above; `2` looks like auto. Write it under this name - the runtime name `pixelBacklightModulationForceState` is rejected. |
| `BLMAHOutputFreq` | `0` | `1`, then larger | pre-27 | Backlight-modulation output frequency. Units unknown, `0` is likely driver default. |
| `BLMAHMode` | `2` | `0`, `1`, `3` | pre-27 | Mode select on the same block; may switch dimming strategy wholesale. |
| `IOMFBDigitalDimmingLevel` | `289984` (4.4248 q16) | `6.0q16`, `8.0q16` | pre-27 | More digital dimming should let the backlight sit at a higher duty cycle. Risky. |

```sh
pwmctl set enablePulseWidthMaximization=1 --revert-after 30
pwmctl set requestPixelBacklightModulation=true --revert-after 30
pwmctl set forcePixelBacklightModulation=1 --revert-after 30
pwmctl set BLMAHOutputFreq=1 --revert-after 30
pwmctl set BLMAHMode=1 --revert-after 30
pwmctl set IOMFBDigitalDimmingLevel=6.0q16 --revert-after 30
```

## Tier 2

| key | now | try | origin | note |
|---|---|---|---|---|
| `enableBLMSloper` | `true` | `false` | pre-27 | Ramp smoothing; affects transitions more than steady state. |
| `BLMVLEDManual` | `230` | `200`, `240` | pre-27 | LED drive level. Lower drive may force a longer on-time for the same nits. Risky. |
| `BLNitsCap` | `34406400` (525.0 q16) | `300.0q16` | pre-27 | Capping peak nits may push dimming into the digital path. Risky. |
| `brightnessCorrection`, `brightnessCorrectionB` | `65536` (1.0 q16) | `0.8q16` | pre-27 | Plain scale factors; useful as a control. |
| `BLMPLimitCfg`, `BLMAHUPCount` | `1`, `0` | vary | pre-27 | Semantics unknown, cheap to sweep. |
| `enableDither`, `uniformity2D` | `false`, `false` | - | pre-27 | Already off. The two knobs that were known before this work. |

## Introduced in macOS 27 - try these on another Mac

Darwin 27.0 added 55 runtime properties (`pwmctl keys --new-in 27`). Seven are dimming-related, and
none of them is published on this panel - but this panel is the plain 60 Hz IPS with a Touch Bar
(`IOMFBIsHiloDevice = false`, `IOMFBSupportsLFC = false`). A mini-LED or ProMotion display is a
different DCP configuration, so the same OS may well publish them there. Worth carrying to a
14"/16" Pro or a newer SoC before concluding anything.

### First, on the new machine

```sh
just build && pwmctl displays          # confirm the internal panel's node name
pwmctl baseline save                   # before touching anything
just reference-probe                   # records the panel's capabilities to reference/<model>.md
pwmctl get --all-keys | grep -iE 'hilo|lfc|hbld|dbv|nits|dimming|modulation'
```

`just reference-probe` captures everything below in one file - node list, backlight hardware,
capability flags, dimming values, which macOS 27 keys are published, and which writes the driver
accepts. Compare it against [reference/](reference/) for the machines already recorded.

The catalog comes from IOMobileGraphicsFamily, which is shared across SoCs, so it carries over to
any Mac on the same OS build. On a different build, run `just regen-catalog` there first.

The `ioreg` line is separate because those values live on the backlight device node, not on
`AppleCLCD2`: on this machine `pwm-frequency` is 24000000, `DBVMin` is 15, and there is a
`DBV2NitsTable` and a `nits-to-pwm-percentage` table. Read them before trying `DBVValue`, since the
sensible range is panel-specific.

### The keys

| key | type | try | note |
|---|---|---|---|
| `enableHBLD` | bool | `true` | Hybrid backlight dimming, on/off. Gate for the two below. |
| `HBLDDimmingFactorMin` | 16.16 | `0.25q16`, `0.5q16` | Floor on the dimming factor - the most promising shape of knob in the whole set: a floor is what stops the backlight going into deep duty cycles. |
| `HBLDNitsRRMax` | 16.16 nits | `50.0q16`, `100.0q16` | Nits ceiling for the hybrid path. |
| `ccMinNitsConfig` | 16.16 nits | `2.0q16`, `5.0q16` | Minimum-nits configuration; raising it may stop the panel reaching its dimmest, worst-flicker state. |
| `DBVValue` | raw register | above that panel's `DBVMin` | Direct brightness-value override. Read `DBVMin`/`DBV2NitsTable` first, and never without `--revert-after`. |
| `DBVInterval` | int | `1`, then larger | Unclear; likely a timing interval for the above. |
| `enableDBTH` | bool | `true` | Unclear, brightness-threshold shaped. |

```sh
pwmctl set enableHBLD=true --revert-after 30 --revert-to enableHBLD=false
pwmctl set enableHBLD=true HBLDDimmingFactorMin=0.5q16 --revert-after 30 \
    --revert-to enableHBLD=false --revert-to HBLDDimmingFactorMin=0
pwmctl set ccMinNitsConfig=2.0q16 --revert-after 30 --revert-to ccMinNitsConfig=0
pwmctl set enableDBTH=true --revert-after 30 --revert-to enableDBTH=false
```

These keys are unpublished until the first successful write, so there is no prior value to restore
and `--revert-after` alone is refused. `--revert-to KEY=VALUE` says what to go back to; the values
above assume the feature is off by default, which is why they are stated rather than guessed by the
tool.

Types are inferred from the naming convention (`enable*` is a boolean, `*Nits`/`*Factor` are 16.16),
not observed - nothing here has been accepted anywhere yet. If a write returns bad argument, try the
other type before concluding the key is unavailable.

### Other groups worth a look on a different panel

- **refresh** (8 keys: `enableRR`, `enableRRBP`, `enableRRBPGainOverride`, `enableNESR`, `enableRTR`,
  `enableRegammaRRSupport`, `enableGenLock`, `genLockFrequency`) - on a ProMotion panel these are
  likely live, and variable refresh interacts with perceived flicker.
- **thermal** (`IRDCACCEnable`, `IRDCTempOverride`, `PTUCAvgTempGridPos`, `PTUCAvgTempOption`) -
  IR-drop compensation is emissive-panel machinery; expect it on mini-LED, not on this IPS.
- `isHiloDevice` and `SupportsSecureIndicator` read as capability flags worth checking first: a
  machine where `isHiloDevice` is true has local dimming zones and a different backlight path
  entirely.

### What this panel reported

Unpublished keys are rejected whatever type is sent:

```
enableHBLD=false            → bad argument (0xe00002c2)
HBLDDimmingFactorMin=0      → bad argument
ccMinNitsConfig=0           → bad argument
```

`enableDither=5` (wrong type on a published key) returns the same code, so that error means only
"the handler did not take this pair". With 81 of 82 published keys accepted and no unpublished key
accepted, the working rule on this machine is that the settable set equals the published set.

The other route to them is boot-time: each key also exists as an `iomfb_RuntimeProperty_<name>`
string, which is the shape of a boot-arg name. That needs Permissive Security (SIP is enabled here,
no boot-args set), so it is a separate, bigger experiment - and the hypothesis is unverified.

## Method

- Fix brightness low and leave it there: PWM depth is usually worst at the bottom of the range.
- One key at a time. `set` prints `[unchanged: driver ignored it]` when a write is accepted but the
  value does not move.
- After setting a `BLM*` key, nudge brightness one step. Those likely re-apply only when the
  backlight is recomputed, so a knob can look inert until then.
- `pwmctl get --json <keys>` for a machine-readable before/after; `pwmctl baseline diff` to confirm
  nothing from an earlier run is still in effect.
- Record the machine and panel with each result: what a key does depends on the backlight path, and
  the keys above are unpublished on the IPS panel this plan was written on.

## Results

| date | machine / panel | key | value | flicker change | notes |
|---|---|---|---|---|---|
| | | | | | |
