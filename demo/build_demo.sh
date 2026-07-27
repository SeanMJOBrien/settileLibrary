#!/usr/bin/env bash
# Build the SetTile library demo module.
#
#   1. Generate the module/area/instances GFF-JSON with make_demo.py
#   2. Compile every .nss in ../nss (the library, the builder demo, the mason)
#   3. Convert all GFF-JSON sources to binary GFF
#   4. Pack everything into demo/SetTileDemo.mod
#
# Usage: bash demo/build_demo.sh [-o output.mod]
#
# Tool locations can be overridden with NWNSC, NWN_GFF and BASE_SCRIPTS.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

NWNSC="${NWNSC:-$REPO/../nwn-tools/linux/nwnsc/nwnsc}"
NWN_GFF="${NWN_GFF:-$REPO/../nwn-tools/linux/neverwinter/nwn_gff}"
NWN_ERF="${NWN_ERF:-$REPO/../nwn-tools/linux/neverwinter/nwn_erf}"
BASE_SCRIPTS="${BASE_SCRIPTS:-$REPO/../gve3/nwn-base-scripts}"

OUT_MOD="$HERE/SetTileDemo.mod"
[ "${1:-}" = "-o" ] && { OUT_MOD="$2"; shift 2; }

BUILD="$HERE/build"

for tool in "$NWNSC" "$NWN_GFF" "$NWN_ERF"; do
    [ -x "$tool" ] || { echo "ERROR: missing or not executable: $tool" >&2; exit 1; }
done
[ -d "$BASE_SCRIPTS" ] || { echo "ERROR: missing base scripts: $BASE_SCRIPTS" >&2; exit 1; }

rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$BUILD/mod"

# --- 1. Generate module sources ---------------------------------------------
echo "Generating sources:"
python3 "$HERE/make_demo.py" "$BUILD/src"

# --- 2. Compile scripts ------------------------------------------------------
# nwnsc appends the input path to -b, so compile from inside each source dir.
echo "Compiling scripts:"
( cd "$REPO/nss" && "$NWNSC" -i . -i example_mason -i "$BASE_SCRIPTS" \
      -b "$BUILD/mod" tile_demo.nss > /dev/null )
( cd "$REPO/nss/example_mason" && "$NWNSC" -i . -i .. -i "$BASE_SCRIPTS" \
      -b "$BUILD/mod" mason_*.nss > /dev/null )

ncs_count=$(find "$BUILD/mod" -name '*.ncs' | wc -l)
[ "$ncs_count" -ge 11 ] || { echo "ERROR: expected >=11 .ncs, got $ncs_count" >&2; exit 1; }
echo "  $ncs_count scripts compiled"

# Ship the sources too, so the module is readable in the toolset.
cp "$REPO"/nss/*.nss "$REPO"/nss/example_mason/*.nss "$BUILD/mod/"

# --- 3. GFF-JSON -> GFF ------------------------------------------------------
echo "Converting resources:"
convert() {   # convert <src.json> <dest-name>
    "$NWN_GFF" -i "$1" -o "$BUILD/mod/$2" -k gff
    echo "  $2"
}
convert "$BUILD/src/module.ifo.json"   "module.ifo"
convert "$BUILD/src/tiletest.are.json" "tiletest.are"
convert "$BUILD/src/tiletest.git.json" "tiletest.git"
convert "$REPO/dlg/mason.dlg.json"     "mason.dlg"
convert "$REPO/utc/mason.utc.json"     "mason.utc"

# --- 4. Pack -----------------------------------------------------------------
rm -f "$OUT_MOD"
( cd "$BUILD/mod" && "$NWN_ERF" -c -f "$OUT_MOD" . )

echo
echo "Built: $OUT_MOD"
ls -la "$OUT_MOD"
echo
echo "Install: copy it to your NWN user directory's modules/ folder, e.g."
echo "  cp '$OUT_MOD' ~/.local/share/Neverwinter\\ Nights/modules/"
