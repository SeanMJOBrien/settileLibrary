// Dialog action: rebuild the ruined tower whole again.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonSetRuined(oPC, FALSE))
        SendMessageToPC(oPC, "The shell is made good, and the tower stands whole.");
    else
        SendMessageToPC(oPC, "There is no ruin of mine here to rebuild.");
}
