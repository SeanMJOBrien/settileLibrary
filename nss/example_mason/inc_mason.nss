// Master Mason - the player-facing half of the runtime tile system.
//
// Backs the mason conversation: a player stands where they want a structure,
// talks to the mason, and the mason raises it, lets a tower fall to ruin,
// rebuilds it, or pulls it down - all by editing the area's tiles through
// inc_tile.
//
// NOTHING HERE ASSUMES A SIZE OR SHAPE
//
// The catalogue below mixes a 2x2 tower with a 2x1 guard post on purpose. A
// tileset's features are all sorts of shapes - in stock tcn01 the non-square ones
// outnumber the square ones, and two features are not even solid rectangles (a
// .set can leave holes in a feature's bounding box). So this example never stores
// a width and height and never reasons about a bounding box. Instead it asks
// TileGroupTiles() for the exact squares a feature covers, rotation included, and
// works from that list:
//
//   - collision      a per-tile occupancy mark, so mixed sizes and holes are exact
//   - reload flags   set only if some covered tile is really on the area edge
//   - step clear     the first in-bounds tile that the feature does NOT cover
//
// Copy that pattern rather than a MASON_SIZE constant.
//
// State lives in local variables on the AREA, keyed by tile, so several
// structures of different shapes coexist:
//     mason_undo_<x>_<y>   tiles that were there before, as a batch dump
//     mason_kind_<x>_<y>   which catalogue entry stands here, +1 (0 = none)
//     mason_occ_<x>_<y>    set on every square a structure covers
// The undo string doubling as "something of mine has its origin here" is why
// razing clears it.
//
// Tile edits are runtime-only - the engine never writes them back to the .are -
// so everything raised here is gone after a reset. See TILES.md.
//
// WHY THERE IS NO "TURN IT" OPTION
//
// The tiles of a tileset structure are one distinct model per position (tcn01's
// tower is u01/u02/v01/v02). Rotating a tile only spins that quadrant's own model,
// so rearranging them and bumping their orientations scrambles the structure
// rather than turning it. TileBlockRotate is a terrain tool. Swapping in a
// differently-authored feature, as ruin/rebuild does, is the honest equivalent.

#include "inc_tile"

// The tileset these tile IDs were read from. A tile ID is meaningless outside its
// own tileset, so the mason refuses to work anywhere else - without this check,
// building in the wrong area silently produces garbage terrain. To retheme, rerun
// tools/set_analyze.py on your tileset and replace the catalogue.
const string MASON_TILESET = "tcn01"; // City Exterior, stock NWN

// Catalogue entries. MASON_KIND_RUIN is the ruined form of MASON_KIND_TOWER and
// shares its footprint, which is what lets one be swapped for the other.
const int MASON_KIND_TOWER = 0;
const int MASON_KIND_RUIN  = 1;
const int MASON_KIND_POST  = 2;

// How far from the player the mason will look for his own work.
const int MASON_SEARCH_RANGE = 4;

const string MASON_VAR_UNDO = "mason_undo_";
const string MASON_VAR_KIND = "mason_kind_";
const string MASON_VAR_OCCUPIED = "mason_occ_";

// Dialog token carrying the mason's status line.
const int MASON_TOKEN_STATUS = 430;

// --- Prototypes ---

// A catalogue entry as a group, origin at its south-west square. Tile IDs and
// offsets came from tools/set_groups.py against tcn01.set.
json MasonStructureGroup(int nKind);

// Display name, and whether an entry has a ruined / whole counterpart.
string MasonStructureName(int nKind);
int MasonRuinOf(int nKind);      // kind it becomes when ruined, or -1
int MasonWholeOf(int nKind);     // kind it becomes when rebuilt, or -1

string MasonUndoVar(int nX, int nY);
string MasonKindVar(int nX, int nY);
string MasonOccupiedVar(int nX, int nY);

// TRUE if a structure has its ORIGIN on this exact square.
int MasonHasWorkAt(object oArea, int nX, int nY);

// Which catalogue entry has its origin here, or -1.
int MasonKindAt(object oArea, int nX, int nY);

// Nearest origin within MASON_SEARCH_RANGE of (nX,nY). Returns .z = 1.0 when one
// was found, with .x/.y holding its origin square.
vector MasonFindWork(object oArea, int nX, int nY);

// TRUE if oArea is built on the tileset the catalogue's tile IDs come from.
int MasonCanWorkHere(object oArea);

// --- All of these take a tile list from TileGroupTiles, never a size ---

// TRUE if every square is inside the area.
int MasonTilesInBounds(object oArea, json jTiles);

// TRUE if any square is already covered by existing work.
int MasonTilesBlocked(object oArea, json jTiles);

// Reload flags for work covering these squares.
int MasonTilesFlags(object oArea, json jTiles);

// Mark / unmark every square as covered.
void MasonOccupy(object oArea, json jTiles, int bOccupied);

// Move oPC to the nearest in-bounds square the work does NOT cover. A square that
// stops being walkable strands whoever stands on it, and structure tiles are
// solid. The jump is queued on oPC's action queue, so it lands the moment the
// calling script yields - just after the tiles change, not before.
void MasonStepClear(object oPC, json jTiles);

