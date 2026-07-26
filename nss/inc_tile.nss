// Runtime tile editing for area tilesets.
//
// Wraps the NWN:EE engine tile functions (SetTile / SetTileJson / GetTileID /
// GetTileOrientation / GetTileHeight) so scripts can retexture terrain at
// runtime: swap a single tile, stamp a multi-tile structure with a chosen
// facing, rotate a block of tiles, or snapshot tiles and put them back.
//
// Include with:
//     #include "inc_tile"
//
// No dependencies beyond nwscript, and no tie to any persistence layer -
// callers that want tile edits to survive a reset must store the snapshot JSON
// themselves.
//
// THE COORDINATE GOTCHA
//
// The location taken by SetTile/GetTileID is NOT a world position. Only its
// area, x and y are read, and x/y are the TILE INDEX: x runs 0 ..
// GetAreaSize(AREA_WIDTH) - 1 and y runs 0 .. GetAreaSize(AREA_HEIGHT) - 1,
// with y = 0 along the south edge. z and facing are ignored. Passing a real
// world position (e.g. GetLocation(oPC) straight through, or tile * 10.0) edits
// a tile ten times too far out, or nothing at all. Build these locations only
// with TileLocation(); convert a world position with TileXFromPosition() /
// TileYFromPosition().
//
// The engine's own header is inconsistent here - SetTileMainLightColor documents
// "the vector part of this is the tile grid (x,y) coordinate" while SetTile only
// says "the location of the tile" - but both take grid references.
//
// ORIENTATION
//
// A tile's nOrientation is 0-3, counting 90-degree steps counter-clockwise, and
// this library uses the same units for group/block rotation. Rotating a group of
// tiles means rotating each tile's position AND its own orientation by the same
// number of steps; rotating only the positions leaves walls and edges facing the
// wrong way and is the usual reason a rotated structure looks scrambled.
//
// ENGINE CAVEATS
//
//   - nTileID must exist in the area's own tileset (.set catalog). There is no
//     way to read the .set from script, so tile IDs have to be looked up by hand
//     and are only valid for areas built on that tileset.
//   - Tile changes do not move placeables already sitting on the tile; they can
//     end up floating or buried.
//   - Creatures can get stuck when a walkable tile becomes non-walkable.
//   - Grass and the outer area border only refresh if the matching
//     SETTILE_FLAG_* is passed.

// Mirrors the engine's -1-on-error return from GetTileID/Orientation/Height.
const int TILE_INVALID = -1;

// Rotation amounts, in 90-degree counter-clockwise steps - the same units as a
// tile's nOrientation.
const int TILE_ROTATE_NONE = 0;
const int TILE_ROTATE_90   = 1;
const int TILE_ROTATE_180  = 2;
const int TILE_ROTATE_270  = 3;

// World units along one tile edge. Needed only to map a world position onto a
// tile index, never to build a tile location.
const float TILE_WORLD_SIZE = 10.0;

// Every reload/recompute flag at once. Correct but slow; prefer just the flags
// the edit actually needs.
const int TILE_FLAGS_ALL = 7;

// --- Grid geometry and bounds ---

// Area size in tiles. GetAreaSize already returns tile counts, not world units.
int TileGridWidth(object oArea);
int TileGridHeight(object oArea);

// TRUE if (nX,nY) is a real tile of oArea. Every read and write below funnels
// through this before touching the engine.
int TileInBounds(object oArea, int nX, int nY);

// TRUE if the tile sits on the area's outer edge, i.e. editing it wants
// SETTILE_FLAG_RELOAD_BORDER.
int TileIsOnEdge(object oArea, int nX, int nY);

// Grid reference for the engine tile functions. See the coordinate note above -
// the vector holds the tile index, not a world position.
location TileLocation(object oArea, int nX, int nY);

// Tile index as used by SetTileJson: row-major from the south-west corner, so a
// 3x3 area indexes 0,1,2 along the south row and 6,7,8 along the north row.
int TileIndex(object oArea, int nX, int nY);

