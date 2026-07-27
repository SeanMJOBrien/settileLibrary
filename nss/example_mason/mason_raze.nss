// Dialog action: pull down nearby work, restoring the ground it covered.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonRaze(oPC))
        SendMessageToPC(oPC, "Down it comes, and the ground is made good.");
    else
        SendMessageToPC(oPC, "There is nothing of mine within reach.");
}
