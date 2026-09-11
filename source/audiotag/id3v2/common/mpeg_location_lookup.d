/++
Shared semantic representation for ID3v2 MPEG location lookup tables.

ID3v2.2 `MLL` and ID3v2.3/v2.4 `MLLT` use the same lookup parameters and
per-reference deviation semantics. Physical bit packing, unsynchronisation and
raw source provenance remain revision-specific.

Deviation widths are encoded as full bytes by the specification and are not
given an artificial 32- or 64-bit upper bound here. `BigInt` therefore
preserves every formally representable unsigned deviation value.
+/
module audiotag.id3v2.common.mpeg_location_lookup;

import std.bigint :
    BigInt;

struct Id3v2MpegLocationLookupParameters
{
    ushort mpegFramesBetweenReference;
    uint bytesBetweenReference;
    uint millisecondsBetweenReference;
    ubyte bitsForBytesDeviation;
    ubyte bitsForMillisecondsDeviation;
}

struct Id3v2MpegLocationLookupReference
{
    BigInt bytesDeviation;
    BigInt millisecondsDeviation;
}

unittest
{
    const parameters =
        Id3v2MpegLocationLookupParameters(
            2,
            1000,
            26,
            4,
            4
        );

    assert(parameters.mpegFramesBetweenReference == 2);
    assert(parameters.bytesBetweenReference == 1000);
    assert(parameters.millisecondsBetweenReference == 26);

    const reference =
        Id3v2MpegLocationLookupReference(
            BigInt(10),
            BigInt(11)
        );

    assert(reference.bytesDeviation == 10);
    assert(reference.millisecondsDeviation == 11);
}