// World-space centre of a tile, for jumping a creature or placing an object onto
// it once the tile has been changed.
vector TileWorldCenter(int nX, int nY);

// The tile a world position falls inside.
int TileXFromPosition(vector vPos);
int TileYFromPosition(vector vPos);

// Round a world facing in degrees (as GetFacing returns) to the nearest
// 90-degree rotation step, 0-3.
int TileRotationFromFacing(float fFacing);

// Add nSteps 90-degree counter-clockwise steps to a tile orientation, wrapping
// to 0-3. Also the canonical way to normalise an arbitrary int to 0-3.
int TileRotateOrientation(int nOrientation, int nSteps);

// --- Single tile ---

// Current tile ID / orientation / height, or TILE_INVALID out of bounds.
int GetTileIDAt(object oArea, int nX, int nY);
int GetTileOrientationAt(object oArea, int nX, int nY);
int GetTileHeightAt(object oArea, int nX, int nY);

// Change one tile. Returns FALSE and writes nothing if the tile is out of
// bounds. For more than a couple of tiles, batch instead - see TileBatchAdd.
int SetTileAt(object oArea, int nX, int nY, int nTileID, int nOrientation, int nHeight = 0, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);

// --- Batched edits ---
//
// A batch is a JSON array in SetTileJson's own format, so many tiles change in
// one engine call and one update to the clients in the area. Because a batch is
// built entirely before anything is written, reads taken while building it are
// never disturbed by the batch's own writes.
//
// The Json*Inplace helpers mutate a copy when the value is passed into a
// function, so always assign the result: jBatch = TileBatchAdd(jBatch, ...).

// Start an empty batch.
json TileBatch();

// Queue one absolute tile into a batch. Out-of-bounds tiles are dropped.
json TileBatchAdd(json jBatch, object oArea, int nX, int nY, int nTileID, int nOrientation, int nHeight = 0);

// Number of tiles queued.
int TileBatchCount(json jBatch);

// Apply a batch. Returns FALSE if the area is invalid or the batch is empty.
int TileBatchApply(object oArea, json jBatch, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);

// --- Groups (multi-tile structures) ---
//
// A group describes a structure in its own unrotated local frame as offsets from
// an origin tile, so the same group can be stamped anywhere at any facing. Build
// it once with TileGroupAdd, then stamp it with TileGroupStamp.

// Start an empty group.
json TileGroup();

// Add one tile to a group. Offsets and orientation are in the group's own
// unrotated frame; +nOffsetY is north.
json TileGroupAdd(json jGroup, int nOffsetX, int nOffsetY, int nTileID, int nOrientation, int nHeight = 0);

// Number of tiles in a group.
int TileGroupCount(json jGroup);

// TRUE if every tile the group would touch, after rotating by nRotation, is in
// bounds. Reads nothing and writes nothing.
int TileGroupFits(object oArea, int nOriginX, int nOriginY, int nRotation, json jGroup);

// Stamp a group at (nOriginX,nOriginY) rotated by nRotation steps. All-or-
// nothing: if any tile would fall outside the area nothing is written and it
// returns FALSE, so a structure never ends up half-stamped across the map edge.
int TileGroupStamp(object oArea, int nOriginX, int nOriginY, int nRotation, json jGroup, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);

// Stamp a group using a location for the origin tile and its facing for the
// rotation - convenient for a DM wand or a placeable acting as an anchor.
int TileGroupStampAtLocation(location lOrigin, json jGroup, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);

// --- Snapshot and restore ---

// Capture the current state of a rectangle of tiles as a batch. Apply it later
// with TileBatchApply to undo whatever was stamped over it. Out-of-bounds tiles
// are skipped, so the result can be narrower than requested.
json TileSnapshotRect(object oArea, int nX, int nY, int nWidth, int nHeight);

// Capture exactly the tiles a group would overwrite. Take this BEFORE stamping.
json TileSnapshotGroup(object oArea, int nOriginX, int nOriginY, int nRotation, json jGroup);

