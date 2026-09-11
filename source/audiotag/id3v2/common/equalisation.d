/++
Shared semantic representation for legacy ID3v2 equalisation bands.

ID3v2.2 `EQU` and ID3v2.3 `EQUA` use the same legacy band semantics:
one frequency in whole hertz, a separate increment/decrement flag and an
unsigned adjustment magnitude whose bit width is declared by the surrounding
frame.

ID3v2.4 replaces that representation with `EQU2`, which uses an identification
string, an interpolation method and signed fixed-point adjustments. This type
therefore intentionally models only the legacy `EQU`/`EQUA` semantics.

`BigInt` avoids imposing an artificial machine-integer limit on adjustment
magnitudes whose declared width may be up to 255 bits.
+/
module audiotag.id3v2.common.equalisation;

import std.bigint :
    BigInt;

struct Id3v2LegacyEqualisationBand
{
    bool increment;
    ushort frequencyHz;
    BigInt adjustmentMagnitude;
}

unittest
{
    const band =
        Id3v2LegacyEqualisationBand(
            true,
            1000,
            BigInt(512)
        );

    assert(band.increment);
    assert(band.frequencyHz == 1000);
    assert(band.adjustmentMagnitude == 512);
}
