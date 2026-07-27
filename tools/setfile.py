"""Shared parsing for NWN tileset .set files.

A .set is an ini-style catalog of a tileset. The sections that matter:

    [GENERAL]        Name, Interior, Default / Floor / Border terrain names
    [TERRAIN TYPES]  Count, then [TERRAIN0..n] Name=
    [CROSSER TYPES]  Count, then [CROSSER0..n] Name=
    [TILES]          Count, then [TILE0..n]
    [GROUPS]         Count, then [GROUP0..n]

A [TILEn] section's n IS the tile ID that NWScript's SetTile takes. Its corner
terrain (TopLeft/TopRight/BottomLeft/BottomRight), corner heights and edge
crossers (Top/Right/Bottom/Left) are what decide whether two tiles can sit next
to each other without a visible seam.

A [GROUPn] is a multi-tile feature: Rows, Columns, and Tile0..Tile(Rows*Columns-1)
listed row-major starting from the NORTH row.

Do not trust a group's Name for its shape. In stock tcn01, SlumHouse_1x2 and
Market_2x1 are both Rows=1 Columns=2 - the suffix convention is inconsistent
even within one file. Read Rows/Columns.
"""

import re

# Tile model names follow <set>_<column-letters><row-number>_<variant>, e.g.
# tcn01_u02_01. The letter part varies with the column of a multi-tile feature
# and the number with the row, counting up towards the NORTH. That gives an
# independent check on a group's declared layout.
MODEL_RE = re.compile(r"^(?P<set>[a-z0-9]+)_(?P<col>[a-z]+)(?P<row>\d+)_(?P<variant>\d+)$",
                      re.IGNORECASE)

CORNERS = ("TopLeft", "TopRight", "BottomLeft", "BottomRight")
EDGES = ("Top", "Right", "Bottom", "Left")

# A group Tile value of -1 marks a square of the bounding box that is NOT part
# of the feature. It is not a tile ID and must never be stamped.
HOLE = -1


def parse_sections(text):
    """Return {section_name: {key: value}} preserving file order."""
    sections = {}
    current = None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
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


def load(path):
    with open(path, errors="replace") as handle:
        return parse_sections(handle.read())


def numbered(sections, prefix):
    """Yield (index, fields) for [PREFIX<n>] sections, in index order."""
    out = []
    for name, fields in sections.items():
        if not name.startswith(prefix):
            continue
        suffix = name[len(prefix):]
        if suffix.isdigit():
            out.append((int(suffix), fields))
    return sorted(out)


def declared_count(sections, name):
    """The Count= a [TILES]/[GROUPS]-style header claims, or None."""
    try:
        return int(sections[name]["Count"])
    except (KeyError, ValueError):
        return None


def tiles(sections):
    return dict(numbered(sections, "TILE"))


def groups(sections):
    return dict(numbered(sections, "GROUP"))


def type_names(sections, header, prefix):
    """Terrain or crosser type names, in index order."""
    return [fields.get("Name", "") for _, fields in numbered(sections, prefix)]


def group_shape(fields):
    """(columns, rows) as actually declared. Returns (0, 0) if absent."""
    try:
        return int(fields.get("Columns", 0)), int(fields.get("Rows", 0))
    except ValueError:
        return 0, 0


def group_offsets(fields, include_holes=False):
    """Map a group's tiles to library offsets.

    Yields (tile_index, tile_id, dx, dy). The .set lists tiles row-major from
    the NORTH, while TileGroupAdd() offsets are from the SOUTH-WEST with +y
    north, so the row is flipped: dy = rows - 1 - row.

    A feature's bounding box is not always solid: a Tile value of HOLE (-1)
    means "this square is not part of the feature, leave whatever is there".
    Stock tcn01's Merchant_Docked and Weathered_Docked are both 2x3 boxes with
    one hole. Holes are skipped unless include_holes is set - never stamp one,
    -1 is not a tile ID.
    """
    columns, rows = group_shape(fields)
    for row in range(rows):
        for column in range(columns):
            index = row * columns + column
            raw = fields.get("Tile%d" % index)
            if raw is None:
                continue
            tile_id = int(raw)
            if tile_id == HOLE and not include_holes:
                continue
            yield index, tile_id, column, rows - 1 - row


def group_holes(fields):
    """How many squares of a feature's bounding box are holes."""
    columns, rows = group_shape(fields)
    count = 0
    for index in range(columns * rows):
        raw = fields.get("Tile%d" % index)
        if raw is None or int(raw) == HOLE:
            count += 1
    return count


