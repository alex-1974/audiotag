/++
Shared structural constants for ID3v2 music-CD-identifier TOC payloads.

ID3v2.2 `MCI` and ID3v2.3/v2.4 `MCDI` carry a binary dump of the CD Table Of
Contents. The ID3 specifications describe a four-byte TOC header followed by
eight-byte TOC entries and cap the complete payload at 804 bytes.

This module deliberately validates only that outer ID3-defined shape. It does
not interpret CD-ROM TOC descriptors, track numbers or addresses; those
belong to a CD-specific layer rather than the ID3 frame codec.
+/
module audiotag.id3v2.common.music_cd_identifier;

enum size_t id3v2MusicCdTocHeaderSize =
    4;

enum size_t id3v2MusicCdTocEntrySize =
    8;

enum size_t id3v2MusicCdTocMaximumSize =
    804;

bool
isValidId3v2MusicCdTocLength(
    size_t length
)
    @safe pure nothrow @nogc
{
    if (
        length <
        id3v2MusicCdTocHeaderSize
    )
    {
        return false;
    }

    if (
        length >
        id3v2MusicCdTocMaximumSize
    )
    {
        return false;
    }

    return
        (
            (
                length -
                id3v2MusicCdTocHeaderSize
            ) %
            id3v2MusicCdTocEntrySize
        ) ==
        0;
}

unittest
{
    assert(isValidId3v2MusicCdTocLength(4));
    assert(isValidId3v2MusicCdTocLength(12));
    assert(isValidId3v2MusicCdTocLength(804));

    assert(!isValidId3v2MusicCdTocLength(1));
    assert(!isValidId3v2MusicCdTocLength(11));
    assert(!isValidId3v2MusicCdTocLength(805));
}
