// Dialog conditional: only offer to rebuild a tower that is currently a ruin.
#include "inc_mason"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    object oArea = GetArea(oPC);
    vector vPos = GetPosition(oPC);
    vector vFound = MasonFindWork(oArea, TileXFromPosition(vPos), TileYFromPosition(vPos));
    if (vFound.z < 1.0) return FALSE;
    return MasonIsRuined(oArea, FloatToInt(vFound.x), FloatToInt(vFound.y));
}
