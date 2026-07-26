// Dialog action: swap the standing tower for its ruined variant.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonSetRuined(oPC, TRUE))
        SendMessageToPC(oPC, "The masons strip the tower back to a shell.");
    else
        SendMessageToPC(oPC, "There is nothing of mine here to ruin.");
}
