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

### Never reason about a footprint with a width and height

`TileGroupTiles` returns the exact squares a group would cover, rotation applied,
as a *tile list* — a JSON array read back with `TileListCount` / `TileListX` /
`TileListY`. It touches nothing, so it also answers "which squares would this
cover?" before committing.

Use it instead of storing a width and height, because a bounding box is the wrong
shape to reason with:

- Features are frequently **non-square** — the majority, in most tilesets.
- Some are **not solid rectangles at all**. A `.set` can leave holes in a feature's
  bounding box, and a box-based collision check would then falsely claim squares
  the feature does not occupy. `Merchant_Docked` is 5 tiles in a 2×3 box; the sixth
  square stays free for something else to use.
- **Rotation moves the offsets**, so a box computed at rotation 0 is wrong at 90°.

```nwscript
json jTiles = TileGroupTiles(oArea, nX, nY, nRotation, jGroup);

int nIndex;
for (nIndex = 0; nIndex < TileListCount(jTiles); nIndex++)
{
    int nTileX = TileListX(jTiles, nIndex);
    int nTileY = TileListY(jTiles, nIndex);
    // ... bounds check, collision mark, edge test, keep-out check
}
```

`inc_mason.nss` is written this way throughout and is the pattern to copy: it holds
a mixed catalogue (2×2 tower, 2×1 guard post) with no size constant anywhere,
deriving collision, reload flags and get-out-of-the-way behaviour from the tile
list alone.

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

Worth knowing how often that limit applies: **non-square features outnumber square
ones** in most tilesets. In tcn01, 25 of the 41 multi-tile features are non-square;
ttf01 is 7 of 13, tdc01 6 of 11, trm02 30 of 46. So for a majority of tileset
features, 180° is the only in-place rotation available.

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

Extract the `.set`, then survey it with `tools/set_analyze.py`:

```sh
nwn_resman_cat --root ~/nwn-data --userdirectory ~/nwn-data/user \
    tcn01.set > /tmp/tcn01.set
python3 tools/set_analyze.py /tmp/tcn01.set          # full survey
python3 tools/set_analyze.py /tmp/tcn01.set shapes   # just the shape census
```

Once you know which feature you want, `tools/set_groups.py` emits it:

```sh
python3 tools/set_groups.py /tmp/tcn01.set cloaktower
```

```nwscript
// GROUP68 CloakTower_2x2  2x2 (columns x rows)
json jGroup = TileGroup();
jGroup = TileGroupAdd(jGroup, 0, 0, 277, 0);        // tcn01_u01_01
jGroup = TileGroupAdd(jGroup, 1, 0, 283, 0);        // tcn01_v01_01
jGroup = TileGroupAdd(jGroup, 0, 1, 282, 0);        // tcn01_u02_01
jGroup = TileGroupAdd(jGroup, 1, 1, 284, 0);        // tcn01_v02_01
```

For a tileset in a hak, unpack it first with `nwn_erf -x -f some.hak`.

### Four things that bite when reading a .set

**1. The row flip.** A `.set` group lists its tiles row-major starting from the
**north** row, so `Tile0` is the north-west corner, while library groups use
offsets from the **south-west** with `+y` north. The mapping is
`Tile[row * columns + column]` → offset `(column, rows - 1 - row)`. Both tools
apply it; if you read a `.set` by hand, apply it yourself.

This is verified, not assumed. Tile models are named
`<set>_<letters><number>_<variant>`, and in a rectangular feature one part varies
with the column and the other with the row — so the declared layout can be
checked independently of any arithmetic. Across six stock tilesets (tcn01, ttf01,
tdc01, tin01, ttu01, trm02) `set_analyze.py` confirms **389 of 397** features this
way.

**2. Group names lie about shape.** Stock tcn01 contains both `SlumHouse_1x2` and
`Market_2x1` — *the same shape*, `Rows=1 Columns=2`, named opposite ways. 18 of
tcn01's names state rows×columns rather than columns×rows; ttf01 has 6, tdc01 5.
**Always read `Rows=`/`Columns=`,** never the name. `set_analyze.py` prints the
real shape and flags names that contradict it.

