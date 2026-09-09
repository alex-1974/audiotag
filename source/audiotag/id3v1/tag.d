/++
Bounded structural parsing for fixed-size ID3v1 tags.

ID3v1 stores one 128-byte metadata block with the `TAG` signature at the
beginning of that block. This module parses an already bounded tag block; it
does not locate the block inside an MP3 file.

Text fields remain raw byte spans. ID3v1 has no encoding marker and real-world
files do not provide a sufficiently reliable encoding contract for the
structural parser to decode text without policy.

ID3v1.1 is recognized only when the 29th byte of the original 30-byte comment
field is zero and the 30th byte is non-zero. In that case the comment is 28
bytes and the final byte is the track number. A zero track byte therefore
remains ID3v1.0/undefined-track semantics.
+/
module audiotag.id3v1.tag;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;


/++
Fixed physical size of one ID3v1 tag block.
+/
enum size_t id3v1TagSize =
    128;


/++
Structural ID3v1 revision represented by a parsed tag.
+/
enum Id3v1Revision : ubyte
{
    /// Original 30-byte comment layout.
    v10,

    /// 28-byte comment followed by zero marker and non-zero track byte.
    v11
}


/++
Zero-copy structural view of one ID3v1.0 or ID3v1.1 tag.

All textual fields preserve their exact source bytes, including NUL or space
padding. `genre` is the raw genre byte and is not mapped to a genre name here.

For ID3v1.1, `comment` is the 28-byte comment field and `track` is the defined
non-zero track byte. For ID3v1.0, `comment` is the complete 30-byte field and
`track` is zero.
+/
struct Id3v1Tag
{
    /// Detected structural revision.
    Id3v1Revision revision;

    /// Complete 128-byte source tag.
    ByteSpan raw;

    /// Raw 30-byte title field.
    ByteSpan title;

    /// Raw 30-byte artist field.
    ByteSpan artist;

    /// Raw 30-byte album field.
    ByteSpan album;

    /// Raw 4-byte year field.
    ByteSpan year;

    /// Raw comment field: 30 bytes for v1.0, 28 bytes for v1.1.
    ByteSpan comment;

    /// Defined v1.1 track number, otherwise zero.
    ubyte track;

    /// Raw one-byte genre identifier.
    ubyte genre;

    /++
    Returns whether this tag carries a defined ID3v1.1 track number.
    +/
    @property
    bool hasTrack() const
        @safe pure nothrow @nogc
    {
        return
            revision ==
            Id3v1Revision.v11;
    }
}


/++
Parses one exact 128-byte ID3v1 tag block.

This function deliberately does not search for a trailer. An enclosing
container parser should locate and bound the final 128 bytes first, then pass
that exact block here.

ID3v1.1 track detection follows the historical compatibility rule: byte 125
relative to the tag start must be zero and byte 126 must be non-zero.

Params:
    source = Exact bounded candidate tag block.

Returns:
    A zero-copy structural tag view, or a structured parse error.

Errors:
    `endOfSpan` when fewer than 128 bytes are supplied;
    `invalidLength` when more than 128 bytes are supplied;
    `invalidSignature` when bytes 0..2 are not `TAG`.
+/
ParseResult!Id3v1Tag
parseId3v1Tag(
    ByteSpan source
)
    @safe pure nothrow @nogc
{
    if (
        source.length <
        id3v1TagSize
    )
    {
        return
            ParseResult!Id3v1Tag
                .failure(
                    ParseError(
                        ParseErrorCode.endOfSpan,
                        source.sourceOffset,
                        id3v1TagSize,
                        source.length
                    )
                );
    }

    if (
        source.length >
        id3v1TagSize
    )
    {
        return
            ParseResult!Id3v1Tag
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        source.sourceOffset,
                        id3v1TagSize,
                        source.length
                    )
                );
    }

    const bytes =
        source.data;

    if (
        bytes[0] != 'T' ||
        bytes[1] != 'A' ||
        bytes[2] != 'G'
    )
    {
        return
            ParseResult!Id3v1Tag
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        source.sourceOffset
                    )
                );
    }

    const hasTrack =
        bytes[125] == 0 &&
        bytes[126] != 0;

    Id3v1Tag tag;

    tag.revision =
        hasTrack
            ? Id3v1Revision.v11
            : Id3v1Revision.v10;

    tag.raw =
        source;

    tag.title =
        source.subspan(
            3,
            30
        );

    tag.artist =
        source.subspan(
            33,
            30
        );

    tag.album =
        source.subspan(
            63,
            30
        );

    tag.year =
        source.subspan(
            93,
            4
        );

    tag.comment =
        source.subspan(
            97,
            hasTrack
                ? 28
                : 30
        );

    tag.track =
        hasTrack
            ? bytes[126]
            : 0;

    tag.genre =
        bytes[127];

    return
        ParseResult!Id3v1Tag
            .success(
                tag
            );
}


