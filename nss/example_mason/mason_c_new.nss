// Dialog conditional: show "raise a tower" only where one could actually go.
#include "inc_mason"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    object oArea = GetArea(oPC);
    if (!MasonCanWorkHere(oArea)) return FALSE;

    vector vPos = GetPosition(oPC);
    int nX = TileXFromPosition(vPos);
    int nY = TileYFromPosition(vPos);

    if (MasonFootprintBlocked(oArea, nX, nY)) return FALSE;
    return TileGroupFits(oArea, nX, nY, TILE_ROTATE_NONE, MasonStructureGroup(FALSE));
}
