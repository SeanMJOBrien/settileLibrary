// Dialog conditional on the mason's greeting: always true, but fills the status
// token (<CUSTOM430>) with what the mason can see from where the player stands.
#include "inc_mason"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    object oArea = GetArea(oPC);
    vector vPos = GetPosition(oPC);
    int nX = TileXFromPosition(vPos);
    int nY = TileYFromPosition(vPos);

    string sStatus;
    if (!MasonCanWorkHere(oArea))
    {
        sStatus = "This is no ground for my craft.";
    }
    else
    {
        vector vFound = MasonFindWork(oArea, nX, nY);
        if (vFound.z >= 1.0)
        {
            if (MasonIsRuined(oArea, FloatToInt(vFound.x), FloatToInt(vFound.y)))
                sStatus = "Your tower stands here, a shell of itself.";
            else
                sStatus = "Your tower stands here, whole and sound.";
        }
        else if (MasonFootprintBlocked(oArea, nX, nY))
            sStatus = "There is already work of mine too close by.";
        else if (!TileGroupFits(oArea, nX, nY, TILE_ROTATE_NONE, MasonStructureGroup(FALSE)))
            sStatus = "There is not room enough here.";
        else
            sStatus = "This ground would take a tower well enough.";
    }

    SetCustomToken(MASON_TOKEN_STATUS, sStatus);
    return TRUE;
}
