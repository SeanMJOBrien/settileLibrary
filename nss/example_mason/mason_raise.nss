// Dialog action: raise a watchtower on the tile the player is standing on.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonRaiseTower(oPC))
        SendMessageToPC(oPC, "The masons set to work, and a tower rises.");
    else
        SendMessageToPC(oPC, "The masons cannot raise a tower here.");
}
