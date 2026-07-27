---
name: nwn-tile-editing
description: Use this skill for changing NWN:EE area terrain tiles at RUNTIME from NWScript — swapping a tile, stamping a multi-tile structure (tower, house, bridge) while players watch, rotating a patch of terrain, or snapshotting tiles and restoring them. Trigger on "SetTile", "SetTileJson", "GetTileID", "SetTileMainLightColor", "tile ID", "tileset group", "tile orientation", ".set file", "change the terrain in game", "raise a building at runtime", or any request to edit an area's tiles while it is live. Covers the settileLibrary include (nss/inc_tile.nss) shipped in this repo. For editing an area's tiles statically in the .are file, use nwn-area-builder instead.
---

# NWN:EE Runtime Tile Editing

Changing area terrain from script, live, with players standing in it. Facts below
are verified against `nwscript.nss` (NWN:EE), a real extracted `tcn01.set`, and
real `.are` files — not recalled from memory.

> This copy ships inside the settileLibrary repo, so it loads automatically when
> working in this checkout and **file paths below are relative to the repo root**.
> To use it from other projects, copy this directory to
> `~/.claude/skills/nwn-tile-editing/` and make those paths absolute.

## First fork: runtime or build-time?

Two completely different jobs. Pick before writing anything.

| | Build-time | Runtime |
| --- | --- | --- |
| Edits | `.are` field `Tile_List` | `SetTile` / `SetTileJson` from NWScript |
| Tool | Python + `nwn_gff` | NWScript, in-game |
| Persists | Yes, it *is* the area | **No** — never written back to the `.are` |
| Skill | `nwn-area-builder` (schema in its `references/`) | **this one** |

`Tile_List` holds exactly `Width * Height` structs (verified on 16x8, 25x10 and
4x4 areas), each with `Tile_ID`, `Tile_Orientation`, `Tile_Height`, in the same
row-major-from-south-west order `SetTileJson` uses for its `index`. So the two
approaches address the same grid the same way — only persistence and timing differ.

