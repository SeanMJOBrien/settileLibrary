# Adding your own feature — a walkthrough

Start-to-finish route for putting a tileset feature of your own into an area at
runtime: find its tile IDs, stamp it, and be able to take it back out again.

This is the *order to do things in*. It does not re-explain the concepts — each
step links to the reference in [TILES.md](../TILES.md) for the why. If you read
only one section there, read
**[the grid-reference rule](../TILES.md#the-one-rule-a-tile-location-is-a-grid-reference)**;
almost every tile bug comes from it.

Worked result: [`nss/example_mason/inc_mason.nss`](../nss/example_mason/inc_mason.nss)
does everything below, for a mixed catalogue of two differently-shaped features.

---

## 1. Get the library on your include path

```sh
nwnsc -i /path/to/settileLibrary/nss -i <your-sources> -b <out> your_script.nss
```

```nwscript
#include "inc_tile"
```

No dependencies, so no include shims needed. Details:
[README §Installing](../README.md#installing).

## 2. Extract your tileset's `.set`

Tile IDs are indexes into one specific `.set` and mean nothing outside it. You
cannot read a `.set` from NWScript, so this is a build-time job.

```sh
nwn_resman_cat --root ~/nwn-data --userdirectory ~/nwn-data/user \
    tcn01.set > /tmp/tcn01.set          # stock tileset
nwn_erf -x -f yourtiles.hak             # or unpack a hak first
```

## 3. Survey it and choose a feature

```sh
python3 tools/set_analyze.py /tmp/tcn01.set            # everything
python3 tools/set_analyze.py /tmp/tcn01.set shapes     # what shapes exist
python3 tools/set_analyze.py /tmp/tcn01.set groups tower
```

The `groups` report gives each feature's **real** shape, whether its layout is
independently confirmed, and whether it has holes. Note the `columns x rows` — you
will need it in step 7.

## 4. Do not trust the feature's name

`SlumHouse_1x2` and `Market_2x1` are the same shape. Names are unreliable in
stock tilesets; `Rows=`/`Columns=` is what counts, and the analyzer prints the
truth. Three other `.set` traps bite here too — holes, hand-assembled features,
and count mismatches.

Details: [TILES.md §Four things that bite when reading a .set](../TILES.md#four-things-that-bite-when-reading-a-set).

## 5. Generate the group

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

Paste that into a function that returns the group. The tool has already applied
the north-row flip and skipped any holes, so **do not** rearrange the offsets to
match how the `.set` lists them.

Details: [TILES.md §Groups](../TILES.md#groups).

## 6. Refuse to work on the wrong tileset

One line, and it is the difference between a feature that fails cleanly and one
that silently paints garbage terrain:

```nwscript
if (GetTilesetResRef(oArea) != "tcn01") return FALSE;
```

Details: [TILES.md §Guard the tileset](../TILES.md#guard-the-tileset).

## 7. Ask which squares it covers — never compute them

```nwscript
json jTiles = TileGroupTiles(oArea, nX, nY, nRotation, jGroup);
```

Everything downstream — bounds, collision, reload flags, moving people out of the
way — works from this list. Do **not** store a width and height and reason about a
box: most features are non-square, some are not rectangles at all, and rotation
moves the offsets.

```nwscript
int nIndex;
for (nIndex = 0; nIndex < TileListCount(jTiles); nIndex++)
{
    int nTileX = TileListX(jTiles, nIndex);
    int nTileY = TileListY(jTiles, nIndex);
    if (!TileInBounds(oArea, nTileX, nTileY)) return FALSE;
}
```

Details: [TILES.md §Never reason about a footprint with a width and height](../TILES.md#never-reason-about-a-footprint-with-a-width-and-height).

## 8. Save the ground before you change it

```nwscript
json jBefore = TileSnapshotGroup(oArea, nX, nY, nRotation, jGroup);
SetLocalString(oArea, "myfeature_undo", JsonDump(jBefore));
```

A snapshot *is* a batch, so putting it back later is one call. Take it **before**
stamping.

Details: [TILES.md §Snapshot and undo](../TILES.md#snapshot-and-undo).

## 9. Stamp it, with only the flags you need

```nwscript
int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING | SETTILE_FLAG_RELOAD_GRASS;
if (/* any covered square is on the area edge */) nFlags |= SETTILE_FLAG_RELOAD_BORDER;

TileGroupStamp(oArea, nX, nY, nRotation, jGroup, nFlags);
```

`TileGroupStamp` is all-or-nothing: off the map edge it writes nothing and returns
`FALSE`. Pass flags once for the whole edit, never per tile. Use `TileIsOnEdge` on
the covered squares to decide about the border.

Details: [TILES.md §Reload flags](../TILES.md#reload-flags).

## 10. Put it back

```nwscript
json jBefore = JsonParse(GetLocalString(oArea, "myfeature_undo"));
TileBatchApply(oArea, jBefore, nFlags);
DeleteLocalString(oArea, "myfeature_undo");
```

## 11. Deal with whatever is already standing there

Two things the engine will not do for you:

- **Placeables do not move.** Anything already on a tile stays put and can end up
  floating or buried. Keep switches and props clear of the work area — the demo
  lever deliberately works two tiles north of itself for exactly this reason.
- **Creatures can get stranded** when a walkable tile turns solid. Move them off
  first, and remember `JumpToLocation` is queued, so it lands just *after* the
  tiles change.

Details: [TILES.md §Traps to remember](../TILES.md#traps-to-remember).

## 12. Decide what happens after a reset

Runtime tile edits are never written back to the `.are`, so **your feature is gone
when the module restarts**. If it should persist, store enough to replay the stamp
(origin square, which feature, rotation) and re-stamp from `OnModuleLoad`. Do not
save the undo snapshot — after a reset the pristine `.are` tiles *are* the undo.

Details: [TILES.md §What does not survive a reset](../TILES.md#what-does-not-survive-a-reset).

## 13. Test it in game

Static checks cannot tell you whether a stamp *looks* right, whether the result is
walkable, or whether players get stuck. Build the demo module and try yours in it:

```sh
bash demo/build_demo.sh
cp demo/SetTileDemo.mod ~/.local/share/Neverwinter\ Nights/modules/
```

See [demo/README.md](../demo/README.md#what-to-do) for cases worth trying —
overlapping footprints, mixed sizes, building against the area edge.

---

## Checklist

- [ ] Tileset guarded with `GetTilesetResRef`
- [ ] Coordinates built with `TileLocation` / `TileXFromPosition`, never a world position
- [ ] Footprint from `TileGroupTiles`, not a width and height
- [ ] Every covered square bounds-checked
- [ ] Snapshot taken **before** stamping, if it should be undoable
- [ ] Reload flags passed once, border only if the work touches the edge
- [ ] Placeables and creatures on the footprint accounted for
- [ ] Reset behaviour decided deliberately
- [ ] Tried in game, not just compiled

## Where the rest lives

| Document | For |
| --- | --- |
| [README.md](../README.md) | Install, requirements, file list |
| [TILES.md](../TILES.md) | Full reference — every concept above, in depth |
| [demo/README.md](../demo/README.md) | The demo module: map, and what to try in game |
| `.claude/skills/nwn-tile-editing/` | The same material written for Claude Code |
