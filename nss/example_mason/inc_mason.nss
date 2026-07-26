// Master Mason - the player-facing half of the runtime tile system.
//
// Backs the mason conversation: a player stands where they want a watchtower,
// talks to the mason, and the mason raises it, lets it fall to ruin, rebuilds it
// or pulls it down entirely - all by editing the area's tiles through
// inc_tile.
//
// All state lives in local variables on the AREA, keyed by the structure's origin
// tile, so several towers can coexist in one area:
//     mason_undo_<x>_<y>   the tiles that were there before, as a batch dump
//     mason_ruin_<x>_<y>   1 while the ruined variant is standing
// The undo string doubling as "something of mine stands here" is why razing
// clears it.
//
// Tile edits are runtime-only - the engine never writes them back to the .are -
// so everything raised here is gone after a reset. See TILES.md.
//
// WHY THERE IS NO "TURN THE TOWER" OPTION
//
// The four tiles of a tileset tower are four different models, one per quadrant
// (tcn01's are u01/u02/v01/v02). Rotating a tile only spins that quadrant's own
// model, so rearranging the four and bumping their orientations does not turn the
// tower - it scrambles it. Runtime rotation (TileBlockRotate) is a terrain tool,
// correct for tiles whose orientation is meaningful on its own; it is not a way
// to reface an authored multi-tile structure. Swapping in a differently-authored
// group, as the ruin option does, is the honest equivalent.

#include "inc_tile"

// The tileset these tile IDs were read from. A tile ID is meaningless outside its
// own tileset, so the mason refuses to work anywhere else - without this check,
// building in the wrong area silently produces garbage terrain.
// To run the mason on a different tileset, repeat the .set lookup described in
// TILES.md and change MASON_TILESET plus the eight tile constants below. Keep the
// check itself.
const string MASON_TILESET = "tcn01"; // City Exterior, stock NWN

// Real IDs read from tcn01.set. Group tiles are listed row-major from the NORTH,
// so CloakTower_2x2's Tile0..Tile3 = NW, NE, SW, SE.
//   GROUP68 CloakTower_2x2  = 282, 284, 277, 283
//   GROUP76 RuinedTower_2x2 = 301, 303, 300, 302
const int MASON_TOWER_SW = 277;
const int MASON_TOWER_SE = 283;
const int MASON_TOWER_NW = 282;
const int MASON_TOWER_NE = 284;

const int MASON_RUIN_SW = 300;
const int MASON_RUIN_SE = 302;
const int MASON_RUIN_NW = 301;
const int MASON_RUIN_NE = 303;

// Both groups are 2x2 and share a footprint, which is what lets one be swapped
// for the other without invalidating the undo snapshot.
const int MASON_TOWER_SIZE = 2;

// How far from the player the mason will look for his own work.
const int MASON_SEARCH_RANGE = 3;

const string MASON_VAR_UNDO = "mason_undo_";
const string MASON_VAR_RUINED = "mason_ruin_";

// Dialog token carrying the mason's status line.
const int MASON_TOKEN_STATUS = 430;

// --- Prototypes ---

// Either structure as a reusable group, in its own frame with the origin at the
// south-west tile. Tileset groups are authored at orientation 0.
json MasonStructureGroup(int bRuined);

string MasonUndoVar(int nX, int nY);
string MasonRuinedVar(int nX, int nY);

// TRUE if the mason has something recorded with its origin on this exact tile.
int MasonHasWorkAt(object oArea, int nX, int nY);

// TRUE if the structure standing at (nX,nY) is the ruined variant.
int MasonIsRuined(object oArea, int nX, int nY);

// Nearest recorded origin within MASON_SEARCH_RANGE of (nX,nY). Returns .z = 1.0
// when one was found, with .x/.y holding its origin tile.
vector MasonFindWork(object oArea, int nX, int nY);

// TRUE if existing work already occupies any tile a new structure at (nX,nY)
// would need.
int MasonFootprintBlocked(object oArea, int nX, int nY);

// TRUE if oArea is built on the tileset the mason's tile IDs come from.
int MasonCanWorkHere(object oArea);

// Reload flags appropriate to work at (nX,nY).
int MasonWorkFlags(object oArea, int nX, int nY);

