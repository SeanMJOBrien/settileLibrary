#!/usr/bin/env python3
"""Generate the demo module's GFF-JSON sources.

Emits module.ifo.json, tiletest.are.json and tiletest.git.json into an output
directory. build_demo.sh then converts them to GFF, compiles the scripts and
packs the .mod.

The area is generated rather than committed because it is a uniform fill: 100
copies of one flat tile. Which tile is not arbitrary - it must have all four
corners on the same terrain at the same height and no edge crosser, or it will
not tile cleanly against itself. tcn01's TILE0 is exactly that trap (three
corners at height 1, one at 0). Tile 44 (tcn01_o01_01) is flat cobble, belongs to
no group, and has no doors or sounds; re-derive the choice any time with:

    python3 tools/set_analyze.py <tcn01.set> fill

Usage:
    python3 make_demo.py <output-dir> [path/to/mason.utc.json]
"""

import base64
import json
import os
import sys

# --- Layout -----------------------------------------------------------------
# Tiles are 10m square and a tile's centre is at (x*10+5, y*10+5). y=0 is south.

TILESET = "tcn01"
FILL_TILE = 44                  # flat cobble, in no group - see the docstring
AREA_WIDTH = 10
AREA_HEIGHT = 10
AREA_RESREF = "tiletest"
AREA_TAG = "TileTest"
AREA_NAME = "The Mason's Yard"

ENTRY_TILE = (1, 1)
MASON_TILE = (1, 4)
LEVER_TILE = (5, 2)

MODULE_NAME = "SetTile Library Demo"
MODULE_TAG = "settiledemo"


def tile_centre(tile):
    return (tile[0] * 10.0 + 5.0, tile[1] * 10.0 + 5.0)


# --- GFF-JSON helpers -------------------------------------------------------

def f(kind, value):
    return {"type": kind, "value": value}


def loc(text):
    return {"type": "cexolocstring", "value": {"0": text}}


# --- Area -------------------------------------------------------------------

def make_area():
    tiles = []
    for _ in range(AREA_WIDTH * AREA_HEIGHT):
        tiles.append({
            "__struct_id": 1,
            "Tile_ID": f("int", FILL_TILE),
            "Tile_Orientation": f("int", 0),
            "Tile_Height": f("int", 0),
            "Tile_MainLight1": f("byte", 0),
            "Tile_MainLight2": f("byte", 0),
            "Tile_SrcLight1": f("byte", 0),
            "Tile_SrcLight2": f("byte", 0),
            "Tile_AnimLoop1": f("byte", 1),
            "Tile_AnimLoop2": f("byte", 1),
            "Tile_AnimLoop3": f("byte", 1),
        })

    return {
        "__data_type": "ARE ",
        "ChanceLightning": f("int", 0),
        "ChanceRain": f("int", 0),
        "ChanceSnow": f("int", 0),
        "Comments": f("cexostring", ""),
        "Creator_ID": f("int", -1),
        "DayNightCycle": f("byte", 1),
        "Expansion_List": f("list", []),
        # 0 = exterior, not natural, not underground. A city street.
        "Flags": f("dword", 0),
        "FogClipDist": f("float", 45.0),
        "Height": f("int", AREA_HEIGHT),
        "ID": f("int", -1),
        "IsNight": f("byte", 0),
        "LightingScheme": f("byte", 0),
        "LoadScreenID": f("word", 0),
        "ModListenCheck": f("int", 0),
        "ModSpotCheck": f("int", 0),
        "MoonAmbientColor": f("dword", 0),
        "MoonDiffuseColor": f("dword", 5066061),
        "MoonFogAmount": f("byte", 0),
        "MoonFogColor": f("dword", 0),
        "MoonShadows": f("byte", 0),
        "Name": loc(AREA_NAME),
        "NoRest": f("byte", 0),
        "OnEnter": f("resref", ""),
        "OnExit": f("resref", ""),
        "OnHeartbeat": f("resref", ""),
        "OnUserDefined": f("resref", ""),
        "PlayerVsPlayer": f("byte", 3),
        "ResRef": f("resref", AREA_RESREF),
        "ShadowOpacity": f("byte", 30),
        "SkyBox": f("byte", 0),
        "SunAmbientColor": f("dword", 5261637),
        "SunDiffuseColor": f("dword", 9676456),
        "SunFogAmount": f("byte", 0),
        "SunFogColor": f("dword", 8026746),
        "SunShadows": f("byte", 0),
        "Tag": f("cexostring", AREA_TAG),
        "TileBrdrDisabled": f("byte", 0),
        "Tile_List": f("list", tiles),
        "Tileset": f("resref", TILESET),
        "Version": f("dword", 39),
        "Width": f("int", AREA_WIDTH),
        "WindPower": f("int", 0),
    }