// --- Rotating tiles already in the area ---

// Rotate a square block of nSize x nSize tiles in place by nRotation steps.
// Square only: rotating a W x H block 90 degrees produces an H x W block, which
// cannot be written back over the original footprint. Use TileBlockRotate180 for
// a rectangle. Returns FALSE if the block is not fully in bounds.
int TileBlockRotate(object oArea, int nX, int nY, int nSize, int nRotation, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);

// Rotate a rectangle 180 degrees in place. Shape is preserved at 180 degrees, so
// unlike TileBlockRotate this works for non-square blocks.
int TileBlockRotate180(object oArea, int nX, int nY, int nWidth, int nHeight, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING);

// --- Private helpers ---

int _TileRotatedOffsetX(int nOffsetX, int nOffsetY, int nSteps);
int _TileRotatedOffsetY(int nOffsetX, int nOffsetY, int nSteps);
int _TileGroupFieldAt(json jGroup, int nIndex, string sKey);

// --- Grid geometry and bounds ---

int TileGridWidth(object oArea)
{
    return GetAreaSize(AREA_WIDTH, oArea);
}

int TileGridHeight(object oArea)
{
    return GetAreaSize(AREA_HEIGHT, oArea);
}

int TileInBounds(object oArea, int nX, int nY)
{
    if (!GetIsObjectValid(oArea)) return FALSE;
    if ((nX < 0) || (nY < 0)) return FALSE;
    return ((nX < TileGridWidth(oArea)) && (nY < TileGridHeight(oArea)));
}

int TileIsOnEdge(object oArea, int nX, int nY)
{
    if (!TileInBounds(oArea, nX, nY)) return FALSE;
    return ((nX == 0) || (nY == 0) ||
            (nX == TileGridWidth(oArea) - 1) ||
            (nY == TileGridHeight(oArea) - 1));
}

location TileLocation(object oArea, int nX, int nY)
{
    return Location(oArea, Vector(IntToFloat(nX), IntToFloat(nY), 0.0), 0.0);
}

int TileIndex(object oArea, int nX, int nY)
{
    return (nY * TileGridWidth(oArea)) + nX;
}

vector TileWorldCenter(int nX, int nY)
{
    float fHalf = TILE_WORLD_SIZE / 2.0;
    return Vector((IntToFloat(nX) * TILE_WORLD_SIZE) + fHalf,
                  (IntToFloat(nY) * TILE_WORLD_SIZE) + fHalf,
                  0.0);
}

int TileXFromPosition(vector vPos)
{
    return FloatToInt(vPos.x / TILE_WORLD_SIZE);
}

int TileYFromPosition(vector vPos)
{
    return FloatToInt(vPos.y / TILE_WORLD_SIZE);
}

int TileRotationFromFacing(float fFacing)
{
    return TileRotateOrientation(FloatToInt((fFacing / 90.0) + 0.5), 0);
}

int TileRotateOrientation(int nOrientation, int nSteps)
{
    int nResult = (nOrientation + nSteps) % 4;
    if (nResult < 0) nResult += 4;
    return nResult;
}

// --- Single tile ---

int GetTileIDAt(object oArea, int nX, int nY)
{
    if (!TileInBounds(oArea, nX, nY)) return TILE_INVALID;
    return GetTileID(TileLocation(oArea, nX, nY));
}

int GetTileOrientationAt(object oArea, int nX, int nY)
{
    if (!TileInBounds(oArea, nX, nY)) return TILE_INVALID;
    return GetTileOrientation(TileLocation(oArea, nX, nY));
}

int GetTileHeightAt(object oArea, int nX, int nY)
{
    if (!TileInBounds(oArea, nX, nY)) return TILE_INVALID;
    return GetTileHeight(TileLocation(oArea, nX, nY));
}

