// Dialog conditional on the greeting: always true, but fills the status token
// (<CUSTOM430>) with what the mason can see from where the player stands.
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
            int nKind = MasonKindAt(oArea, FloatToInt(vFound.x), FloatToInt(vFound.y));
            sStatus = "Your " + MasonStructureName(nKind) + " stands here.";
        }
        else
        {
            json jTiles = TileGroupTiles(oArea, nX, nY, TILE_ROTATE_NONE,
                                         MasonStructureGroup(MASON_KIND_POST));
            if (MasonTilesBlocked(oArea, jTiles))
                sStatus = "There is already work of mine on this ground.";
            else if (!MasonTilesInBounds(oArea, jTiles))
                sStatus = "There is not room enough here.";
            else
                sStatus = "This ground would take a building well enough.";
        }
    }

    SetCustomToken(MASON_TOKEN_STATUS, sStatus);
    return TRUE;
}
