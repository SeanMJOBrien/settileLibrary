// Dialog action: raise a guard post. Two tiles wide and one deep - the example's
// proof that nothing in the mason assumes a square footprint.
#include "inc_mason"

void main()
{
    object oPC = GetPCSpeaker();
    if (MasonRaise(oPC, MASON_KIND_POST))
        SendMessageToPC(oPC, "A guard post goes up, two spans across.");
    else
        SendMessageToPC(oPC, "There is no room for a guard post here.");
}