// A negative tile ID is never a tile. It is what a .set uses inside a group to
// mark a square of the bounding box that is NOT part of the feature - a hole, as
// in tcn01's Merchant_Docked, meaning "leave whatever is already there". Since
// tile IDs get transcribed out of .set files by hand, all three write paths drop
// negatives instead of handing them to the engine.
int SetTileAt(object oArea, int nX, int nY, int nTileID, int nOrientation, int nHeight = 0, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING)
{
    if (nTileID < 0) return FALSE;
    if (!TileInBounds(oArea, nX, nY)) return FALSE;
    SetTile(TileLocation(oArea, nX, nY), nTileID,
            TileRotateOrientation(nOrientation, 0), nHeight, nFlags);
    return TRUE;
}

// --- Batched edits ---

json TileBatch()
{
    return JsonArray();
}

json TileBatchAdd(json jBatch, object oArea, int nX, int nY, int nTileID, int nOrientation, int nHeight = 0)
{
    if (nTileID < 0) return jBatch;           // hole - see the note on SetTileAt
    if (!TileInBounds(oArea, nX, nY)) return jBatch;

    json jTile = JsonObject();
    JsonObjectSetInplace(jTile, "index",       JsonInt(TileIndex(oArea, nX, nY)));
    JsonObjectSetInplace(jTile, "tileid",      JsonInt(nTileID));
    JsonObjectSetInplace(jTile, "orientation", JsonInt(TileRotateOrientation(nOrientation, 0)));
    JsonObjectSetInplace(jTile, "height",      JsonInt(nHeight));

    JsonArrayInsertInplace(jBatch, jTile);
    return jBatch;
}

int TileBatchCount(json jBatch)
{
    return JsonGetLength(jBatch);
}

int TileBatchApply(object oArea, json jBatch, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING)
{
    if (!GetIsObjectValid(oArea)) return FALSE;
    if (JsonGetLength(jBatch) < 1) return FALSE;

    SetTileJson(oArea, jBatch, nFlags);
    return TRUE;
}

// --- Groups ---

json TileGroup()
{
    return JsonArray();
}

json TileGroupAdd(json jGroup, int nOffsetX, int nOffsetY, int nTileID, int nOrientation, int nHeight = 0)
{
    if (nTileID < 0) return jGroup;           // hole - see the note on SetTileAt

    json jTile = JsonObject();
    JsonObjectSetInplace(jTile, "dx",          JsonInt(nOffsetX));
    JsonObjectSetInplace(jTile, "dy",          JsonInt(nOffsetY));
    JsonObjectSetInplace(jTile, "tileid",      JsonInt(nTileID));
    JsonObjectSetInplace(jTile, "orientation", JsonInt(nOrientation));
    JsonObjectSetInplace(jTile, "height",      JsonInt(nHeight));

    JsonArrayInsertInplace(jGroup, jTile);
    return jGroup;
}

int TileGroupCount(json jGroup)
{
    return JsonGetLength(jGroup);
}

int TileGroupFits(object oArea, int nOriginX, int nOriginY, int nRotation, json jGroup)
{
    if (!GetIsObjectValid(oArea)) return FALSE;

    int nCount = JsonGetLength(jGroup);
    if (nCount < 1) return FALSE;

    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        int nOffsetX = _TileGroupFieldAt(jGroup, nIndex, "dx");
        int nOffsetY = _TileGroupFieldAt(jGroup, nIndex, "dy");
        if (!TileInBounds(oArea,
                nOriginX + _TileRotatedOffsetX(nOffsetX, nOffsetY, nRotation),
                nOriginY + _TileRotatedOffsetY(nOffsetX, nOffsetY, nRotation)))
            return FALSE;
    }
    return TRUE;
}

