#!/usr/bin/env python3
"""Survey a tileset .set: what features it has and what layout they really are.

Reports every multi-tile feature's TRUE shape and tile->offset mapping, taken
from Rows/Columns and cross-checked against the tile model names — never from
the group's name, which is unreliable. In stock tcn01, SlumHouse_1x2 and
Market_2x1 are both Rows=1 Columns=2.

Usage:
    python3 set_analyze.py <tileset.set> [report]

    report = all (default) | general | shapes | groups | fill | integrity

To get a .set out of the game data or a hak first:
    nwn_resman_cat --root ~/nwn-data --userdirectory ~/nwn-data/user \\
        tcn01.set > /tmp/tcn01.set
    nwn_erf -x -f some.hak            # for a hak tileset

Companion: set_groups.py turns one group into ready-to-paste TileGroupAdd()
calls.
"""

import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setfile


def report_general(sections):
    general = sections.get("GENERAL", {})
    print("== Tileset ==")
    for key in ("Name", "DisplayName", "Type", "Version", "Interior",
                "HasHeightTransition", "Border", "Default", "Floor"):
        if key in general:
            print("  %-20s %s" % (key + ":", general[key]))

    terrains = setfile.type_names(sections, "TERRAIN TYPES", "TERRAIN")
    crossers = setfile.type_names(sections, "CROSSER TYPES", "CROSSER")
    print("  %-20s %s" % ("terrain types:", ", ".join(terrains) or "(none)"))
    print("  %-20s %s" % ("crosser types:", ", ".join(crossers) or "(none)"))
    print()


def report_integrity(sections):
    """Declared Count= vs sections actually present.

    A .set edited by hand or by a third-party tool can carry more [TILEn]
    sections than [TILES] Count claims. Tile IDs at or above Count are outside
    what the toolset advertises; treat them as suspect before shipping a
    hard-coded ID.
    """
    print("== Integrity ==")
    for header, prefix in (("TILES", "TILE"), ("GROUPS", "GROUP")):
        declared = setfile.declared_count(sections, header)
        present = setfile.numbered(sections, prefix)
        indexes = [index for index, _ in present]
        highest = max(indexes) if indexes else -1
        note = ""
        if declared is not None and declared != len(present):
            note = "  <-- MISMATCH: %d sections present" % len(present)
        print("  %-8s Count=%-6s sections=%-6d highest index=%-6d%s"
              % (header, declared, len(present), highest, note))
        if declared is not None and highest >= declared:
            print("           %d..%d are above the declared Count - verify before use"
                  % (declared, highest))
    print()


def report_shapes(sections):
    groups = setfile.groups(sections)
    shapes = collections.Counter()
    examples = {}
    for _, fields in sorted(groups.items()):
        shape = setfile.group_shape(fields)
        shapes[shape] += 1
        examples.setdefault(shape, fields.get("Name", ""))

    print("== Feature shapes (columns x rows) ==")
    single = multi_square = multi_oblong = 0
    for (columns, rows), count in sorted(shapes.items(), key=lambda kv: (-kv[1], kv[0])):
        tiles = columns * rows
        kind = "single tile" if tiles == 1 else ("square" if columns == rows else "non-square")
        print("  %2dx%-2d  count=%-4d %-12s e.g. %s"
              % (columns, rows, count, kind, examples[(columns, rows)]))
        if tiles == 1:
            single += count
        elif columns == rows:
            multi_square += count
        else:
            multi_oblong += count

    print("\n  %d groups: %d single-tile, %d multi-tile (%d square, %d non-square)"
          % (sum(shapes.values()), single, multi_square + multi_oblong,
             multi_square, multi_oblong))
    if multi_oblong > multi_square:
        print("  Non-square features OUTNUMBER square ones. TileBlockRotate is")
        print("  square-only; non-square features get TileBlockRotate180 only.")
    print()


