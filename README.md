# pwmctl

[![CI](https://github.com/Temikus/eyecare/actions/workflows/ci.yml/badge.svg)](https://github.com/Temikus/eyecare/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

A CLI for the IOMFB framebuffer properties behind backlight dimming, dithering and PWM behaviour
on Apple Silicon Macs. Built to hunt for flicker mitigations beyond the two knobs everyone knows
(`enableDither`, `uniformity2D`), with a revert timer so a bad value cannot leave you stuck.

Every knob is a runtime property on an `AppleCLCD2` node, so **a reboot clears everything**.

## Install

Needs only the Xcode Command Line Tools and [`just`](https://github.com/casey/just).

```sh
just install     # builds release, copies to ~/.local/bin/pwmctl
just test
```

## Use

```sh
pwmctl baseline save                  # record the known-good state FIRST
pwmctl displays                       # the framebuffer nodes on this machine
pwmctl get                            # catalogued properties of the internal panel, by category
pwmctl get --all-keys                 # everything the node publishes
pwmctl keys --category dimming        # browse the key catalog
pwmctl keys --new-in 27               # keys macOS 27 added
pwmctl probe --write                  # which keys the driver accepts (rewrites values unchanged)
pwmctl snapshot --out before.json     # raw dump, for diffing across OS updates
```

## Getting unstuck

```sh
pwmctl baseline save        # while the display is known good
pwmctl baseline diff        # what has drifted since
pwmctl baseline restore     # put the saved values back
```

The baseline lives in `~/.config/pwmctl/baseline-<os build>.json`, one file per OS build so an
update cannot silently reuse the previous driver's values. It records only catalogued runtime
properties whose value is identical across two reads a moment apart - a value that moves on its own
is a reading, not a setting, and writing a stale ambient-light sample back would be wrong. The file
is plain JSON in the same syntax `set` takes, so it can be hand-edited.

Everything here is runtime state, so a reboot is always the last resort.

Writing, with the guard:

```sh
pwmctl set enableHBLD=true HBLDDimmingFactorMin=0.25q16 --revert-after 30
```

`--revert-after N` puts the previous values back after N seconds, and immediately on `^C`, so a
knob that blacks out the panel recovers on its own. A key the node does not publish yet has no
previous value, so name one with `--revert-to KEY=VALUE`. Keys that drive a brightness register directly
(`DBVValue`, `BLMVLEDManual`, `digitalDimmingLevel`, ...) refuse to run without `--revert-after`
or `--force`.

Values: `true`/`false`, `42`, `0x2a`, `0.25q16` (16.16 fixed point, `65536` == 1.0), `s:text`.

## What is worth poking

[TESTING.md](TESTING.md) ranks the candidate keys with their current values and flags which predate
macOS 27. The seven dimming keys macOS 27 added are unpublished on this IPS panel, so they are
written up as a plan to run on a mini-LED or ProMotion Mac instead.

## Observed behaviour

On a MacBook Pro 13" M2 (T8112), macOS 27.0 (26A428):

- Writes do **not** need root: a normal user's write is applied.
- Unknown keys are rejected with `kIOReturnBadArgument`, so the driver does validate.
- A key is only accepted under the spelling it is published as. `digitalDimmingLevel` reads back
  as `IOMFBDigitalDimmingLevel` and is rejected under the short name; the tool resolves the
  spelling before writing and retries the alternate.
- `probe --write` on the internal panel: **81 of 82 published keys accepted**. The only refusal is
  `enableLinearToPanel`, with `kIOReturnUnsupported` rather than bad argument.
- Unpublished keys are rejected whatever type you send, and a wrong type on a published key gives
  the same error, so the settable set appears to equal the published set. Every key macOS 27 added
  is unpublished here.

## Keeping the catalog current

The key catalog is generated from the boot kernel collection, including the pre-update one that
survives in `/System/Volumes/Preboot` after an OS update - the only on-disk copy of the previous
display drivers.

```sh
just regen-catalog    # rewrites Sources/PWMKit/Catalog.swift and prints what changed
```

## Layout

```
Sources/PWMKit/      framebuffer discovery, value parsing, revert guard, generated catalog
Sources/pwmctl/      the CLI
tools/               kernelcache extraction, catalog generation, reference collection
reference/           per-machine display capabilities, one file per Mac
```

`reference/` records what each panel exposes, since the settable keys depend on the backlight
architecture: `just reference` writes a record for the machine you are on.

## License

Apache 2.0.
