# Runtime tile editing — reference

NWN:EE can change an area's terrain tiles while players are standing in it. This is
the full reference for `inc_tile.nss` and the mason example. For installation and a
file list, see [README.md](README.md).

## Contents

- [The one rule: a tile location is a grid reference](#the-one-rule-a-tile-location-is-a-grid-reference)
- [The library](#the-library)
- [For a builder](#for-a-builder)
- [For a player: the Master Mason example](#for-a-player-the-master-mason-example)
- [What does not survive a reset](#what-does-not-survive-a-reset)
- [How this was verified](#how-this-was-verified)

## The one rule: a tile location is a grid reference

The `location` taken by `SetTile`, `GetTileID`, `GetTileOrientation` and
`GetTileHeight` is **not a world position**. Only its area, `x` and `y` are read,
and those are the tile *index*:

- `x` runs `0 .. GetAreaSize(AREA_WIDTH, oArea) - 1`
- `y` runs `0 .. GetAreaSize(AREA_HEIGHT, oArea) - 1`, with `y = 0` along the south edge
- `z` and facing are ignored

Passing a real world position — `GetLocation(oPC)` straight through, or
`tile * 10.0` — addresses a tile ten times too far out, so the edit either lands
somewhere unintended or silently does nothing. This is the single most common way
to get tile scripting wrong, and the engine's own header is inconsistent about it:
`SetTileMainLightColor` spells out *"the vector part of this is the tile grid (x,y)
coordinate"*, while `SetTile` only says *"the location of the tile"*. Both are grid
references.

Build these locations only with `TileLocation()`, and convert the other way with
`TileXFromPosition()` / `TileYFromPosition()`. `TileWorldCenter()` exists for the
opposite need — a genuine world position, e.g. to jump a creature onto a tile.

Two related conventions:

- **`SetTileJson` indexes tiles** as `y * width + x`, row-major from the
  south-west corner. A 3x3 area is `0,1,2` along the south row and `6,7,8` along
  the north.
- **Orientation is `0-3`**, counting 90° steps counter-clockwise. This library
  uses the same units for rotation, so a rotation amount and a tile orientation
  are interchangeable.

## The library

### Grid and bounds

`TileGridWidth` / `TileGridHeight` report the area size in tiles.
`TileInBounds` is the guard every read and write funnels through, so an
out-of-range coordinate returns a failure instead of reaching the engine.
`TileIsOnEdge` tells you whether an edit needs `SETTILE_FLAG_RELOAD_BORDER`.

### Reading and writing one tile

`GetTileIDAt` / `GetTileOrientationAt` / `GetTileHeightAt` return `TILE_INVALID`
(`-1`, matching the engine) out of bounds. `SetTileAt` changes one tile and
returns `FALSE` without writing if the target is off the map.

### Batches

For anything beyond a tile or two, build a batch and apply it once:

```nwscript
json jBatch = TileBatch();
jBatch = TileBatchAdd(jBatch, oArea, 4, 7, 277, 0);
jBatch = TileBatchAdd(jBatch, oArea, 5, 7, 283, 0);
TileBatchApply(oArea, jBatch, SETTILE_FLAG_RECOMPUTE_LIGHTING);
```

A batch is a JSON array in `SetTileJson`'s own format, so the whole edit is one
engine call and one update to the clients in the area. It also removes a hazard:
because the batch is built completely before anything is written, reads taken
while building it cannot be disturbed by the batch's own writes. This is why the
rotation functions are safe without a temporary copy.

Always assign the result — `jBatch = TileBatchAdd(jBatch, ...)` — because the
`Json*Inplace` helpers mutate a copy when a value is passed into a function.

### Groups

A group describes a structure once, in its own frame, as offsets from an origin
tile (`+y` is north), so it can be stamped anywhere:

```nwscript
json jTower = TileGroup();
jTower = TileGroupAdd(jTower, 0, 0, 277, 0);   // south-west
jTower = TileGroupAdd(jTower, 1, 0, 283, 0);   // south-east
jTower = TileGroupAdd(jTower, 0, 1, 282, 0);   // north-west
jTower = TileGroupAdd(jTower, 1, 1, 284, 0);   // north-east

TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, jTower, nFlags);
```

`TileGroupStamp` is **all-or-nothing**: if any tile would fall outside the area it
writes nothing and returns `FALSE`, so a structure never ends up half-stamped
across the map edge. `TileGroupFits` runs the same check without writing, which is
what the dialog conditionals use to decide whether to offer the option at all.
`TileGroupStampAtLocation` derives the origin tile and rotation from a location's
position and facing.

Note that group offsets rotate **about the origin tile**, not the group's centre,
so stamping a 2x2 group at 90° shifts its footprint one tile west. That is the
documented contract, and it is why the mason swaps groups rather than re-stamping
a rotated one.

### Snapshot and undo

`TileSnapshotRect` captures a rectangle and `TileSnapshotGroup` captures exactly
the tiles a group is about to cover. Both return a batch, so restoring is just
`TileBatchApply` — there is no separate restore call:

```nwscript
json jBefore = TileSnapshotGroup(oArea, nX, nY, TILE_ROTATE_NONE, jTower);
// ... stamp, later ...
TileBatchApply(oArea, jBefore, nFlags);
```

Because a batch is plain JSON, `JsonDump` turns it into a string you can park on
an object or push into a database, and `JsonParse` brings it back.

### Rotation, and when it does not apply

`TileBlockRotate` turns a **square** block of tiles in place, rotating both each
tile's position and its own orientation. Square only: rotating a `W x H` block 90°
produces an `H x W` block, which cannot be written back over the original
footprint. `TileBlockRotate180` handles rectangles, because 180° preserves shape.

**This is a terrain tool, not a way to reface a building.** The four tiles of a
tileset tower are four *different* models, one per quadrant — tcn01's
`CloakTower_2x2` is `u01`/`u02`/`v01`/`v02`. Rotating a tile only spins that
quadrant's own model, so rearranging the four and bumping their orientations
scrambles the tower instead of turning it. Rotation is correct for tiles whose
orientation is meaningful on its own: terrain crossers, roads, single-tile
features. To reface an authored structure you need a differently-authored group,
which is what the mason's ruin/rebuild options do.

## For a builder

### Finding tile IDs

Tile IDs are indexes into the tileset's `.set` file and mean nothing outside it —
ID 277 is a tower quadrant in tcn01 and something unrelated in any other tileset.
There is no way to read a `.set` from NWScript, so the lookup is a build-time job.

Extract the `.set`, then let `tools/set_groups.py` do the mapping:

```sh
nwn_resman_cat --root ~/nwn-data --userdirectory ~/nwn-data/user \
    tcn01.set > /tmp/tcn01.set
python3 tools/set_groups.py /tmp/tcn01.set tower
```

which prints, ready to paste:

```nwscript
// GROUP68 CloakTower_2x2  2x2
json jGroup = TileGroup();
jGroup = TileGroupAdd(jGroup, 0, 1, 282, 0);        // tcn01_u02_01
jGroup = TileGroupAdd(jGroup, 1, 1, 284, 0);        // tcn01_v02_01
jGroup = TileGroupAdd(jGroup, 0, 0, 277, 0);        // tcn01_u01_01
jGroup = TileGroupAdd(jGroup, 1, 0, 283, 0);        // tcn01_v01_01
```

The row flip matters. A `.set` group lists its tiles row-major starting from the
**north** row, so `Tile0` is the north-west corner, while library groups use
offsets from the **south-west** with `+y` north. `set_groups.py` applies the flip;
if you read a `.set` by hand, apply it yourself. The mapping is
`Tile[row * columns + column]` → offset `(column, rows - 1 - row)`, confirmed
against tcn01's model names (`Tile0` = 282 = `tcn01_u02_01`, the north-west
quadrant).

For a tileset that lives in a hak, unpack the hak first with
`nwn_erf -x -f some.hak`.

### Guard the tileset

A tile ID is only meaningful in its own tileset, so any feature with hard-coded IDs
should check the area before editing it:

```nwscript
if (GetTilesetResRef(oArea) != "tcn01") return FALSE;
```

That one line is what stops a feature from stamping garbage terrain in an area
built on something else. `inc_mason.nss` does this via `MasonCanWorkHere`; keep the
check when rethemeing.

### Reload flags

`nFlags` is a bitmask of `SETTILE_FLAG_*`, and only what you ask for is refreshed:

- `SETTILE_FLAG_RECOMPUTE_LIGHTING` — lighting and static shadows. Wanted almost always.
- `SETTILE_FLAG_RELOAD_GRASS` — needed if a tile gained or lost grass.
- `SETTILE_FLAG_RELOAD_BORDER` — only if the edit touches the area's outer edge.

Pass them once to `TileBatchApply` / `TileGroupStamp` for the whole edit rather
than per tile. The engine also exposes `RecomputeStaticLighting`, `ReloadAreaGrass`
and `ReloadAreaBorder` directly if you need to refresh without editing.

### Traps to remember

- **Placeables do not move.** A tile change ignores anything already sitting on
  the tile, so props end up floating or buried. Clean them up yourself.
- **Creatures can get stuck** when a walkable tile becomes solid — every tile of
  a tower is. `MasonStepClear` moves the player to the first in-bounds tile just
  outside the footprint; do the equivalent in any new feature. Note that
  `JumpToLocation` is queued on the player's action queue, so it lands the moment
  the script yields — just *after* the tiles change, not before. The player is
  briefly inside the new stonework, then relocated.
- **Tile edits do not persist.** See below.

## For a player: the Master Mason example

A complete player-facing feature built on the library: an NPC who raises a
watchtower wherever a player is standing, lets it fall to ruin, rebuilds it, or
pulls it down and restores the original ground.

### Wiring it in

Convert the two GFF-JSON resources to binary and place the NPC in a tcn01 area
(see [README.md](README.md#installing)). It carries tag, resref and conversation
`mason` plus the stock `x2_def_onconv` dialogue script, so it works as soon as it
is placed. Nothing needs adding to any area's `.git` for the scripts themselves.

The conversation reads the *player's* position, not the mason's, so the mason can
stand anywhere in the area and the player walks to where they want the tower.

### The conversation

The greeting runs `mason_c_top`, which always returns TRUE but fills `<CUSTOM430>`
with what the mason can see from where the player is standing — no room, ground
already built on, tower standing whole, tower standing ruined, or good ground.
Each option is then gated so players are only offered what is actually possible:

| Player option | Conditional | Action | Library call |
| --- | --- | --- | --- |
| Raise a watchtower on this spot. | `mason_c_new` — right tileset, fits, nothing too close | `mason_raise` | `TileSnapshotGroup` then `TileGroupStamp` |
| Let the tower fall to ruin. | `mason_c_int` — work nearby and currently whole | `mason_ruin` | `TileGroupStamp` with the ruin group |
| Rebuild the ruin whole again. | `mason_c_rui` — work nearby and currently ruined | `mason_build` | `TileGroupStamp` with the tower group |
| Pull it down altogether. | `mason_c_old` — any work nearby | `mason_raze` | `TileBatchApply` of the saved snapshot |

Each result line loops back to the greeting, so the status token is re-evaluated
and the option list narrows or widens as the ground changes. Every action script
reports success or failure with `SendMessageToPC`, so a refused edit is never
silent.

Ruin and rebuild swap `CloakTower_2x2` for `RuinedTower_2x2` and back. Both are
2x2 with the same origin, which is what keeps the snapshot taken at raise time
valid however often the variant is swapped.

### State

State lives in local variables on the **area**, keyed by the structure's origin
tile, so several towers can coexist:

- `mason_undo_<x>_<y>` — the tiles that were there before, as a `JsonDump`ed
  batch. Its presence is also the "something of mine stands here" flag, which is
  why razing deletes it.
- `mason_ruin_<x>_<y>` — set while the ruined variant is standing.

Ruin, rebuild and raze do not require the player to stand on the tower (they are
moved off it when it is raised). Each searches out to `MASON_SEARCH_RANGE` (3
tiles) for the nearest recorded origin. `MasonFootprintBlocked` stops a new tower
from overlapping an existing one by checking the only origins that could share a
square of a 2x2 footprint.

## What does not survive a reset

The engine never writes tile changes back to the `.are`, so **everything raised
this way is gone when the module restarts**, while the `mason_*` local variables
die with the area objects. That is consistent — you do not get orphaned
bookkeeping pointing at terrain that no longer exists — but it does mean towers
are session-scoped as written.

Making them durable means storing, per area, enough to replay the stamps: the
origin tile and which variant. If your persistence layer cannot be enumerated (a
campaign database cannot), keep a per-area index string alongside. Something then
has to re-stamp them on load, from OnModuleLoad. The raw undo snapshot does not
need saving — the pristine `.are` tiles are the undo after a reset. This is
deliberately not built.

## How this was verified

- `nwnsc` compiles the library and all ten example scripts clean, plus a
  throwaway harness that calls every public function and every default-argument
  overload, so nothing is merely unreferenced-and-unchecked.
- The rotation maths was replayed outside the game for sizes 1–5 and all three
  rotation amounts: every mapping is a bijection onto the original footprint (no
  tile lost or duplicated), the direction is genuinely counter-clockwise, and four
  90° turns return to the identity including orientations.
- `mason.dlg.json` round-trips through `nwn_gff`, every entry/reply index
  resolves, and all nine referenced scripts exist as `.nss` under the names the
  dialog uses.
- Tile IDs came from `tcn01.set` and were cross-checked two ways: against the
  group definitions and against the tile model names, then independently
  reproduced by `set_groups.py`.
- **Not tested in game.** That needs a live server: the tileset check, the visual
  result of each stamp, and whether `MasonStepClear` reliably keeps a player off a
  tower footprint all want confirming in a tcn01 area.
