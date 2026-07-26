// Dialog conditional: show "pull it down" whenever any work of the mason's is
// within reach, whole or ruined.
#include "inc_mason"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    vector vPos = GetPosition(oPC);
    vector vFound = MasonFindWork(GetArea(oPC), TileXFromPosition(vPos), TileYFromPosition(vPos));
    return (vFound.z >= 1.0);
}
