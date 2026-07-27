// Dialog action: raise a 2x2 watchtower where the player is standing.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonRaise(oPC, MASON_KIND_TOWER))
        SendMessageToPC(oPC, "The masons set to work, and a tower rises.");
    else
        SendMessageToPC(oPC, "There is no room for a tower here.");
}