If the user wants a change that survives a reset, runtime tile editing alone will
not do it (see [Persistence](#persistence)).

## THE TRAP: a tile location is a grid reference

The single most common way to get this wrong. The `location` taken by `SetTile`,
`GetTileID`, `GetTileOrientation`, `GetTileHeight` and `SetTileAnimationLoops` is
**not a world position**:

- Only the area, `x` and `y` are read. `z` and facing are **ignored**.
- `x` and `y` are the tile *index*: `x` in `0 .. GetAreaSize(AREA_WIDTH, oArea)-1`,
  `y` in `0 .. GetAreaSize(AREA_HEIGHT, oArea)-1`.
- `y = 0` is the **south** edge. `+y` is north.

```nwscript
// WRONG - a world position, or tile*10.0. Edits a tile 10x too far out, or nothing.
SetTile(GetLocation(oPC), 277, 0);
SetTile(Location(oArea, Vector(10.0, 20.0, 0.0), 0.0), 277, 0);   // means tile 10,20? No.

// RIGHT - the vector holds the tile index.
location lTile = Location(oArea, Vector(IntToFloat(nX), IntToFloat(nY), 0.0), 0.0);
SetTile(lTile, 277, 0);

// World position -> tile index: divide by 10 (tiles are 10m square).
int nX = FloatToInt(GetPosition(oPC).x / 10.0);
int nY = FloatToInt(GetPosition(oPC).y / 10.0);
```

The engine header is genuinely inconsistent, which is why this bites people:
`SetTileMainLightColor` documents *"the vector part of this is the tile grid (x,y)
coordinate"*, while `SetTile` only says *"the location of the tile"*. **Both are
grid references.** Do not trust the wording; trust this.

Beware AI-generated or forum tile snippets — they very often step by `10.0` per
tile or pass `GetLocation(OBJECT_SELF)` straight through. Both are wrong.

## How tiles work

- An area is a `Width x Height` grid of tiles, each 10x10 metres.
- A **tile ID** is an index into the area's tileset `.set` file. IDs are only
  meaningful within that one tileset — 277 is a tower quadrant in `tcn01` and
  something unrelated everywhere else. Always guard:
  `if (GetTilesetResRef(oArea) != "tcn01") return;`
- **Orientation** is `0-3`, counting 90° steps **counter-clockwise**.
- **Height** raises the tile; default 0.
- A multi-tile feature (tower, house) is *not* one tile — it is N tiles, each a
  distinct model authored for its own position in the footprint. This matters for
  rotation (see below).

### The .set file

Plain INI. `[GENERAL]` (default/floor/border terrain), `[TERRAIN*]`/`[CROSSER*]`
type names, `[TILEn]` per tile, `[GROUPn]` per multi-tile feature:

```ini
[TILE277]
Model=tcn01_u01_01          ; the number in [TILEnnn] IS the tile ID
TopLeft=cobble              ; corner terrain, x4
TopLeftHeight=1             ; corner height, x4 - unequal means height transition
Top=                        ; edge crosser (wall/road/stream), x4

[GROUP68]
Name=CloakTower_2x2
Rows=2
Columns=2
Tile0=282                   ; row-major starting from the NORTH row
Tile1=284
Tile2=277
Tile3=283
```

**Never hand-read a .set — run `tools/set_analyze.py` on it.** Four traps, all
verified against six stock tilesets:

1. **Row flip.** `GROUP` tiles are row-major from the **NORTH**, so `Tile0` is the
   north-west corner, while library groups use south-west-origin offsets with `+y`
   north: `Tile[row * columns + column]` → offset `(column, rows - 1 - row)`.
2. **Group names lie about shape.** tcn01 has `SlumHouse_1x2` *and* `Market_2x1` —
   the same `Rows=1 Columns=2` shape, named opposite ways. 18 tcn01 names state
   rows×columns. **Read `Rows=`/`Columns=`, never the name.**
3. **`Tile=-1` is a hole**, not a tile ID — a square of the bounding box that
   isn't part of the feature ("leave what's there"). Features are not always solid
   rectangles. Common: tcn01 2, ttf01 1, tdc01 1, trm02 7. The library drops
   negative IDs in all three write paths rather than stamping them.
4. **`[TILES] Count` can disagree** with the `[TILEn]` sections present, and
   `[TILEnDOORm]` sections are door definitions, not tiles. `set_analyze.py
   <set> integrity` checks this.

The flip is confirmed independently, not assumed: models are named
`<set>_<letters><number>_<variant>` and in a rectangular feature one part varies
with the column and the other with the row — which axis is *not* universal (tcn01
uses letters for columns, the Ampitheater's `amp01` does the opposite), so the
analyzer tries both. It confirms 389 of 397 features across six tilesets; the
remainder are hand-assembled from non-adjacent tiles, which is legal.

**Filling an area:** use `set_analyze.py <set> fill` for tiles that are flat
(all four corner heights equal), single-terrain and crosser-free. Do not reach for
tile 0 — tcn01's `TILE0` has three corners at height 1 and one at 0, so it is a
height transition that won't tile against itself.

### Engine API (verified signatures)

```nwscript
void SetTile(location locTile, int nTileID, int nOrientation, int nHeight = 0,
             int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);
int  GetTileID(location locTile);           // -1 on error
int  GetTileOrientation(location locTile);  // -1 on error
int  GetTileHeight(location locTile);       // -1 on error
void SetTileJson(object oArea, json jTileData,
                 int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING, string sTileset = "");
void SetTileAnimationLoops(location locTile, int bAnimLoop1, int bAnimLoop2, int bAnimLoop3);
string GetTilesetResRef(object oArea);
void RecomputeStaticLighting(object oArea);
void ReloadAreaGrass(object oArea);
void ReloadAreaBorder(object oArea);
```

`SetTileJson`'s `jTileData` is a JSON array of objects with keys `index`,
`tileid`, `orientation`, `height` (plus optional `animloop1..3`). `index` is
`y * width + x`. **Unset keys default to 0**, so always write all of
`tileid`/`orientation`/`height` or you will silently flatten tiles to ID 0.

Never pass `sTileset` unless changing every tile in the area — the header warns
it is "very easy to break things badly".

**Flags** (`nFlags` is a bitmask; only what you ask for is refreshed):

| Flag | When |
| --- | --- |
| `SETTILE_FLAG_RECOMPUTE_LIGHTING` | Lighting + static shadows. Almost always. |
| `SETTILE_FLAG_RELOAD_GRASS` | A tile gained or lost grass. |
| `SETTILE_FLAG_RELOAD_BORDER` | The edit touches the area's outer edge. |

Apply flags **once for the whole edit**, not per tile. Prefer one `SetTileJson`
batch over N `SetTile` calls: one engine call, one client update, one recompute.

## The library: settileLibrary

`nss/inc_tile.nss` is a single include with **no dependencies** (engine functions
only, no NWNX), so it needs no include shims.

```sh
nwnsc -i <settileLibrary>/nss -i <your-sources> -b <out> your_script.nss
```

```nwscript
#include "inc_tile"
```

It exists so you never hand-build a tile location. Use it rather than raw
`SetTile` unless there's a reason not to.

| Group | Functions |
| --- | --- |
| Grid | `TileGridWidth/Height`, `TileInBounds`, `TileIsOnEdge`, `TileLocation`, `TileIndex`, `TileWorldCenter`, `TileXFromPosition`, `TileYFromPosition` |
| Rotation helpers | `TileRotateOrientation`, `TileRotationFromFacing` |
| One tile | `GetTileIDAt`, `GetTileOrientationAt`, `GetTileHeightAt`, `SetTileAt` |
| Batches | `TileBatch`, `TileBatchAdd`, `TileBatchCount`, `TileBatchApply` |
| Groups | `TileGroup`, `TileGroupAdd`, `TileGroupCount`, `TileGroupFits`, `TileGroupStamp`, `TileGroupStampAtLocation` |
| Tile lists | `TileGroupTiles`, `TileListCount`, `TileListX`, `TileListY` |
| Snapshot | `TileSnapshotRect`, `TileSnapshotGroup` |
| Rotation | `TileBlockRotate` (square), `TileBlockRotate180` (rectangle) |

Constants: `TILE_INVALID` (-1), `TILE_ROTATE_NONE/90/180/270`, `TILE_WORLD_SIZE`
(10.0), `TILE_FLAGS_ALL`.

Everything is bounds-checked: out of range returns `TILE_INVALID` or `FALSE`
instead of reaching the engine.

### Stamping a structure

A **group** describes a structure once as offsets from an origin tile (`+y`
north), so it can be stamped anywhere. `TileGroupStamp` is **all-or-nothing** —
off the map edge it writes nothing and returns FALSE, so a building never
half-lands. `TileGroupFits` is the same check without writing (use it in dialog
conditionals to decide whether to even offer the option).

```nwscript
json jTower = TileGroup();
jTower = TileGroupAdd(jTower, 0, 0, 277, 0);   // SW
jTower = TileGroupAdd(jTower, 1, 0, 283, 0);   // SE
jTower = TileGroupAdd(jTower, 0, 1, 282, 0);   // NW
jTower = TileGroupAdd(jTower, 1, 1, 284, 0);   // NE

// Save the ground first so it can be undone.
json jBefore = TileSnapshotGroup(oArea, nX, nY, TILE_ROTATE_NONE, jTower);
TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, jTower,
               SETTILE_FLAG_RECOMPUTE_LIGHTING | SETTILE_FLAG_RELOAD_GRASS);
```

Group offsets rotate **about the origin tile**, not the group's centre, so
stamping a 2x2 group at 90° shifts its footprint one tile west. That is the
contract, not a bug.

### Never reason about a footprint with a width and height

`TileGroupTiles(oArea, nX, nY, nRotation, jGroup)` returns the exact squares a
group covers, rotation applied, as a *tile list* read back with `TileListCount` /
`TileListX` / `TileListY`. It writes nothing, so it also answers "which squares
would this cover?" before committing.

Always prefer it to a stored width/height, because a bounding box is the wrong
shape to reason with:

- Non-square features are the **majority** in most tilesets.
- Some features are **not solid rectangles**: a `.set` can leave holes, so a
  box-based collision test falsely claims squares the feature doesn't occupy.
  `Merchant_Docked` is 5 tiles in a 2×3 box — the sixth stays usable by something
  else.
- Rotation moves the offsets, so a box computed at rotation 0 is wrong at 90°.

```nwscript
json jTiles = TileGroupTiles(oArea, nX, nY, nRotation, jGroup);
int nIndex;
for (nIndex = 0; nIndex < TileListCount(jTiles); nIndex++)
{
    int nTileX = TileListX(jTiles, nIndex);
    int nTileY = TileListY(jTiles, nIndex);
    // bounds check / collision mark / edge test / keep-out
}
```

`example_mason/inc_mason.nss` is written this way throughout — a mixed catalogue
(2×2 tower, 2×1 guard post) with no size constant anywhere. If you find yourself
writing `MY_STRUCTURE_SIZE`, use a tile list instead.

### Snapshot and undo

A snapshot **is** a batch, so undo is just applying it — there is no separate
restore call:

```nwscript
TileBatchApply(oArea, jBefore, nFlags);
```

Being plain JSON, `JsonDump` makes it a storable string and `JsonParse` brings it
back.

Gotcha: always assign the result of `TileBatchAdd`/`TileGroupAdd`
(`jBatch = TileBatchAdd(jBatch, ...)`). The `Json*Inplace` engine helpers mutate a
*copy* when a json value is passed into a function.

### Getting tile IDs

Build-time job — a `.set` cannot be read from NWScript. Use the bundled tools:

```sh
nwn_resman_cat --root ~/nwn-data --userdirectory ~/nwn-data/user \
    tcn01.set > /tmp/tcn01.set
python3 tools/set_analyze.py /tmp/tcn01.set            # survey first
python3 tools/set_analyze.py /tmp/tcn01.set shapes     # general|integrity|shapes|fill|groups
python3 tools/set_groups.py  /tmp/tcn01.set cloaktower # then emit one feature
```

`set_analyze.py` reports every feature's real shape and layout, holes, flat filler
tiles and integrity problems — run it before trusting anything about an unfamiliar
tileset. `set_groups.py` prints ready-to-paste `TileGroupAdd()` lines with the
north-row flip already applied, holes skipped, and the model name in a trailing
comment. For a hak tileset, unpack it
first: `nwn_erf -x -f some.hak`.

## Rotation: what it can and cannot do

`TileBlockRotate(oArea, nX, nY, nSize, nRotation, nFlags)` rotates a **square**
block in place, turning both each tile's position and its own orientation.
Square only — and that limit bites often, because **non-square features outnumber
square ones** in most tilesets (tcn01: 25 of 41 multi-tile; trm02: 30 of 46). For
most tileset features 180° is the only in-place rotation available.

Rotating `W x H` by 90° yields `H x W`, which cannot be written back
over the original footprint. `TileBlockRotate180` handles rectangles (180°
preserves shape).

**It is a terrain tool, not a way to reface a building.** The four tiles of a
tileset tower are four *different* models, one per quadrant (`tcn01`'s
`CloakTower_2x2` is `u01`/`u02`/`v01`/`v02`). Rotating a tile only spins that
quadrant's own model, so rearranging the four and bumping their orientations
**scrambles** the structure instead of turning it.

- Correct for: terrain crossers, roads, single-tile features — anything whose
  orientation is meaningful on its own.
- Wrong for: authored multi-tile structures. To "turn" one you need a
  differently-authored group. Swapping groups (as the mason example's
  ruin/rebuild does) is the honest equivalent.

If a user asks to rotate a building at runtime, say this rather than shipping
something that renders wrong.

## Caveats checklist

Before shipping any runtime tile edit:

- [ ] Tileset guarded with `GetTilesetResRef`? IDs are tileset-specific.
- [ ] Coordinates built via `TileLocation`, never a world position?
- [ ] Bounds-checked, or using the library (which does it)?
- [ ] Flags applied once for the whole edit, not per tile?
- [ ] **Placeables on the tile do not move** — they end up floating or buried.
      Clean them up yourself.
- [ ] **Creatures can get stuck** when a walkable tile turns solid. Move them off
      first. Note `JumpToLocation` is queued on the action queue, so it lands just
      *after* the tiles change — the PC is briefly inside the new geometry.
- [ ] Snapshot taken if the change should be undoable?

## Persistence

**Runtime tile edits never persist.** The engine does not write them back to the
`.are`, so everything is gone on reset. To make them durable, store enough to
*replay* the stamps (origin tile + which structure) in your persistence layer, and
re-stamp from `OnModuleLoad`. A campaign DB cannot be enumerated, so keep a
per-area index string alongside. Do not bother saving the undo snapshot — after a
reset the pristine `.are` tiles *are* the undo.

## Worked example and full reference

- `nss/example_mason/` — a complete player-facing feature: an
  NPC who raises / ruins / rebuilds / razes a watchtower through dialog, with
  per-structure state on the area and gated dialog options.
- `nss/tile_demo.nss` — builder's tour; wire to a placeable's
  OnUsed and use it repeatedly to cycle stamp → rotate → undo.
- `TILES.md` — full reference and rationale.
- `README.md` — install, requirements, file list.

## Verifying tile work

There are no unit tests for NWScript. What is actually checkable without a server:

1. **Compile.** `nwnsc` catches signature and type errors. Write a throwaway
   script calling every function and default-arg overload — unreferenced functions
   in an include are otherwise never code-generated.
2. **Replay coordinate maths outside the game.** Port the rotation/offset logic to
   Python and assert it is a bijection onto the intended footprint (nothing lost or
   duplicated), that direction is what you claim, and that four 90° turns return to
   identity. This caught real bugs in the library's ancestor.
3. **Cross-check tile IDs two ways** — group definitions *and* tile model names.
4. Be explicit that visual results, walkability and stuck-creature behaviour are
   **not** verified until tested on a live server in an area of that tileset.