**3. Features are not always solid rectangles.** A `Tile` value of `-1` is a
**hole**: a square of the bounding box that is not part of the feature, meaning
"leave whatever is already there". `-1` is not a tile ID and must never be
stamped. This is common, not exotic — tcn01 has 2 holed features
(`Merchant_Docked`, `Weathered_Docked`), ttf01 and tdc01 one each, and trm02 has
seven including a 5×3 `Castle3x5`. `set_groups.py` skips holes, and
`SetTileAt`/`TileBatchAdd`/`TileGroupAdd` all drop negative tile IDs rather than
pass them to the engine.

**4. Some features are hand-assembled.** A handful borrow a tile from elsewhere in
the tileset rather than using a clean block — tcn01's `StateBuilding02` reuses
`y08` where `y07`'s neighbour would be expected. `set_analyze.py` reports these as
`irregular`. They are perfectly usable; it only means the model-name cross-check
can't confirm them, and `Rows`/`Columns` stays authoritative.

### Picking a tile to fill an area with

`set_analyze.py ... fill` lists, per terrain type, the tiles that are safe to tile
a whole area with: every corner the same terrain at the same height and no edge
crosser. The height part matters — a tile with unequal corner heights is a height
*transition* and will not tile cleanly against itself. Stock tcn01's `TILE0` is
exactly that trap (three corners at height 1, one at 0), so "just use tile 0" is
wrong. tcn01 has 221 genuinely flat cobble tiles to choose from instead.

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
| Raise a watchtower on this spot. | `mason_c_new` — right tileset, room for the smallest entry | `mason_raise` | `TileSnapshotGroup` then `TileGroupStamp` (2×2) |
| Put up a guard post instead. | `mason_c_new` | `mason_post` | same, with a **2×1** group |
| Let the tower fall to ruin. | `mason_c_int` — nearby work has a ruined form | `mason_ruin` | `TileGroupStamp` with the ruin group |
| Rebuild the ruin whole again. | `mason_c_rui` — nearby work has a whole form | `mason_build` | `TileGroupStamp` with the tower group |
| Pull it down altogether. | `mason_c_old` — any work nearby | `mason_raze` | `TileBatchApply` of the saved snapshot |

Per-entry fit and collision are checked in the *actions*, not the conditionals,
because what fits depends on which entry the player picks; the conditional only
asks whether the mason can work here at all. Each action reports why it refused.

Each result line loops back to the greeting, so the status token is re-evaluated
and the option list narrows or widens as the ground changes. Every action script
reports success or failure with `SendMessageToPC`, so a refused edit is never
silent.

Ruin and rebuild swap `CloakTower_2x2` for `RuinedTower_2x2` and back. Both are
2x2 with the same origin, which is what keeps the snapshot taken at raise time
valid however often the variant is swapped.

### State

State lives in local variables on the **area**, so structures of different shapes
coexist:

- `mason_undo_<x>_<y>` — keyed by origin: the tiles that were there before, as a
  `JsonDump`ed batch. Its presence is also the "something of mine has its origin
  here" flag, which is why razing deletes it.
- `mason_kind_<x>_<y>` — keyed by origin: which catalogue entry stands here, `+1`
  so that 0 means none.
- `mason_occ_<x>_<y>` — keyed by **every square a structure covers**. This is what
  makes collision exact for mixed sizes and for holed features, where a
  bounding-box test would be wrong.

Ruin, rebuild and raze do not require the player to stand on the structure (they
are moved off when it goes up). Each searches out to `MASON_SEARCH_RANGE` for the
nearest recorded origin, then recomputes that entry's tile list to know what it
covers — so razing clears occupancy from the squares actually used, whatever shape
they form.

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
- **Not tested in game.** Everything above is static verification. The visual
  result of each stamp, walkability, and whether a player is reliably kept off a
  footprint can only be confirmed by playing. Build `demo/SetTileDemo.mod` with
  `bash demo/build_demo.sh` and see [demo/README.md](demo/README.md) for the cases
  worth trying.
