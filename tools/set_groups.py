#!/usr/bin/env python3
"""Print a tileset .set's features as ready-to-paste inc_tile calls.

There is no way to read a .set from NWScript, so the tile IDs a TileGroup needs
have to be looked up at build time. This does the lookup and emits the
TileGroupAdd() lines, handling the two traps described below.

Usage:
    python3 set_groups.py <tileset.set> [name-substring]

To get the .set out of the game data or a hak first:
    nwn_resman_cat --root ~/nwn-data --userdirectory ~/nwn-data/user \\
        tcn01.set > /tmp/tcn01.set
    nwn_erf -x -f some.hak            # for a hak tileset

  * A .set GROUP lists its tiles row-major starting from the NORTH row, while
    inc_tile groups use offsets from the SOUTH-WEST tile with +y north. So
    Tile[row * columns + column] becomes offset (column, rows - 1 - row).
    Verified against tcn01: CloakTower_2x2's Tile0 is 282 = tcn01_u02_01, the
    north-west quadrant.

  * A Tile value of -1 is a HOLE - a square of the bounding box that is not part
    of the feature. It is not a tile ID and is skipped, never stamped. Stock
    tcn01's Merchant_Docked and Weathered_Docked are both 2x3 boxes with a hole.

Do not trust a group's Name for its shape: stock tcn01 has SlumHouse_1x2 and
Market_2x1 both at Rows=1 Columns=2. Use set_analyze.py for a full survey of a
tileset's real layouts.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setfile


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    path = sys.argv[1]
    name_filter = sys.argv[2].casefold() if len(sys.argv) > 2 else ""

    sections = setfile.load(path)
    models = {tile_id: fields.get("Model", "")
              for tile_id, fields in setfile.tiles(sections).items()}

    shown = 0
    for group_id, fields in sorted(setfile.groups(sections).items()):
        name = fields.get("Name", "")
        if name_filter and name_filter not in name.casefold():
            continue

        columns, rows = setfile.group_shape(fields)
        if not columns or not rows:
            continue
        holes = setfile.group_holes(fields)

        shown += 1
        print("// GROUP%d %s  %dx%d (columns x rows)" % (group_id, name, columns, rows))
        if holes:
            print("// Not a solid rectangle: %d square(s) of the %dx%d box are holes,"
                  % (holes, columns, rows))
            print("// skipped below so the tiles under them are left alone.")
        print("json jGroup = TileGroup();")

        # South row first, so the listing reads bottom-up the way offsets do.
        for _index, tile_id, dx, dy in sorted(
                setfile.group_offsets(fields), key=lambda item: (item[3], item[2])):
            call = "jGroup = TileGroupAdd(jGroup, %d, %d, %d, 0);" % (dx, dy, tile_id)
            print("%-52s// %s" % (call, models.get(tile_id, "")))
        print()

    if not shown:
        print("No groups matched in %s." % path, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