# --- Instances --------------------------------------------------------------

def make_lever(tile):
    """A floor lever wired to tile_demo's OnUsed.

    Instances in a .git carry the whole blueprint, so the demo needs no .utp.
    """
    x, y = tile_centre(tile)
    return {
        "__struct_id": 9,
        "AnimationState": f("byte", 0),
        "Appearance": f("dword", 22),          # placeables.2da row 22, FlrLever1
        "AutoRemoveKey": f("byte", 0),
        "Bearing": f("float", 0.0),
        "BodyBag": f("byte", 0),
        "CloseLockDC": f("byte", 0),
        "Conversation": f("resref", ""),
        "CurrentHP": f("short", 15),
        "Description": loc(""),
        "DisarmDC": f("byte", 15),
        "Faction": f("dword", 0),
        "Fort": f("byte", 0),
        "HP": f("short", 15),
        "Hardness": f("byte", 5),
        "HasInventory": f("byte", 0),
        "Interruptable": f("byte", 1),
        "KeyName": f("cexostring", ""),
        "KeyRequired": f("byte", 0),
        "LocName": loc("Demo Lever"),
        "Lockable": f("byte", 0),
        "Locked": f("byte", 0),
        "OnClick": f("resref", ""),
        "OnClosed": f("resref", ""),
        "OnDamaged": f("resref", ""),
        "OnDeath": f("resref", ""),
        "OnDisarm": f("resref", ""),
        "OnHeartbeat": f("resref", ""),
        "OnInvDisturbed": f("resref", ""),
        "OnLock": f("resref", ""),
        "OnMeleeAttacked": f("resref", ""),
        "OnOpen": f("resref", ""),
        "OnSpellCastAt": f("resref", ""),
        "OnTrapTriggered": f("resref", ""),
        "OnUnlock": f("resref", ""),
        "OnUsed": f("resref", "tile_demo"),
        "OnUserDefined": f("resref", ""),
        "OpenLockDC": f("byte", 0),
        "Plot": f("byte", 1),
        "PortraitId": f("word", 0),
        "Ref": f("byte", 0),
        "Static": f("byte", 0),
        "Tag": f("cexostring", "demo_lever"),
        "TemplateResRef": f("resref", "demo_lever"),
        "TrapDetectDC": f("byte", 0),
        "TrapDetectable": f("byte", 1),
        "TrapDisarmable": f("byte", 1),
        "TrapFlag": f("byte", 0),
        "TrapOneShot": f("byte", 1),
        "TrapType": f("byte", 0),
        "Type": f("byte", 0),
        "Useable": f("byte", 1),
        "Will": f("byte", 0),
        "X": f("float", x),
        "Y": f("float", y),
        "Z": f("float", 0.0),
    }


def make_mason_instance(utc_path, tile):
    """The mason NPC, built from the shipped blueprint plus a position.

    Creature instances use XPosition/YPosition/ZPosition and XOrientation/
    YOrientation - not the X/Y/Z that placeables use.
    """
    with open(utc_path) as handle:
        creature = json.load(handle)

    creature.pop("__data_type", None)
    creature["__struct_id"] = 4

    x, y = tile_centre(tile)
    creature["XPosition"] = f("float", x)
    creature["YPosition"] = f("float", y)
    creature["ZPosition"] = f("float", 0.0)
    creature["XOrientation"] = f("float", 0.0)
    creature["YOrientation"] = f("float", -1.0)   # facing south, towards entry
    return creature


def make_git(utc_path):
    return {
        "__data_type": "GIT ",
        "AreaProperties": {
            "__struct_id": 100, "type": "struct",
            "value": {
                "__struct_id": 100,
                "AmbientSndDay": f("int", 1),
                "AmbientSndDayVol": f("int", 20),
                "AmbientSndNight": f("int", 1),
                "AmbientSndNitVol": f("int", 20),
                "EnvAudio": f("int", 0),
                "MusicBattle": f("int", 0),
                "MusicDay": f("int", 0),
                "MusicDelay": f("int", 0),
                "MusicNight": f("int", 0),
            },
        },
        "Creature List": f("list", [make_mason_instance(utc_path, MASON_TILE)]),
        "Door List": f("list", []),
        "Encounter List": f("list", []),
        "List": f("list", []),
        "Placeable List": f("list", [make_lever(LEVER_TILE)]),
        "SoundList": f("list", []),
        "StoreList": f("list", []),
        "TriggerList": f("list", []),
        "WaypointList": f("list", []),
    }


