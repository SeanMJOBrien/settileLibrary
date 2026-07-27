# Demo module — The Mason's Yard

A loadable module for trying the library in game. One 10×10 City Exterior area
with the Master Mason standing in it and a lever wired to the builder demo.

Everything is generated or converted from the repo's own sources, so the demo
cannot drift from the library it demonstrates.

## Build

```sh
bash demo/build_demo.sh
```

Produces `demo/SetTileDemo.mod` (git-ignored — it is a build artifact). Then:

```sh
cp demo/SetTileDemo.mod ~/.local/share/Neverwinter\ Nights/modules/
```

and pick **SetTile Library Demo** from the New Module list.

The script needs `nwnsc`, `nwn_gff` and `nwn_erf`, plus a copy of the stock
NWScript includes. It looks for them beside the repo by default; override with
the `NWNSC`, `NWN_GFF`, `NWN_ERF` and `BASE_SCRIPTS` environment variables.

No haks and no custom TLK — it runs on a stock NWN:EE install.

## The yard

North is up. You start at `@`.

```
 y=9  .  .  .  .  .  .  .  .  .  .
 y=8  .  .  .  .  .  .  .  .  .  .
 y=7  .  .  .  .  .  .  .  .  .  .
 y=6  .  .  .  .  .  d  d  d  .  .     d = 3x3 patch the lever rotates
 y=5  .  .  .  .  .  T  T  d  .  .     T = 2x2 tower the lever stamps
 y=4  .  M  .  .  .  T  T  d  .  .     M = Master Mason
 y=3  .  .  .  .  .  .  .  .  .  .
 y=2  .  .  .  .  .  L  .  .  .  .     L = demo lever
 y=1  .  @  .  .  .  .  .  .  .  .     @ = your entry point
 y=0  .  .  .  .  .  .  .  .  .  .
      x=0 1  2  3  4  5  6  7  8  9
```

The whole yard is filled with tile 44 (`tcn01_o01_01`) — flat cobble that belongs
to no feature group, so anything stamped on it is obvious. `make_demo.py` explains
why the fill tile has to be chosen rather than assumed.

## What to do

### The lever — for builders

Pull it repeatedly. It cycles three steps, reporting each in your message log:

1. **Stamp** the 2×2 `CloakTower` group two tiles north of the lever.
2. **Rotate** the 3×3 patch of terrain there 90°.
3. **Undo** — restore the tiles saved before step 1.

The lever deliberately works *north of itself* rather than under its own feet: a
tile change ignores placeables already standing on the tile, so a lever that
stamped a tower onto its own square would end up sealed inside the stonework.

### Master Mason — for players

Walk to where you want a building and talk to him. Options appear only when they
are actually possible, and the greeting tells you what he can see from where you
stand.

| Option | What happens |
| --- | --- |
| Raise a watchtower on this spot. | Stamps a **2×2** tower at your feet |
| Put up a guard post instead. | Stamps a **2×1** post — a *non-square* footprint |
| Let the tower fall to ruin. | Swaps the tower for the ruined variant |
| Rebuild the ruin whole again. | Swaps it back |
| Pull it down altogether. | Restores the original cobble |

Worth trying deliberately:

- **Raise a tower, then try to raise a post overlapping it.** Refused — collision
  is tracked per covered square, not per bounding box.
- **Raise both a tower and a post.** Two different footprints coexist; the mason
  holds no size constant anywhere.
- **Stand on the spot and raise a tower.** You get moved clear, because tiles that
  turn solid would otherwise strand you.
- **Walk to the north edge and build there.** The area border is reloaded only
  when the work actually touches the edge.
- **Raise something, then reset the module.** It is gone. Runtime tile edits are
  never written back to the `.are` — see *What does not survive a reset* in
  [TILES.md](../TILES.md).

## What it is made of

| Source | Becomes |
| --- | --- |
| `make_demo.py` | `module.ifo`, `tiletest.are`, `tiletest.git` |
| `../utc/mason.utc.json` | `mason.utc`, and the creature instance in the `.git` |
| `../dlg/mason.dlg.json` | `mason.dlg` |
| `../nss/*.nss`, `../nss/example_mason/*.nss` | compiled `.ncs`, sources shipped too |

The lever is defined inline in the `.git` rather than as a `.utp`, because a
placeable instance already carries every blueprint field.

Sources are packed alongside the compiled scripts, so the module opens readably in
the toolset.
