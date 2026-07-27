// Builder-facing tour of inc_tile. Wire it to a placeable's OnUsed (or a DM
// wand) in a City Exterior (tcn01) area and use it repeatedly: it cycles through
// stamping a group, rotating a patch of terrain, and undoing both.
//
// Everything here is deliberately hard-coded so the API calls are easy to read.
// For a real feature see inc_mason.nss, which does the same work with proper
// bounds checks and per-tower state.

#include "inc_tile"

// tcn01.set, GROUP68 CloakTower_2x2. Group tiles are listed row-major from the
// NORTH, so Tile0..Tile3 = NW, NE, SW, SE -> 282, 284, 277, 283.
const int DEMO_TOWER_SW = 277;
const int DEMO_TOWER_SE = 283;
const int DEMO_TOWER_NW = 282;
const int DEMO_TOWER_NE = 284;

const int DEMO_PATCH_SIZE = 3;

// The work happens this many tiles NORTH of the placeable rather than under it.
// Tile edits ignore placeables already standing on a tile, so a lever that
// stamped a tower onto its own square would end up buried in the stonework and
// unusable. Keeping the switch clear of the work area is the general lesson.
const int DEMO_WORK_OFFSET = 2;

const string DEMO_VAR_STEP = "tile_demo_step";
const string DEMO_VAR_UNDO = "tile_demo_undo";

void main()
{
    object oUser = GetLastUsedBy();
    if (!GetIsObjectValid(oUser)) oUser = GetFirstPC();

    object oArea = GetArea(OBJECT_SELF);
    vector vPos = GetPosition(OBJECT_SELF);

    // A world position becomes a tile index only through these helpers - the tile
    // functions take a grid reference, never a world position.
    int nX = TileXFromPosition(vPos);
    int nY = TileYFromPosition(vPos) + DEMO_WORK_OFFSET;

    int nStep = GetLocalInt(OBJECT_SELF, DEMO_VAR_STEP) % 3;
    SetLocalInt(OBJECT_SELF, DEMO_VAR_STEP, nStep + 1);

    if (nStep == 0)
    {
        // --- Stamping a group ---
        // Offsets are in the group's own frame with the origin at the south-west
        // tile and +y north, which is why the .set group's north row goes last.
        json jTower = TileGroup();
        jTower = TileGroupAdd(jTower, 0, 0, DEMO_TOWER_SW, 0);
        jTower = TileGroupAdd(jTower, 1, 0, DEMO_TOWER_SE, 0);
        jTower = TileGroupAdd(jTower, 0, 1, DEMO_TOWER_NW, 0);
        jTower = TileGroupAdd(jTower, 1, 1, DEMO_TOWER_NE, 0);

        // Save the ground first; TileSnapshotGroup captures exactly the tiles the
        // stamp is about to cover.
        SetLocalString(OBJECT_SELF, DEMO_VAR_UNDO,
                       JsonDump(TileSnapshotGroup(oArea, nX, nY, TILE_ROTATE_NONE, jTower)));

        // TileGroupStamp is all-or-nothing: off the map edge it writes nothing.
        if (TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, jTower,
                           SETTILE_FLAG_RECOMPUTE_LIGHTING | SETTILE_FLAG_RELOAD_GRASS))
            SendMessageToPC(oUser, "Stamped CloakTower_2x2 at tile " +
                            IntToString(nX) + "," + IntToString(nY) + ".");
        else
            SendMessageToPC(oUser, "The tower does not fit here.");
    }
    else if (nStep == 1)
    {
        // --- Rotating terrain in place ---
        // Correct for tiles whose orientation is meaningful on its own: terrain
        // crossers, roads, single-tile features. It is NOT a way to reface an
        // authored multi-tile structure - each tile of the tower above is a
        // different quadrant model, so rotating those four only scrambles them.
        // Square blocks only; 90 degrees of a W x H block would need an H x W hole
        // to land in. Use TileBlockRotate180 for a rectangle.
        if (TileBlockRotate(oArea, nX, nY, DEMO_PATCH_SIZE, TILE_ROTATE_90))
            SendMessageToPC(oUser, "Rotated the " + IntToString(DEMO_PATCH_SIZE) + "x" +
                            IntToString(DEMO_PATCH_SIZE) + " patch 90 degrees.");
        else
            SendMessageToPC(oUser, "That patch runs off the edge of the area.");
    }
    else
    {
        // --- Undo ---
        // A snapshot is already a batch in SetTileJson's format, so putting it
        // back is just applying it.
        json jUndo = JsonParse(GetLocalString(OBJECT_SELF, DEMO_VAR_UNDO));
        if (TileBatchApply(oArea, jUndo,
                           SETTILE_FLAG_RECOMPUTE_LIGHTING | SETTILE_FLAG_RELOAD_GRASS))
            SendMessageToPC(oUser, "Restored " + IntToString(TileBatchCount(jUndo)) + " tiles.");
        else
            SendMessageToPC(oUser, "Nothing saved to restore.");
    }
}
