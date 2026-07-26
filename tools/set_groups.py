#!/usr/bin/env python3
"""List the tile groups in a tileset .set file as inc_tile calls.

There is no way to read a .set from NWScript, so the tile IDs a TileGroup needs
have to be looked up by hand. This does the lookup and prints ready-to-paste
TileGroupAdd() lines, including the row flip described below.

Usage:
    python3 set_groups.py <tileset.set> [name-substring]

To get the .set out of the game data or a hak first:
    ../nwn-tools/linux/neverwinter/nwn_resman_cat \\
        --root ~/nwn-data --userdirectory ~/nwn-data/user tcn01.set > tcn01.set
    ../nwn-tools/linux/neverwinter/nwn_erf -x -f some.hak   # for hak tilesets

A .set GROUP lists its tiles row-major starting from the NORTH row, while
inc_tile groups use offsets from the SOUTH-WEST tile with +y north. So
Tile[row * columns + column] becomes offset (column, rows - 1 - row) - which is
the flip this script applies. Verified against tcn01: CloakTower_2x2's Tile0 is
282 = tcn01_u02_01, the north-west quadrant.
"""

import re
import sys


def parse_sections(text):
    """Return {section_name: {key: value}} for an ini-style .set file."""
    sections = {}
    current = None
    for line in text.splitlines():
        line = line.strip()
        header = re.match(r"^\[(.+)\]$", line)
        if header:
            current = header.group(1)
            sections[current] = {}
            continue
        if current is None or "=" not in line:
            continue
        key, _, value = line.partition("=")
        sections[current][key.strip()] = value.strip()
    return sections


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    path = sys.argv[1]
    name_filter = sys.argv[2].lower() if len(sys.argv) > 2 else ""

    with open(path, errors="replace") as handle:
        sections = parse_sections(handle.read())

    models = {
        int(name[4:]): fields.get("Model", "")
        for name, fields in sections.items()
        if name.startswith("TILE") and name[4:].isdigit()
    }

    shown = 0
    for name, fields in sections.items():
        if not name.startswith("GROUP"):
            continue
        group_name = fields.get("Name", "")
        if name_filter and name_filter not in group_name.lower():
            continue

        rows = int(fields.get("Rows", 0))
        columns = int(fields.get("Columns", 0))
        if not rows or not columns:
            continue

        shown += 1
        print(f"// {name} {group_name}  {columns}x{rows}")
        print("json jGroup = TileGroup();")
        for row in range(rows):
            for column in range(columns):
                tile = fields.get(f"Tile{row * columns + column}")
                if tile is None:
                    continue
                offset_y = rows - 1 - row
                model = models.get(int(tile), "")
                print(f"jGroup = TileGroupAdd(jGroup, {column}, {offset_y}, "
                      f"{tile}, 0);".ljust(52) + f"// {model}")
        print()

    if not shown:
        print(f"No groups matched in {path}.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
