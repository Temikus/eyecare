# pwmctl - IOMFB framebuffer property CLI

# Builds land outside the project: iCloud Drive adds extended attributes that break codesigning.
scratch := env_var_or_default("PWMCTL_BUILD_DIR", env_var("HOME") + "/Library/Caches/pwm-explore/build")
binary := scratch + "/debug/pwmctl"

default:
    @just --list

build:
    swift build --scratch-path "{{ scratch }}"
    @echo "binary: {{ binary }}"

build-release:
    swift build -c release --scratch-path "{{ scratch }}"
    @echo "binary: {{ scratch }}/release/pwmctl"

# Run the test suite.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    # swift-testing's macro plugin sits in a subdirectory SwiftPM does not scan when only the
    # Command Line Tools are selected, so point at it explicitly in that case.
    flags=()
    plugin=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
    if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -f "$plugin" ]; then
        flags=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
    fi
    # Expansion form keeps an empty array valid under `set -u` on macOS's bash 3.2.
    swift test --scratch-path "{{ scratch }}" ${flags[@]+"${flags[@]}"}

lint:
    swift format lint --strict --recursive Sources Tests
    python3 -m py_compile tools/extract-props.py
    bash -n tools/extract-kernelcache.sh
    bash -n tools/collect-reference.sh

check: lint test

fmt:
    swift format --in-place --recursive Sources Tests

run *ARGS: build
    @"{{ binary }}" {{ ARGS }}

install: build-release
    mkdir -p ~/.local/bin
    cp "{{ scratch }}/release/pwmctl" ~/.local/bin/pwmctl
    @echo "installed ~/.local/bin/pwmctl"

# Current state of the internal panel's dimming knobs.
dimming: build
    @"{{ binary }}" get | sed -n '/\[dimming\]/,/^$/p'

# Which catalogued keys the driver accepts, by rewriting each published value unchanged.
probe: build
    @"{{ binary }}" probe --write

# Record the current values as the known-good state to fall back on.
baseline: build
    @"{{ binary }}" baseline save

# What has drifted from the saved baseline.
drift: build
    @"{{ binary }}" baseline diff

# Put the saved baseline back: the way out when a knob leaves something stuck.
restore: build
    @"{{ binary }}" baseline restore

# Record this machine's display capabilities as reference/<hw.model>.md.
reference: build
    PWMCTL="{{ binary }}" tools/collect-reference.sh

# Same, plus which keys the driver accepts (rewrites published values unchanged).
reference-probe: build
    PWMCTL="{{ binary }}" tools/collect-reference.sh --probe

# Raw dump of every published value, for diffing across macOS updates.
snapshot FILE="snapshots/snapshot.json": build
    mkdir -p "$(dirname "{{ FILE }}")"
    @"{{ binary }}" snapshot --out "{{ FILE }}"

# Rebuild the key catalog from the boot kernel collections, including the pre-update one.
regen-catalog:
    #!/usr/bin/env bash
    set -euo pipefail
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    tools/extract-kernelcache.sh --preboot "$work"
    args=(--current "$work/kc-current.bin")
    if [ -f "$work/kc-baseline.bin" ]; then args+=(--baseline "$work/kc-baseline.bin"); fi
    python3 tools/extract-props.py "${args[@]}"
    swift format --in-place Sources/PWMKit/Catalog.swift

clean:
    rm -rf "{{ scratch }}"
