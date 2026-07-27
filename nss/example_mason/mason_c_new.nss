// Dialog conditional: offer to build only where the mason can work at all. The
// per-structure fit and collision checks live in the raise actions, because what
// fits depends on which catalogue entry the player picks.
#include "inc_mason"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    object oArea = GetArea(oPC);
    if (!MasonCanWorkHere(oArea)) return FALSE;

    vector vPos = GetPosition(oPC);
    int nX = TileXFromPosition(vPos);
    int nY = TileYFromPosition(vPos);

    // Smallest catalogue entry: if even that cannot go here, offer nothing.
    json jTiles = TileGroupTiles(oArea, nX, nY, TILE_ROTATE_NONE,
                                 MasonStructureGroup(MASON_KIND_POST));
    if (!MasonTilesInBounds(oArea, jTiles)) return FALSE;
    return !MasonTilesBlocked(oArea, jTiles);
}