private void
setSignature(
    ref ubyte[128] bytes
)
    @safe pure nothrow @nogc
{
    bytes[0] = 'T';
    bytes[1] = 'A';
    bytes[2] = 'G';
}


/// Parses an ID3v1.0 tag and preserves fixed-field source spans.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'T';
    bytes[33] = 'A';
    bytes[63] = 'L';

    bytes[93] = '1';
    bytes[94] = '9';
    bytes[95] = '9';
    bytes[96] = '9';

    bytes[97] = 'C';

    // Make the v1.1 marker condition explicitly false.
    bytes[125] = 'X';
    bytes[126] = 'Y';

    bytes[127] = 13;

    auto result =
        parseId3v1Tag(
            ByteSpan(
                bytes[],
                1000
            )
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(
        tag.revision ==
        Id3v1Revision.v10
    );

    assert(!tag.hasTrack);
    assert(tag.track == 0);
    assert(tag.genre == 13);

    assert(tag.raw.length == 128);
    assert(tag.raw.sourceOffset == 1000);

    assert(tag.title.length == 30);
    assert(tag.title.sourceOffset == 1003);
    assert(tag.title.data[0] == 'T');

    assert(tag.artist.length == 30);
    assert(tag.artist.sourceOffset == 1033);
    assert(tag.artist.data[0] == 'A');

    assert(tag.album.length == 30);
    assert(tag.album.sourceOffset == 1063);
    assert(tag.album.data[0] == 'L');

    assert(tag.year.length == 4);
    assert(tag.year.sourceOffset == 1093);

    assert(tag.comment.length == 30);
    assert(tag.comment.sourceOffset == 1097);
    assert(tag.comment.data[0] == 'C');
}


/// Parses the ID3v1.1 zero-marker plus non-zero-track convention.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[97] = 'C';
    bytes[124] = 'Z';
    bytes[125] = 0;
    bytes[126] = 7;
    bytes[127] = 17;

    auto result =
        parseId3v1Tag(
            ByteSpan(
                bytes[],
                2000
            )
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(
        tag.revision ==
        Id3v1Revision.v11
    );

    assert(tag.hasTrack);
    assert(tag.track == 7);
    assert(tag.genre == 17);

    assert(tag.comment.length == 28);
    assert(tag.comment.sourceOffset == 2097);
    assert(tag.comment.data[0] == 'C');
    assert(tag.comment.data[27] == 'Z');
}


/// A zero byte in the track slot leaves the track undefined.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[125] = 0;
    bytes[126] = 0;

    auto result =
        parseId3v1Tag(
            ByteSpan(bytes[])
        );

    assert(result.hasValue);

    assert(
        result.value.revision ==
        Id3v1Revision.v10
    );

    assert(!result.value.hasTrack);
    assert(result.value.track == 0);
    assert(result.value.comment.length == 30);
}


/// Short candidate blocks report an exact bounded-read failure.
unittest
{
    ubyte[127] bytes;

    auto result =
        parseId3v1Tag(
            ByteSpan(
                bytes[],
                3000
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 3000);
    assert(result.error.requested == 128);
    assert(result.error.available == 127);
}


/// Oversized candidate blocks are rejected rather than partially consumed.
unittest
{
    ubyte[129] bytes;

    auto result =
        parseId3v1Tag(
            ByteSpan(
                bytes[],
                4000
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 4000);
    assert(result.error.requested == 128);
    assert(result.error.available == 129);
}


/// The required TAG signature is validated at the beginning of the block.
unittest
{
    ubyte[128] bytes;

    bytes[0] = 'B';
    bytes[1] = 'A';
    bytes[2] = 'D';

    auto result =
        parseId3v1Tag(
            ByteSpan(
                bytes[],
                5000
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 5000);
}


/// Parsed field spans retain zero-copy access to the original storage.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);
    bytes[3] = 'A';

    auto result =
        parseId3v1Tag(
            ByteSpan(bytes[])
        );

    assert(result.hasValue);
    assert(result.value.title.data[0] == 'A');

    bytes[3] = 'B';

    assert(result.value.title.data[0] == 'B');
}