def parse_model(model):
    """Split a tile model name into its parts, or None if it doesn't conform."""
    match = MODEL_RE.match(model or "")
    if not match:
        return None
    return match.group("set"), match.group("col").lower(), int(match.group("row"))


def check_group_layout(fields, tile_models):
    """Cross-check a group's declared layout against its tile model names.

    Independent of both Rows/Columns arithmetic and the group's Name. Tile models
    are named <set>_<letters><number>_<variant>; in a rectangular feature one of
    those two parts varies with the column and the other with the row, so if the
    declared layout is right, each part is constant along its own axis.

    Which part maps to which axis is NOT universal - it varies by model set.
    Stock tcn01 features use letters for columns and numbers for rows
    (CloakTower: u01 south-west, u02 north-west), while the Ampitheater's amp01
    models do the opposite (a01..a08 across one row). Both assignments are tried
    and the one that fits is reported, so a different convention is not mistaken
    for broken data.

    Returns (verdict, detail):
        "confirmed" - the models form a consistent grid for the declared layout
        "irregular" - models parse but form no consistent grid, so the feature
                      was hand-assembled from non-adjacent tiles (legal, and
                      stock tcn01 has one: StateBuilding02 borrows y08)
        "n/a"       - models are off-convention, nothing to check against
    """
    columns, rows = group_shape(fields)
    if columns < 1 or rows < 1:
        return "n/a", "no Rows/Columns"

    grid = {}
    for _index, tile_id, dx, dy in group_offsets(fields):
        parsed = parse_model(tile_models.get(tile_id, ""))
        if parsed is None:
            return "n/a", "model %r off-convention" % tile_models.get(tile_id, "")
        grid[(dx, dy)] = parsed
    if not grid:
        return "n/a", "no parseable tiles"

    # (label, column key, row key). Holes simply leave gaps in the grid.
    for label, column_key, row_key in (
            ("letters=columns", lambda p: p[1], lambda p: p[2]),
            ("letters=rows", lambda p: p[2], lambda p: p[1])):

        consistent = True
        for dx in range(columns):
            keys = {column_key(p) for (x, _y), p in grid.items() if x == dx}
            if len(keys) > 1:
                consistent = False
                break
        if not consistent:
            continue

        row_keys = {}
        for dy in range(rows):
            keys = {row_key(p) for (_x, y), p in grid.items() if y == dy}
            if len(keys) > 1:
                consistent = False
                break
            if keys:
                row_keys[dy] = keys.pop()
        if not consistent:
            continue

        # Report which way the row key runs, rather than assuming. tcn01 numbers
        # ascend north; amp01 letters ascend south.
        ordered = [row_keys[dy] for dy in sorted(row_keys)]
        if len(ordered) < 2:
            direction = "single row"
        elif ordered == sorted(ordered):
            direction = "ascends north (%s)" % "->".join(str(k) for k in ordered)
        elif ordered == sorted(ordered, reverse=True):
            direction = "ascends south (%s)" % "->".join(str(k) for k in ordered)
        else:
            direction = "non-monotonic (%s)" % "->".join(str(k) for k in ordered)
        return "confirmed", "%s, row key %s" % (label, direction)

    detail = []
    for dx in range(columns):
        letters = sorted({p[1] for (x, _y), p in grid.items() if x == dx})
        numbers = sorted({p[2] for (x, _y), p in grid.items() if x == dx})
        if len(letters) > 1 and len(numbers) > 1:
            detail.append("column %d spans letters %s and numbers %s" % (dx, letters, numbers))
    return "irregular", "; ".join(detail) or "no consistent row/column grid"


def is_flat_filler(fields, terrain):
    """True if a tile is plain, flat, crosser-free ground of the given terrain.

    These are the tiles it is safe to fill a whole area with: every corner the
    same terrain at the same height, and no wall/road crosser on any edge. A
    tile with unequal corner heights is a height transition and will not tile
    cleanly against itself (stock tcn01's TILE0 is exactly that trap).
    """
    want = (terrain or "").casefold()
    if not want:
        return False
    if any((fields.get(corner, "").casefold() != want) for corner in CORNERS):
        return False
    heights = {fields.get(corner + "Height", "0") for corner in CORNERS}
    if len(heights) != 1:
        return False
    return not any(fields.get(edge, "") for edge in EDGES)