// --- The operations the conversation can ask for ---

int MasonRaise(object oPC, int nKind);
int MasonSetRuined(object oPC, int bRuined);
int MasonRaze(object oPC);

// --- Catalogue ---

json MasonStructureGroup(int nKind)
{
    json jGroup = TileGroup();

    if (nKind == MASON_KIND_TOWER)
    {
        // GROUP68 CloakTower_2x2 - 2x2
        jGroup = TileGroupAdd(jGroup, 0, 0, 277, 0);   // tcn01_u01_01
        jGroup = TileGroupAdd(jGroup, 1, 0, 283, 0);   // tcn01_v01_01
        jGroup = TileGroupAdd(jGroup, 0, 1, 282, 0);   // tcn01_u02_01
        jGroup = TileGroupAdd(jGroup, 1, 1, 284, 0);   // tcn01_v02_01
    }
    else if (nKind == MASON_KIND_RUIN)
    {
        // GROUP76 RuinedTower_2x2 - 2x2, same footprint as the tower
        jGroup = TileGroupAdd(jGroup, 0, 0, 300, 0);   // tcn01_s15_01
        jGroup = TileGroupAdd(jGroup, 1, 0, 302, 0);   // tcn01_t15_01
        jGroup = TileGroupAdd(jGroup, 0, 1, 301, 0);   // tcn01_s16_01
        jGroup = TileGroupAdd(jGroup, 1, 1, 303, 0);   // tcn01_t16_01
    }
    else if (nKind == MASON_KIND_POST)
    {
        // GROUP38 GuardTower_1x2 - actually 2 columns x 1 row. The name says
        // 1x2; group names are unreliable, Rows/Columns is what counts.
        jGroup = TileGroupAdd(jGroup, 0, 0, 135, 0);   // tcn01_s18_01
        jGroup = TileGroupAdd(jGroup, 1, 0, 136, 0);   // tcn01_t18_01
    }
    return jGroup;
}

string MasonStructureName(int nKind)
{
    if (nKind == MASON_KIND_TOWER) return "watchtower";
    if (nKind == MASON_KIND_RUIN)  return "ruined tower";
    if (nKind == MASON_KIND_POST)  return "guard post";
    return "";
}

int MasonRuinOf(int nKind)
{
    if (nKind == MASON_KIND_TOWER) return MASON_KIND_RUIN;
    return -1;
}

int MasonWholeOf(int nKind)
{
    if (nKind == MASON_KIND_RUIN) return MASON_KIND_TOWER;
    return -1;
}

// --- State ---

string MasonUndoVar(int nX, int nY)
{
    return MASON_VAR_UNDO + IntToString(nX) + "_" + IntToString(nY);
}

string MasonKindVar(int nX, int nY)
{
    return MASON_VAR_KIND + IntToString(nX) + "_" + IntToString(nY);
}

string MasonOccupiedVar(int nX, int nY)
{
    return MASON_VAR_OCCUPIED + IntToString(nX) + "_" + IntToString(nY);
}

int MasonHasWorkAt(object oArea, int nX, int nY)
{
    return (GetLocalString(oArea, MasonUndoVar(nX, nY)) != "");
}

int MasonKindAt(object oArea, int nX, int nY)
{
    return GetLocalInt(oArea, MasonKindVar(nX, nY)) - 1;
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

int MasonCanWorkHere(object oArea)
{
    if (!GetIsObjectValid(oArea)) return FALSE;
    return (GetTilesetResRef(oArea) == MASON_TILESET);
}

// --- Tile-list helpers: shape-agnostic by construction ---

int MasonTilesInBounds(object oArea, json jTiles)
{
    int nCount = TileListCount(jTiles);
    if (nCount < 1) return FALSE;

    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        if (!TileInBounds(oArea, TileListX(jTiles, nIndex), TileListY(jTiles, nIndex)))
            return FALSE;
    }
    return TRUE;
}

int MasonTilesBlocked(object oArea, json jTiles)
{
    int nCount = TileListCount(jTiles);
    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        if (GetLocalInt(oArea, MasonOccupiedVar(TileListX(jTiles, nIndex),
                                                TileListY(jTiles, nIndex))))
            return TRUE;
    }
    return FALSE;
}

int MasonTilesFlags(object oArea, json jTiles)
{
    int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING | SETTILE_FLAG_RELOAD_GRASS;

    int nCount = TileListCount(jTiles);
    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        // The outer border only needs reloading if the work reaches the map edge.
        if (TileIsOnEdge(oArea, TileListX(jTiles, nIndex), TileListY(jTiles, nIndex)))
            return nFlags | SETTILE_FLAG_RELOAD_BORDER;
    }
    return nFlags;
}

void MasonOccupy(object oArea, json jTiles, int bOccupied)
{
    int nCount = TileListCount(jTiles);
    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        string sVar = MasonOccupiedVar(TileListX(jTiles, nIndex), TileListY(jTiles, nIndex));
        if (bOccupied) SetLocalInt(oArea, sVar, TRUE);
        else           DeleteLocalInt(oArea, sVar);
    }
}

