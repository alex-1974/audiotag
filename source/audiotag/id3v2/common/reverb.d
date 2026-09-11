/++
Shared semantic representation for ID3v2 reverb settings.

ID3v2.2 `REV` and ID3v2.3/v2.4 `RVRB` use the same twelve-byte semantic
layout. Reverb delays are expressed in milliseconds. A bounce count of `$FF`
means infinitely many bounces. Feedback and premix fields use the full byte
range, where `$00` denotes 0% and `$FF` denotes 100%.

Physical byte layout, frame identifiers, unsynchronisation and source
provenance remain revision-specific.
+/
module audiotag.id3v2.common.reverb;

struct Id3v2ReverbBounceCount
{
    bool infinite;
    ubyte finiteCount;
}

Id3v2ReverbBounceCount
decodeId3v2ReverbBounceCount(
    ubyte value
)
    @safe pure nothrow @nogc
{
    if (value == 0xFF)
    {
        return Id3v2ReverbBounceCount(true, 0);
    }

    return Id3v2ReverbBounceCount(false, value);
}

struct Id3v2ReverbSettings
{
    ushort leftDelayMilliseconds;
    ushort rightDelayMilliseconds;

    Id3v2ReverbBounceCount leftBounces;
    Id3v2ReverbBounceCount rightBounces;

    ubyte feedbackLeftToLeft;
    ubyte feedbackLeftToRight;
    ubyte feedbackRightToRight;
    ubyte feedbackRightToLeft;

    ubyte premixLeftToRight;
    ubyte premixRightToLeft;
}

unittest
{
    const finite = decodeId3v2ReverbBounceCount(7);
    assert(!finite.infinite);
    assert(finite.finiteCount == 7);

    const infinite = decodeId3v2ReverbBounceCount(0xFF);
    assert(infinite.infinite);
    assert(infinite.finiteCount == 0);
}
