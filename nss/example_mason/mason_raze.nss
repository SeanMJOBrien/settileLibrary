// Dialog action: dismantle the nearby watchtower, restoring the original ground.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonRazeTower(oPC))
        SendMessageToPC(oPC, "The tower is pulled down and the ground made good.");
    else
        SendMessageToPC(oPC, "There is no tower of mine within reach.");
}