// Move oPC clear of the footprint - a tile that stops being walkable can
// otherwise strand whoever is standing on it, and every tile of a tower is solid.
// The jump is queued on oPC's action queue, so it lands the moment the calling
// script yields, just after the tiles change rather than just before.
void MasonStepClear(object oPC, int nX, int nY);

// The three things the conversation can ask for. Each returns TRUE on success.
int MasonRaiseTower(object oPC);
int MasonSetRuined(object oPC, int bRuined);
int MasonRazeTower(object oPC);

// --- Structure definitions and state ---

json MasonStructureGroup(int bRuined)
{
    json jGroup = TileGroup();
    if (bRuined)
    {
        jGroup = TileGroupAdd(jGroup, 0, 0, MASON_RUIN_SW, 0);
        jGroup = TileGroupAdd(jGroup, 1, 0, MASON_RUIN_SE, 0);
        jGroup = TileGroupAdd(jGroup, 0, 1, MASON_RUIN_NW, 0);
        jGroup = TileGroupAdd(jGroup, 1, 1, MASON_RUIN_NE, 0);
        return jGroup;
    }
    jGroup = TileGroupAdd(jGroup, 0, 0, MASON_TOWER_SW, 0);
    jGroup = TileGroupAdd(jGroup, 1, 0, MASON_TOWER_SE, 0);
    jGroup = TileGroupAdd(jGroup, 0, 1, MASON_TOWER_NW, 0);
    jGroup = TileGroupAdd(jGroup, 1, 1, MASON_TOWER_NE, 0);
    return jGroup;
}

string MasonUndoVar(int nX, int nY)
{
    return MASON_VAR_UNDO + IntToString(nX) + "_" + IntToString(nY);
}

string MasonRuinedVar(int nX, int nY)
{
    return MASON_VAR_RUINED + IntToString(nX) + "_" + IntToString(nY);
}

int MasonHasWorkAt(object oArea, int nX, int nY)
{
    return (GetLocalString(oArea, MasonUndoVar(nX, nY)) != "");
}

int MasonIsRuined(object oArea, int nX, int nY)
{
    return GetLocalInt(oArea, MasonRuinedVar(nX, nY));
}

vector MasonFindWork(object oArea, int nX, int nY)
{
    int nBestX = 0;
    int nBestY = 0;
    int nBestDistance = -1;

    int nOffsetY;
    for (nOffsetY = -MASON_SEARCH_RANGE; nOffsetY <= MASON_SEARCH_RANGE; nOffsetY++)
    {
        int nOffsetX;
        for (nOffsetX = -MASON_SEARCH_RANGE; nOffsetX <= MASON_SEARCH_RANGE; nOffsetX++)
        {
            if (!MasonHasWorkAt(oArea, nX + nOffsetX, nY + nOffsetY)) continue;

            int nDistance = abs(nOffsetX) + abs(nOffsetY);
            if ((nBestDistance >= 0) && (nDistance >= nBestDistance)) continue;

            nBestDistance = nDistance;
            nBestX = nX + nOffsetX;
            nBestY = nY + nOffsetY;
        }
    }

    if (nBestDistance < 0) return Vector(0.0, 0.0, 0.0);
    return Vector(IntToFloat(nBestX), IntToFloat(nBestY), 1.0);
}

int MasonFootprintBlocked(object oArea, int nX, int nY)
{
    // Only origins within one tile can share a square of a 2x2 footprint.
    int nOffsetY;
    for (nOffsetY = -(MASON_TOWER_SIZE - 1); nOffsetY <= MASON_TOWER_SIZE - 1; nOffsetY++)
    {
        int nOffsetX;
        for (nOffsetX = -(MASON_TOWER_SIZE - 1); nOffsetX <= MASON_TOWER_SIZE - 1; nOffsetX++)
        {
            if (MasonHasWorkAt(oArea, nX + nOffsetX, nY + nOffsetY)) return TRUE;
        }
    }
    return FALSE;
}

int MasonCanWorkHere(object oArea)
{
    if (!GetIsObjectValid(oArea)) return FALSE;
    return (GetTilesetResRef(oArea) == MASON_TILESET);
}