int TileGroupStamp(object oArea, int nOriginX, int nOriginY, int nRotation, json jGroup, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING)
{
    if (!TileGroupFits(oArea, nOriginX, nOriginY, nRotation, jGroup)) return FALSE;

    json jBatch = TileBatch();
    int nCount = JsonGetLength(jGroup);
    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        int nOffsetX = _TileGroupFieldAt(jGroup, nIndex, "dx");
        int nOffsetY = _TileGroupFieldAt(jGroup, nIndex, "dy");
        // The tile's own orientation turns with the group, not just its position.
        jBatch = TileBatchAdd(jBatch, oArea,
                    nOriginX + _TileRotatedOffsetX(nOffsetX, nOffsetY, nRotation),
                    nOriginY + _TileRotatedOffsetY(nOffsetX, nOffsetY, nRotation),
                    _TileGroupFieldAt(jGroup, nIndex, "tileid"),
                    TileRotateOrientation(_TileGroupFieldAt(jGroup, nIndex, "orientation"), nRotation),
                    _TileGroupFieldAt(jGroup, nIndex, "height"));
    }
    return TileBatchApply(oArea, jBatch, nFlags);
}

int TileGroupStampAtLocation(location lOrigin, json jGroup, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING)
{
    object oArea  = GetAreaFromLocation(lOrigin);
    vector vPos   = GetPositionFromLocation(lOrigin);
    int nRotation = TileRotationFromFacing(GetFacingFromLocation(lOrigin));

    return TileGroupStamp(oArea, TileXFromPosition(vPos), TileYFromPosition(vPos),
                          nRotation, jGroup, nFlags);
}

// --- Snapshot and restore ---

json TileSnapshotRect(object oArea, int nX, int nY, int nWidth, int nHeight)
{
    json jBatch = TileBatch();

    int nRow;
    for (nRow = 0; nRow < nHeight; nRow++)
    {
        int nColumn;
        for (nColumn = 0; nColumn < nWidth; nColumn++)
        {
            int nTileX = nX + nColumn;
            int nTileY = nY + nRow;
            if (!TileInBounds(oArea, nTileX, nTileY)) continue;

            jBatch = TileBatchAdd(jBatch, oArea, nTileX, nTileY,
                        GetTileIDAt(oArea, nTileX, nTileY),
                        GetTileOrientationAt(oArea, nTileX, nTileY),
                        GetTileHeightAt(oArea, nTileX, nTileY));
        }
    }
    return jBatch;
}

json TileSnapshotGroup(object oArea, int nOriginX, int nOriginY, int nRotation, json jGroup)
{
    json jBatch = TileBatch();

    int nCount = JsonGetLength(jGroup);
    int nIndex;
    for (nIndex = 0; nIndex < nCount; nIndex++)
    {
        int nOffsetX = _TileGroupFieldAt(jGroup, nIndex, "dx");
        int nOffsetY = _TileGroupFieldAt(jGroup, nIndex, "dy");
        int nTileX = nOriginX + _TileRotatedOffsetX(nOffsetX, nOffsetY, nRotation);
        int nTileY = nOriginY + _TileRotatedOffsetY(nOffsetX, nOffsetY, nRotation);
        if (!TileInBounds(oArea, nTileX, nTileY)) continue;

        jBatch = TileBatchAdd(jBatch, oArea, nTileX, nTileY,
                    GetTileIDAt(oArea, nTileX, nTileY),
                    GetTileOrientationAt(oArea, nTileX, nTileY),
                    GetTileHeightAt(oArea, nTileX, nTileY));
    }
    return jBatch;
}

// --- Rotating tiles already in the area ---