def report_groups(sections, name_filter=""):
    """Every group's real layout, plus two independent cross-checks."""
    groups = setfile.groups(sections)
    models = {tile_id: fields.get("Model", "")
              for tile_id, fields in setfile.tiles(sections).items()}

    print("== Feature layouts ==")
    print("  'name shape' is the NxM suffix in the group's own name, shown only")
    print("  to flag where it contradicts reality. Trust 'actual'.\n")

    verdicts = collections.Counter()
    lying_names = []
    holed = []
    for group_id, fields in sorted(groups.items()):
        name = fields.get("Name", "")
        if name_filter and name_filter not in name.casefold():
            continue
        columns, rows = setfile.group_shape(fields)
        verdict, detail = setfile.check_group_layout(fields, models)
        verdicts[verdict] += 1
        holes = setfile.group_holes(fields)
        if holes:
            holed.append((name, columns, rows, holes))

        flag = ""
        suffix = name.rsplit("_", 1)[-1].casefold()
        if "x" in suffix:
            parts = suffix.split("x")
            if len(parts) == 2 and all(p.isdigit() for p in parts):
                claimed = (int(parts[0]), int(parts[1]))
                if claimed not in ((columns, rows), (rows, columns)):
                    flag = "  name shape %dx%d is WRONG either way" % claimed
                elif claimed != (columns, rows) and columns != rows:
                    flag = "  name says %dx%d (rows x columns)" % claimed
                    lying_names.append(name)

        tile_count = columns * rows - holes
        hole_note = "  %d HOLE(S)" % holes if holes else ""
        print("  GROUP%-3d %-34s actual %dx%d (%d tiles)  models:%-10s%s%s"
              % (group_id, name, columns, rows, tile_count, verdict, hole_note, flag))
        if verdict == "irregular":
            print("           ^ %s" % detail)

    print("\n  model cross-check: " + ", ".join(
        "%s=%d" % (key, verdicts[key])
        for key in ("confirmed", "irregular", "n/a") if verdicts[key]))
    print("  confirmed = tile model names independently form a consistent grid for")
    print("              the declared layout (both naming axes are tried).")
    print("  irregular = hand-assembled from non-adjacent tiles. Still usable; the")
    print("              declared Rows/Columns remains authoritative.")
    if holed:
        print("\n  %d feature(s) are NOT solid rectangles - the bounding box has holes" % len(holed))
        print("  (Tile=-1, meaning 'leave whatever is there'). Never stamp a -1:")
        for name, columns, rows, holes in holed:
            print("    %-30s %dx%d box, %d hole(s)" % (name, columns, rows, holes))
    if lying_names:
        print("\n  %d group name(s) state rows x columns, not columns x rows: %s"
              % (len(lying_names), ", ".join(lying_names)))
    print()


def report_fill(sections, limit=12):
    """Tiles safe to fill an area with, per terrain type."""
    general = sections.get("GENERAL", {})
    tiles = setfile.tiles(sections)
    terrains = setfile.type_names(sections, "TERRAIN TYPES", "TERRAIN")

    print("== Flat filler tiles ==")
    print("  Every corner the same terrain at the same height, no edge crosser -")
    print("  safe to tile an entire area with. Unequal corner heights mean a")
    print("  height transition, which will not tile against itself.\n")

    default = general.get("Default", "")
    for terrain in terrains:
        matches = [tile_id for tile_id, fields in sorted(tiles.items())
                   if setfile.is_flat_filler(fields, terrain)]
        mark = "  <-- [GENERAL] Default" if terrain.casefold() == default.casefold() else ""
        print("  %-12s %3d tile(s)%s" % (terrain + ":", len(matches), mark))
        if matches:
            shown = ", ".join("%d (%s)" % (t, tiles[t].get("Model", ""))
                              for t in matches[:limit])
            more = "" if len(matches) <= limit else ", ... +%d more" % (len(matches) - limit)
            print("               %s%s" % (shown, more))
    print()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    path = sys.argv[1]
    which = sys.argv[2].lower() if len(sys.argv) > 2 else "all"
    sections = setfile.load(path)

    if not setfile.tiles(sections):
        print("No [TILEn] sections in %s - is that a .set file?" % path, file=sys.stderr)
        return 1

    if which in ("all", "general"):
        report_general(sections)
    if which in ("all", "integrity"):
        report_integrity(sections)
    if which in ("all", "shapes"):
        report_shapes(sections)
    if which in ("all", "fill"):
        report_fill(sections)
    if which in ("all", "groups"):
        report_groups(sections, sys.argv[3].casefold() if len(sys.argv) > 3 else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
