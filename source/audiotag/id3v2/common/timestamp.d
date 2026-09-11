/++
Shared timestamp-unit semantics used by ID3v2 synchronisation frames.

ID3v2.2 `ETC`, `STC` and `SLT` and their later-revision counterparts use the
same two timestamp-format discriminator values:

- `$01`: absolute MPEG-frame count from the beginning of the file;
- `$02`: absolute milliseconds from the beginning of the file.

The concrete frame grammar and event/tempo/lyric semantics remain
revision-specific.
+/
module audiotag.id3v2.common.timestamp;


/++
Unit used by an absolute 32-bit ID3v2 synchronisation timestamp.
+/
enum Id3v2TimestampFormat : ubyte
{
    /// Absolute MPEG-frame count from the beginning of the file.
    mpegFrames = 0x01,

    /// Absolute milliseconds from the beginning of the file.
    milliseconds = 0x02
}


/++
Returns whether a raw timestamp-format discriminator is defined by ID3v2.
+/
bool
isValidId3v2TimestampFormat(
    ubyte value
)
    @safe pure nothrow @nogc
{
    return
        value ==
            cast(ubyte)
                Id3v2TimestampFormat.mpegFrames ||
        value ==
            cast(ubyte)
                Id3v2TimestampFormat.milliseconds;
}


unittest
{
    assert(isValidId3v2TimestampFormat(0x01));
    assert(isValidId3v2TimestampFormat(0x02));

    assert(!isValidId3v2TimestampFormat(0x00));
    assert(!isValidId3v2TimestampFormat(0x03));
    assert(!isValidId3v2TimestampFormat(0xFF));
}