int TileBlockRotate(object oArea, int nX, int nY, int nSize, int nRotation, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING)
{
    if (nSize < 1) return FALSE;

    nRotation = TileRotateOrientation(nRotation, 0);
    if (nRotation == TILE_ROTATE_NONE) return TRUE;

    // Reject the whole operation unless the block is fully inside the area, so a
    // rotation never silently drops the tiles that fell off the edge.
    if (!TileInBounds(oArea, nX, nY)) return FALSE;
    if (!TileInBounds(oArea, nX + nSize - 1, nY + nSize - 1)) return FALSE;

    // Every tile is read while building the batch and nothing is written until
    // TileBatchApply, so sources are never clobbered before they are read.
    json jBatch = TileBatch();
    int nLocalY;
    for (nLocalY = 0; nLocalY < nSize; nLocalY++)
    {
        int nLocalX;
        for (nLocalX = 0; nLocalX < nSize; nLocalX++)
        {
            int nSourceX = nX + nLocalX;
            int nSourceY = nY + nLocalY;

            // Offsets rotate about the block's south-west corner, then shift back
            // so the result lands on the original footprint.
            int nDestX = _TileRotatedOffsetX(nLocalX, nLocalY, nRotation);
            int nDestY = _TileRotatedOffsetY(nLocalX, nLocalY, nRotation);
            if (nRotation == TILE_ROTATE_90)  nDestX += nSize - 1;
            if (nRotation == TILE_ROTATE_180) { nDestX += nSize - 1; nDestY += nSize - 1; }
            if (nRotation == TILE_ROTATE_270) nDestY += nSize - 1;

            jBatch = TileBatchAdd(jBatch, oArea, nX + nDestX, nY + nDestY,
                        GetTileIDAt(oArea, nSourceX, nSourceY),
                        TileRotateOrientation(GetTileOrientationAt(oArea, nSourceX, nSourceY), nRotation),
                        GetTileHeightAt(oArea, nSourceX, nSourceY));
        }
    }
    return TileBatchApply(oArea, jBatch, nFlags);
}

int TileBlockRotate180(object oArea, int nX, int nY, int nWidth, int nHeight, int nFlags = SETTILE_FLAG_RECOMPUTE_LIGHTING)
{
    if ((nWidth < 1) || (nHeight < 1)) return FALSE;
    if (!TileInBounds(oArea, nX, nY)) return FALSE;
    if (!TileInBounds(oArea, nX + nWidth - 1, nY + nHeight - 1)) return FALSE;

    json jBatch = TileBatch();
    int nLocalY;
    for (nLocalY = 0; nLocalY < nHeight; nLocalY++)
    {
        int nLocalX;
        for (nLocalX = 0; nLocalX < nWidth; nLocalX++)
        {
            int nSourceX = nX + nLocalX;
            int nSourceY = nY + nLocalY;

            jBatch = TileBatchAdd(jBatch, oArea,
                        nX + (nWidth  - 1 - nLocalX),
                        nY + (nHeight - 1 - nLocalY),
                        GetTileIDAt(oArea, nSourceX, nSourceY),
                        TileRotateOrientation(GetTileOrientationAt(oArea, nSourceX, nSourceY), TILE_ROTATE_180),
                        GetTileHeightAt(oArea, nSourceX, nSourceY));
        }
    }
    return TileBatchApply(oArea, jBatch, nFlags);
}

// --- Private helpers ---

// Rotate an (x,y) offset about the origin by nSteps of 90 degrees
// counter-clockwise: one step maps (x,y) -> (-y,x).
int _TileRotatedOffsetX(int nOffsetX, int nOffsetY, int nSteps)
{
    switch (TileRotateOrientation(nSteps, 0))
    {
        case TILE_ROTATE_90:  return -nOffsetY;
        case TILE_ROTATE_180: return -nOffsetX;
        case TILE_ROTATE_270: return  nOffsetY;
    }
    return nOffsetX;
}

int _TileRotatedOffsetY(int nOffsetX, int nOffsetY, int nSteps)
{
    switch (TileRotateOrientation(nSteps, 0))
    {
        case TILE_ROTATE_90:  return  nOffsetX;
        case TILE_ROTATE_180: return -nOffsetY;
        case TILE_ROTATE_270: return -nOffsetX;
    }
    return nOffsetY;
}

// One field of one tile record in a group array.
int _TileGroupFieldAt(json jGroup, int nIndex, string sKey)
{
    return JsonGetInt(JsonObjectGet(JsonArrayGet(jGroup, nIndex), sKey));
}
