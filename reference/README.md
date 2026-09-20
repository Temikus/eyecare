# Reference: per-machine display capabilities

What each Mac's display pipeline exposes, so the knobs in [../TESTING.md](../TESTING.md) can be
compared across panels. The keys a panel publishes - and therefore the keys that can be written -
differ by backlight architecture, not just by OS version.

| machine | panel | node | `isHiloDevice` | macOS 27 dimming keys | record |
|---|---|---|---|---|---|
| Mac14,7 (MacBook Pro 13" M2) | IPS, 60 Hz, Touch Bar chassis | `disp0` | no | none published | [mac14-7.md](mac14-7.md) |

## Adding a machine

```sh
just build
just reference              # read-only
just reference-probe        # also records which keys the driver accepts
```

That writes `reference/<hw.model>.md`; add a row to the table above. `--probe` rewrites every
published value unchanged, which is a no-op but still a write, so it is opt-in.

## What goes in a record

Framebuffer nodes, backlight hardware facts from the backlight device node (`pwm-frequency`,
`DBVMin`, which lookup tables exist), capability flags, the dimming properties with their values,
whether each macOS 27 dimming key is published, and the probe result. Free-text observations go
under Notes.

## Privacy

The generator collects no hostname, computer name or user name, and truncates the platform serial by
three characters. Panel identity comes from `ProductAttributes`, which carries a manufacturer and
product ID but no serial. Check a record before sharing it, and keep the same rules for any machine
added by hand.
