# SetTile Library

Runtime tile editing for NWN:EE. A portable NWScript include that wraps the engine
tile functions so a module can change area terrain while players are standing in
it — swap a tile, stamp a multi-tile structure, rotate a patch of terrain, snapshot
tiles and put them back.

Extracted from work on the *Shield Lands* persistent world, with all project
coupling removed.

---

## System Overview

- **One include, no dependencies.** `inc_tile.nss` uses engine functions only — no
  NWNX, no persistence layer, no other includes.
- **Grid-reference safety.** The engine's tile `location` is a grid reference, not
  a world position (see below). Every coordinate goes through one converter, and
  every read/write is bounds-checked instead of reaching the engine with a bad
  index.
- **Batched writes.** Multi-tile edits build a `SetTileJson` batch and apply it in
  one engine call, one client update, one lighting recompute.
- **Groups.** Describe a structure once as offsets from an origin tile, stamp it
  anywhere. All-or-nothing: a structure never half-lands across the map edge.
- **Snapshot / undo.** A snapshot *is* a batch, so undo is just applying it. Being
  plain JSON, it can be dumped to a string and stored.
- **A worked example.** `example_mason/` is a complete player-facing feature: an
  NPC who raises, ruins, rebuilds and razes a watchtower through dialog.

---

## Requirements

- **NWN:EE** with the tile scripting functions — `SetTile` was added in
  1.87.8193.35, and this uses `SetTileJson`, `GetTileID`, `GetTileOrientation`,
  `GetTileHeight`, `GetTilesetResRef`, `RecomputeStaticLighting`,
  `ReloadAreaGrass`, `ReloadAreaBorder` plus the `Json*` family.
- No NWNX plugins.
- The example mason expects the stock **tcn01** (City Exterior) tileset and the
  stock `x2_def_onconv` dialogue script. Any tileset works if you redo the tile-ID
  lookup — see [TILES.md](TILES.md).

---

## Files

### Library (`nss/`)

| File | Purpose |
| --- | --- |
| `inc_tile.nss` | The library. `#include "inc_tile"`. |
| `tile_demo.nss` | Builder's tour of the API — wire to a placeable's OnUsed and use it repeatedly; it cycles stamp → rotate → undo. |

### Worked example (`nss/example_mason/`)

| File | Purpose |
| --- | --- |
| `inc_mason.nss` | Tower definitions, per-tower state, the four operations. |
| `mason_raise.nss` | Dialog action — raise a watchtower where the player stands. |
| `mason_ruin.nss` / `mason_build.nss` | Dialog actions — swap the tower for its ruined variant and back. |
| `mason_raze.nss` | Dialog action — restore the original ground from the snapshot. |
| `mason_c_top.nss` | Greeting conditional; fills the `<CUSTOM430>` status token. |
| `mason_c_new.nss` | Gate — right tileset, room to build, nothing too close. |
| `mason_c_old.nss` | Gate — any of the mason's work within reach. |
| `mason_c_int.nss` / `mason_c_rui.nss` | Gates — the structure is currently whole / ruined. |

### Resources

| File | Purpose |
| --- | --- |
| `dlg/mason.dlg.json` | The conversation, as GFF-JSON. |
| `utc/mason.utc.json` | Master Mason NPC blueprint, as GFF-JSON. Tag/resref `mason`. |

### Tools (`tools/`)

| File | Purpose |
| --- | --- |
| `set_groups.py` | Reads a tileset `.set` and prints its groups as ready-to-paste `TileGroupAdd()` calls, applying the north-row flip. |

### Claude Code skill (`.claude/skills/`)

| File | Purpose |
| --- | --- |
| `nwn-tile-editing/SKILL.md` | How tiles work and how to use this library, written for [Claude Code](https://claude.com/claude-code). Loads automatically when working in this checkout; copy to `~/.claude/skills/` to use it from other projects. |

---

## Installing

Only the library is required; everything else is optional.

1. **Copy `nss/inc_tile.nss`** into your module's script sources, or add `nss/` to
   your compiler include path:

   ```sh
   nwnsc -i /path/to/settileLibrary/nss -i <your-sources> -b <out> your_script.nss
   ```

2. **Use it:**

   ```nwscript
   #include "inc_tile"

   void main()
   {
       object oArea = GetArea(OBJECT_SELF);
       vector vPos  = GetPosition(OBJECT_SELF);

       // A world position becomes a tile index only through these helpers.
       int nX = TileXFromPosition(vPos);
       int nY = TileYFromPosition(vPos);

       SetTileAt(oArea, nX, nY, 277, 0);
   }
   ```

3. **For the mason example**, also take `nss/example_mason/*.nss` and convert the
   two GFF-JSON resources to binary:

   ```sh
   nwn_gff -i dlg/mason.dlg.json  -o mason.dlg -k gff
   nwn_gff -i utc/mason.utc.json  -o mason.utc -k gff
   ```

   Then place the `mason` NPC in a tcn01 area. It carries tag, resref and
   conversation `mason` and the stock `x2_def_onconv`, so it works as soon as it is
   placed. Rename all three if `mason` collides in your module.

`nwn_gff` and `nwnsc` come from
[niv/neverwinter.nim](https://github.com/niv/neverwinter.nim) and
[nwnsc](https://github.com/nwneetool/nwnsc).

---

## The one rule

The `location` taken by `SetTile` / `GetTileID` / `GetTileOrientation` /
`GetTileHeight` is **not a world position**. Only its area, `x` and `y` are read,
and those are the tile *index* — `x` in `0 .. AREA_WIDTH-1`, `y` in
`0 .. AREA_HEIGHT-1` with `y = 0` along the south edge. Passing a real world
position addresses a tile ten times too far out.

The engine header is inconsistent about this: `SetTileMainLightColor` documents
*"the vector part of this is the tile grid (x,y) coordinate"* while `SetTile` only
says *"the location of the tile"*. Both are grid references. Build them with
`TileLocation()` and convert with `TileXFromPosition()` / `TileYFromPosition()`.

Full reference, builder workflow and caveats: **[TILES.md](TILES.md)**.

---

## Verifying a checkout

```sh
cd nss              && nwnsc -i . -i example_mason -i <base-scripts> -b /tmp tile_demo.nss
cd nss/example_mason && nwnsc -i . -i .. -i <base-scripts> -b /tmp mason_*.nss
```

`nwnsc` appends the input path to `-b`, which is why these run from inside the
source directories.