void MasonStepClear(object oPC, json jTiles)
{
    object oArea = GetArea(oPC);
    int nCount = TileListCount(jTiles);
    if (nCount < 1) return;

    // Ring outwards from the first covered square until a square turns up that is
    // in bounds and not part of the work. Driven by the real tile list, so it is
    // correct for a non-square or holed footprint.
    int nRadius;
    for (nRadius = 1; nRadius <= 4; nRadius++)
    {
        int nOffsetY;
        for (nOffsetY = -nRadius; nOffsetY <= nRadius; nOffsetY++)
        {
            int nOffsetX;
            for (nOffsetX = -nRadius; nOffsetX <= nRadius; nOffsetX++)
            {
                int nTileX = TileListX(jTiles, 0) + nOffsetX;
                int nTileY = TileListY(jTiles, 0) + nOffsetY;
                if (!TileInBounds(oArea, nTileX, nTileY)) continue;
                if (GetLocalInt(oArea, MasonOccupiedVar(nTileX, nTileY))) continue;

                int nIndex;
                int bCovered = FALSE;
                for (nIndex = 0; nIndex < nCount; nIndex++)
                {
                    if ((TileListX(jTiles, nIndex) == nTileX) &&
                        (TileListY(jTiles, nIndex) == nTileY))
                    {
                        bCovered = TRUE;
                        break;
                    }
                }
                if (bCovered) continue;

                // Unlike the tile functions, JumpToLocation wants a world position.
                location lSafe = Location(oArea, TileWorldCenter(nTileX, nTileY), GetFacing(oPC));
                AssignCommand(oPC, ClearAllActions());
                AssignCommand(oPC, JumpToLocation(lSafe));
                return;
            }
        }
    }
}

// --- Operations ---

int MasonRaise(object oPC, int nKind)
{
    object oArea = GetArea(oPC);
    if (!MasonCanWorkHere(oArea)) return FALSE;
    if (MasonStructureName(nKind) == "") return FALSE;

    vector vPos = GetPosition(oPC);
    int nX = TileXFromPosition(vPos);
    int nY = TileYFromPosition(vPos);

    json jGroup = MasonStructureGroup(nKind);
    json jTiles = TileGroupTiles(oArea, nX, nY, TILE_ROTATE_NONE, jGroup);
    if (!MasonTilesInBounds(oArea, jTiles)) return FALSE;
    if (MasonTilesBlocked(oArea, jTiles)) return FALSE;

    // Capture the ground before overwriting it, so razing can put it back.
    json jBefore = TileSnapshotGroup(oArea, nX, nY, TILE_ROTATE_NONE, jGroup);

    MasonStepClear(oPC, jTiles);

    if (!TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, jGroup,
                        MasonTilesFlags(oArea, jTiles)))
        return FALSE;

    SetLocalString(oArea, MasonUndoVar(nX, nY), JsonDump(jBefore));
    SetLocalInt(oArea, MasonKindVar(nX, nY), nKind + 1);
    MasonOccupy(oArea, jTiles, TRUE);
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
    int nKind = MasonKindAt(oArea, nX, nY);
    int nWanted = bRuined ? MasonRuinOf(nKind) : MasonWholeOf(nKind);
    if (nWanted < 0) return FALSE;

    // The two forms share a footprint, so the snapshot taken when it was raised
    // still describes the ground underneath and occupancy does not change.
    json jGroup = MasonStructureGroup(nWanted);
    json jTiles = TileGroupTiles(oArea, nX, nY, TILE_ROTATE_NONE, jGroup);

    MasonStepClear(oPC, jTiles);
    if (!TileGroupStamp(oArea, nX, nY, TILE_ROTATE_NONE, jGroup,
                        MasonTilesFlags(oArea, jTiles)))
        return FALSE;

    SetLocalInt(oArea, MasonKindVar(nX, nY), nWanted + 1);
    return TRUE;
}

int MasonRaze(object oPC)
{
    object oArea = GetArea(oPC);
    vector vPos = GetPosition(oPC);
    vector vFound = MasonFindWork(oArea, TileXFromPosition(vPos), TileYFromPosition(vPos));
    if (vFound.z < 1.0) return FALSE;

    int nX = FloatToInt(vFound.x);
    int nY = FloatToInt(vFound.y);
    int nKind = MasonKindAt(oArea, nX, nY);
    if (nKind < 0) return FALSE;

    // Clear occupancy from the squares this entry actually covers, whatever shape
    // that is - not from an assumed box.
    json jTiles = TileGroupTiles(oArea, nX, nY, TILE_ROTATE_NONE,
                                 MasonStructureGroup(nKind));

    // The saved undo string is already a batch in SetTileJson's format.
    json jBefore = JsonParse(GetLocalString(oArea, MasonUndoVar(nX, nY)));
    if (!TileBatchApply(oArea, jBefore, MasonTilesFlags(oArea, jTiles))) return FALSE;

    MasonOccupy(oArea, jTiles, FALSE);
    DeleteLocalString(oArea, MasonUndoVar(nX, nY));
    DeleteLocalInt(oArea, MasonKindVar(nX, nY));
    return TRUE;
}
