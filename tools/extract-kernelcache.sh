#!/usr/bin/env bash
# Decompress an Apple Silicon boot kernel collection (IMG4/IM4P, lzfse) to a raw Mach-O fileset.
#
# With no argument, locates both caches under /System/Volumes/Preboot: after an OS update the
# previous version's cache survives next to the active one, which is the only on-disk source of
# the pre-update display drivers (kexts in /System/Library/Extensions are plist-only stubs).
set -euo pipefail

usage() { echo "usage: $0 [<kernelcache> <output>] | --preboot <outdir>" >&2; exit 2; }

decode() {
  local src=$1 dst=$2 off
  off=$(python3 - "$src" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(1 << 20)
i = d.find(b'bvx2')
if i < 0:
    sys.exit("no lzfse (bvx2) payload found; is this an IMG4 kernelcache?")
print(i)
PY
)
  tail -c "+$((off + 1))" "$src" > "$dst.lzfse"
  compression_tool -decode -i "$dst.lzfse" -o "$dst" -a lzfse > /dev/null
  rm -f "$dst.lzfse"
  local version
  version=$(strings -a "$dst" | grep -F 'Darwin Kernel Version' | head -1 || true)
  echo "$dst: ${version:-unknown version}"
}

case "${1:-}" in
  --preboot)
    [ $# -eq 2 ] || usage
    outdir=$2; mkdir -p "$outdir"
    active=$(cat /System/Volumes/Preboot/*/boot/active)
    n=0
    for kc in /System/Volumes/Preboot/*/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache; do
      # .../boot/<hash>/System/Library/Caches/com.apple.kernelcaches/kernelcache
      hash=${kc#*/boot/}
      hash=${hash%%/*}
      if [ "$hash" = "$active" ]; then tag=current; else tag=baseline; fi
      decode "$kc" "$outdir/kc-$tag.bin"
      n=$((n + 1))
    done
    [ "$n" -gt 0 ] || { echo "no kernelcaches found under /System/Volumes/Preboot" >&2; exit 1; }
    ;;
  ''|-h|--help) usage ;;
  *)
    [ $# -eq 2 ] || usage
    decode "$1" "$2"
    ;;
esac
