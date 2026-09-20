#!/usr/bin/env bash
# Record a Mac's display and backlight capabilities as reference/<model>.md.
#
# Privacy: no hostname, user or computer name is collected, and the platform serial is truncated by
# three characters. Panel identity comes from ProductAttributes, which carries no serial.
set -euo pipefail

PWMCTL=${PWMCTL:-$(command -v pwmctl || echo "$HOME/Library/Caches/pwm-explore/build/debug/pwmctl")}
[ -x "$PWMCTL" ] || { echo "pwmctl not found; run 'just build' or set PWMCTL" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

probe=false
[ "${1:-}" = "--probe" ] && probe=true

model=$(sysctl -n hw.model)
soc=$(sysctl -n machdep.cpu.brand_string)
name=$(system_profiler SPHardwareDataType -json 2>/dev/null \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["SPHardwareDataType"][0].get("machine_name",""))' \
    || echo "")
serial=$(ioreg -l -w0 -c IOPlatformExpertDevice \
    | sed -n 's/.*"IOPlatformSerialNumber" = "\([^"]*\)".*/\1/p' | head -1)
serial="${serial%???}***"
os="$(sw_vers -productVersion) ($(sw_vers -buildVersion)), Darwin $(uname -r)"
slug=$(echo "$model" | tr 'A-Z,' 'a-z-')
out="reference/$slug.md"

# Machine-wide backlight facts live on the backlight device node, not on AppleCLCD2.
backlight_scalar() {
    ioreg -l -w0 | sed -n "s/.*\"$1\" = \\([^,]*\\).*/\\1/p" | head -1
}
backlight_present() {
    # No grep -q here: it closes the pipe early and pipefail then reports ioreg's SIGPIPE.
    local hits
    hits=$(ioreg -l -w0 | grep -c "\"$1\" = <" || true)
    [ "$hits" -gt 0 ] && echo "present" || echo "absent"
}
le32() {  # little-endian 4-byte ioreg data value, e.g. <0f000000> -> 15
    local raw=$1
    raw=${raw#<}
    raw=${raw%>}
    [ -n "$raw" ] || { echo "-"; return; }
    python3 -c "import sys;d=bytes.fromhex(sys.argv[1]);print(int.from_bytes(d[:4],'little'))" "$raw"
}

internal=$("$PWMCTL" displays --json | python3 -c "
import json,sys
nodes=json.load(sys.stdin)
print(next((n['name'] for n in nodes if n['name']=='disp0'), nodes[0]['name']))")

{
    echo "# $model"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Machine | ${name:-unknown} |"
    echo "| SoC | $soc |"
    echo "| Serial | \`$serial\` (last 3 characters withheld) |"
    echo "| OS when recorded | $os |"
    echo "| Internal panel node | \`$internal\` |"
    echo "| Recorded | $(date -u +%Y-%m-%d) |"
    echo
    echo "## Framebuffer nodes"
    echo
    echo '```'
    "$PWMCTL" displays
    echo '```'
    echo
    echo "## Panel and backlight hardware"
    echo
    echo "From the backlight device node via \`ioreg\`, not from \`AppleCLCD2\`."
    echo
    echo "| key | value |"
    echo "|---|---|"
    echo "| \`pwm-frequency\` | $(backlight_scalar pwm-frequency) |"
    echo "| \`FPWM Frequency\` | $(backlight_scalar 'FPWM Frequency') |"
    echo "| \`DBVMin\` | $(le32 "$(backlight_scalar DBVMin)") |"
    echo "| \`backlight-level-encoding\` | $(le32 "$(backlight_scalar backlight-level-encoding)") bits |"
    echo "| \`new-backlight-architecture\` | $(backlight_scalar new-backlight-architecture) |"
    echo "| \`DBV2NitsTable\` | $(backlight_present DBV2NitsTable) |"
    echo "| \`nits-to-pwm-percentage\` | $(backlight_present nits-to-pwm-percentage-part1) |"
    echo "| \`backlight-marketing-table\` | $(backlight_present backlight-marketing-table) |"
    echo
    echo "Panel identity: $(ioreg -l -w0 -r -c AppleCLCD2 \
        | sed -n 's/.*"ProductAttributes"={\([^}]*\)}.*/\1/p' | head -1)"
    echo
    echo "## Capability flags"
    echo
    echo "| key | value |"
    echo "|---|---|"
    "$PWMCTL" get --display "$internal" --all-keys --json | python3 -c "
import json, sys
values = {v['key']: v['value'] for v in json.load(sys.stdin)}
for key in ['IOMFBIsHiloDevice', 'IOMFBSupportsLFC', 'IOMFBSupportsGPLite', 'IOMFBSupportsICC',
            'ALSSSupported', 'SPLCSupported', 'IOMFBSwapAppleLookSupported',
            'IOMFBBrightnessCompensationEnable', 'IOMFBTemperatureCompensationEnable']:
    print(f'| \`{key}\` | {values.get(key, \"not published\")} |')"
    echo
    echo "## Dimming and backlight properties"
    echo
    echo "| key | value | risk |"
    echo "|---|---|---|"
    "$PWMCTL" get --display "$internal" --json | python3 -c "
import json, sys
for v in sorted(json.load(sys.stdin), key=lambda v: v['key'].lower()):
    if v['category'] != 'dimming':
        continue
    value = v['value']
    if v['fixedPointValue'] is not None:
        value += f\" ({v['fixedPointValue']:.4f} q16)\"
    print(f\"| \`{v['key']}\` | {value} | {v['risk']} |\")"
    echo
    echo "## macOS 27 dimming additions"
    echo
    "$PWMCTL" keys --new-in 27 --category dimming --json > "$tmp/new27.json"
    "$PWMCTL" get --display "$internal" --all-keys --json | python3 -c "
import json, sys
live = {v['key'] for v in json.load(sys.stdin)}
new = json.load(open('$tmp/new27.json'))
print('| key | published here |')
print('|---|---|')
for entry in sorted(new, key=lambda e: e['key'].lower()):
    key = entry['key']
    prefixed = 'IOMFB' + key[0].upper() + key[1:]
    found = key in live or prefixed in live
    print(f\"| \`{key}\` | {'yes' if found else 'no'} |\")"
    echo
    echo "## Accepted writes"
    echo
    if $probe; then
        "$PWMCTL" probe --display "$internal" --write --json > "$tmp/probe.json"
        python3 -c "
import json
results = json.load(open('$tmp/probe.json'))
accepted = [r for r in results if r['status'] == 'accepted']
rejected = [r for r in results if r['status'] != 'accepted']
print(f'\`probe --write\`: {len(accepted)} accepted, {len(rejected)} rejected '
      f'of {len(results)} published catalogued keys.')
if rejected:
    print()
    print('Rejected:')
    print()
    for r in rejected:
        print(f\"- \`{r['key']}\` - {r['detail'] or 'no detail'}\")"
    else
        echo "Not recorded. Run \`tools/collect-reference.sh --probe\` to rewrite each published"
        echo "value unchanged and record which keys the driver accepts."
    fi
    echo
    echo "## Notes"
    echo
    echo "-"
} > "$out"

echo "wrote $out"
