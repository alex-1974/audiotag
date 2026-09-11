/++
Shared semantic representation for legacy ID3v2 relative-volume adjustments.

ID3v2.2 `RVA` and ID3v2.3 `RVAD` use unsigned adjustment magnitudes plus
separate increment/decrement flags. ID3v2.4 replaces that representation with
the signed fixed-point `RVA2` format, so this type intentionally models only
the legacy RVA/RVAD semantics.

The width of a legacy volume description is carried by the surrounding frame.
`BigInt` avoids imposing an artificial machine-integer limit on the decoded
magnitude or peak value.
+/
module audiotag.id3v2.common.relative_volume;

import std.bigint :
    BigInt;

struct Id3v2LegacyVolumeChannelAdjustment
{
    bool increment;
    BigInt changeMagnitude;
    bool hasPeak;
    BigInt peak;
}

unittest
{
    const adjustment =
        Id3v2LegacyVolumeChannelAdjustment(
            true,
            BigInt(512),
            true,
            BigInt(1023)
        );

    assert(adjustment.increment);
    assert(adjustment.changeMagnitude == 512);
    assert(adjustment.hasPeak);
    assert(adjustment.peak == 1023);
}