# --- Module -----------------------------------------------------------------

def make_ifo():
    entry_x, entry_y = tile_centre(ENTRY_TILE)
    return {
        "__data_type": "IFO ",
        "Expansion_Pack": f("word", 0),
        "Mod_Area_list": f("list", [
            {"__struct_id": 6, "Area_Name": f("resref", AREA_RESREF)}]),
        "Mod_Creator_ID": f("int", -1),
        "Mod_CustomTlk": f("cexostring", ""),
        "Mod_CutSceneList": f("list", []),
        "Mod_DawnHour": f("byte", 6),
        "Mod_DefaultBic": f("resref", ""),
        "Mod_Description": loc(
            "Test yard for the SetTile runtime tile-editing library. "
            "Talk to Master Mason to raise buildings; pull the lever to run "
            "the builder demo."),
        "Mod_DuskHour": f("byte", 19),
        "Mod_Entry_Area": f("resref", AREA_RESREF),
        "Mod_Entry_Dir_X": f("float", 0.0),
        "Mod_Entry_Dir_Y": f("float", 1.0),
        "Mod_Entry_X": f("float", entry_x),
        "Mod_Entry_Y": f("float", entry_y),
        "Mod_Entry_Z": f("float", 0.0),
        "Mod_Expan_List": f("list", []),
        "Mod_GVar_List": f("list", []),
        "Mod_HakList": f("list", []),
        "Mod_ID": {"type": "void", "value64": base64.b64encode(os.urandom(16)).decode()},
        "Mod_IsSaveGame": f("byte", 0),
        "Mod_MinGameVer": f("cexostring", "1.88"),
        "Mod_MinPerHour": f("byte", 2),
        "Mod_Name": loc(MODULE_NAME),
        "Mod_OnAcquirItem": f("resref", ""),
        "Mod_OnActvtItem": f("resref", ""),
        "Mod_OnClientEntr": f("resref", ""),
        "Mod_OnClientLeav": f("resref", ""),
        "Mod_OnCutsnAbort": f("resref", ""),
        "Mod_OnHeartbeat": f("resref", ""),
        "Mod_OnModLoad": f("resref", ""),
        "Mod_OnModStart": f("resref", ""),
        "Mod_OnNuiEvent": f("resref", ""),
        "Mod_OnPlrChat": f("resref", ""),
        "Mod_OnPlrDeath": f("resref", ""),
        "Mod_OnPlrDying": f("resref", ""),
        "Mod_OnPlrEqItm": f("resref", ""),
        "Mod_OnPlrGuiEvt": f("resref", ""),
        "Mod_OnPlrLvlUp": f("resref", ""),
        "Mod_OnPlrRest": f("resref", ""),
        "Mod_OnPlrTarget": f("resref", ""),
        "Mod_OnPlrTileAct": f("resref", ""),
        "Mod_OnPlrUnEqItm": f("resref", ""),
        "Mod_OnSpawnBtnDn": f("resref", ""),
        "Mod_OnUnAqreItem": f("resref", ""),
        "Mod_OnUsrDefined": f("resref", ""),
        "Mod_PartyControl": f("int", 0),
        "Mod_StartDay": f("byte", 1),
        "Mod_StartHour": f("byte", 13),
        "Mod_StartMonth": f("byte", 6),
        "Mod_StartMovie": f("resref", ""),
        "Mod_StartYear": f("dword", 1372),
        "Mod_Tag": f("cexostring", MODULE_TAG),
        "Mod_UUID": f("cexostring", ""),
        "Mod_Version": f("dword", 3),
        "Mod_XPScale": f("byte", 10),
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    out = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    utc = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, os.pardir,
                                                             "utc", "mason.utc.json")
    os.makedirs(out, exist_ok=True)

    written = [
        ("module.ifo.json", make_ifo()),
        ("%s.are.json" % AREA_RESREF, make_area()),
        ("%s.git.json" % AREA_RESREF, make_git(utc)),
    ]
    for name, data in written:
        with open(os.path.join(out, name), "w") as handle:
            json.dump(data, handle, indent=2)
        print("  %s" % name)

    print("  area %dx%d on %s, filled with tile %d"
          % (AREA_WIDTH, AREA_HEIGHT, TILESET, FILL_TILE))
    print("  entry %s, mason %s, lever %s (tile coords)"
          % (ENTRY_TILE, MASON_TILE, LEVER_TILE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
