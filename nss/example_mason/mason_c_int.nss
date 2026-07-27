// Dialog conditional: only offer to ruin work that HAS a ruined form and is
// currently whole.
#include "inc_mason"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    object oArea = GetArea(oPC);
    vector vPos = GetPosition(oPC);
    vector vFound = MasonFindWork(oArea, TileXFromPosition(vPos), TileYFromPosition(vPos));
    if (vFound.z < 1.0) return FALSE;

    int nKind = MasonKindAt(oArea, FloatToInt(vFound.x), FloatToInt(vFound.y));
    return (MasonRuinOf(nKind) >= 0);
}