int MasonWorkFlags(object oArea, int nX, int nY)
{
    int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING | SETTILE_FLAG_RELOAD_GRASS;

    // The outer border only needs reloading when the work reaches the map edge.
    if (TileIsOnEdge(oArea, nX, nY) ||
        TileIsOnEdge(oArea, nX + MASON_TOWER_SIZE - 1, nY + MASON_TOWER_SIZE - 1))
        nFlags = nFlags | SETTILE_FLAG_RELOAD_BORDER;

    return nFlags;
}

void MasonStepClear(object oPC, int nX, int nY)
{
    object oArea = GetArea(oPC);

    // First in-bounds tile just outside the footprint, tried south, west, east,
    // north.
    int nSafeX = nX;
    int nSafeY = nY - 1;
    if (!TileInBounds(oArea, nSafeX, nSafeY)) { nSafeX = nX - 1;                 nSafeY = nY; }
    if (!TileInBounds(oArea, nSafeX, nSafeY)) { nSafeX = nX + MASON_TOWER_SIZE;  nSafeY = nY; }
    if (!TileInBounds(oArea, nSafeX, nSafeY)) { nSafeX = nX;                     nSafeY = nY + MASON_TOWER_SIZE; }
    if (!TileInBounds(oArea, nSafeX, nSafeY)) return;

    // Unlike the tile functions, JumpToLocation wants a real world position.
    location lSafe = Location(oArea, TileWorldCenter(nSafeX, nSafeY), GetFacing(oPC));
    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, JumpToLocation(lSafe));
}

// --- The three operations ---

int MasonRaiseTower(object oPC)
{
    object oArea = GetArea(oPC);
    if (!MasonCanWorkHere(oArea)) return FALSE;

    vector vPos = GetPosition(oPC);
    int nX = TileXFromPosition(vPos);
    int nY = TileYFromPosition(vPos);

    json jTower = MasonStructureGroup(FALSE);
    if (!TileGroupFits(oArea, nX, nY, TILE_ROTATE_NONE, jTower)) return FALSE;
    if (MasonFootprintBlocked(oArea, nX, nY)) return FALSE;

    // Capture the ground before overwriting it, so razing can put it back.
    json jBefore = TileSnapshotGroup(oArea, nX, nY, TILE_ROTATE_NONE, jTower);

    MasonStepClear(oPC, nX, nY);

    if (!TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, jTower, MasonWorkFlags(oArea, nX, nY)))
        return FALSE;

    SetLocalString(oArea, MasonUndoVar(nX, nY), JsonDump(jBefore));
    DeleteLocalInt(oArea, MasonRuinedVar(nX, nY));
    return TRUE;
}

int MasonSetRuined(object oPC, int bRuined)
{
    object oArea = GetArea(oPC);
    vector vPos = GetPosition(oPC);
    vector vFound = MasonFindWork(oArea, TileXFromPosition(vPos), TileYFromPosition(vPos));
    if (vFound.z < 1.0) return FALSE;

    int nX = FloatToInt(vFound.x);
    int nY = FloatToInt(vFound.y);
    if (MasonIsRuined(oArea, nX, nY) == bRuined) return FALSE;

    // Both variants are 2x2 with the same origin, so the snapshot taken when the
    // tower was first raised still describes the ground underneath.
    MasonStepClear(oPC, nX, nY);
    if (!TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, MasonStructureGroup(bRuined),
                        MasonWorkFlags(oArea, nX, nY)))
        return FALSE;

    if (bRuined) SetLocalInt(oArea, MasonRuinedVar(nX, nY), TRUE);
    else         DeleteLocalInt(oArea, MasonRuinedVar(nX, nY));
    return TRUE;
}

int MasonRazeTower(object oPC)
{
    object oArea = GetArea(oPC);
    vector vPos = GetPosition(oPC);
    vector vFound = MasonFindWork(oArea, TileXFromPosition(vPos), TileYFromPosition(vPos));
    if (vFound.z < 1.0) return FALSE;

    int nX = FloatToInt(vFound.x);
    int nY = FloatToInt(vFound.y);

    // The saved undo string is already a batch in SetTileJson's format.
    json jBefore = JsonParse(GetLocalString(oArea, MasonUndoVar(nX, nY)));
    if (!TileBatchApply(oArea, jBefore, MasonWorkFlags(oArea, nX, nY))) return FALSE;

    DeleteLocalString(oArea, MasonUndoVar(nX, nY));
    DeleteLocalInt(oArea, MasonRuinedVar(nX, nY));
    return TRUE;
}
