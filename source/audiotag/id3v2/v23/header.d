/++
ID3v2.3 tag-header parsing.

This module parses only the fixed 10-byte ID3v2.3 tag header.
Extended headers, frames, padding and tag-level unsynchronisation are
handled by later structural parsing stages.

Parsing is atomic: a malformed or unsupported header leaves the input
cursor unchanged.
+/
module audiotag.id3v2.v23.header;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.numeric :
    readSynchsafe32;

import audiotag.core.result :
    ParseResult;


/++
Parsed ID3v2.3 tag header.

`tagSize` is the size stored in the ID3 header. It describes the bytes
following the fixed ten-byte header that belong to the tag.
+/
struct Id3v23Header
{
    /// Absolute source offset of the first `I` in the ID3 identifier.
    size_t sourceOffset;

    /// ID3v2.3 revision byte.
    ubyte revision;

    /// Raw ID3v2.3 header flags.
    ubyte flags;

    /// Decoded 28-bit synchsafe tag size.
    uint tagSize;


    /// Whether tag-level unsynchronisation is indicated.
    @property
    bool unsynchronisation() const
        @safe pure nothrow @nogc
    {
        return
            (flags & 0x80) != 0;
    }


    /// Whether an extended header follows the tag header.
    @property
    bool hasExtendedHeader() const
        @safe pure nothrow @nogc
    {
        return
            (flags & 0x40) != 0;
    }


    /// Whether the experimental indicator is set.
    @property
    bool experimentalIndicator() const
        @safe pure nothrow @nogc
    {
        return
            (flags & 0x20) != 0;
    }
}


/++
Parses one ID3v2.3 tag header.

The parser accepts ID3 major version 3. Revision values are retained
for provenance; revision `0xFF` is rejected because ID3 version and
revision bytes may not use that value.

Only the three ID3v2.3-defined header flag bits are accepted:

- bit 7: unsynchronisation;
- bit 6: extended header;
- bit 5: experimental indicator.

The lower five bits must be zero.

Params:
    cursor = Cursor positioned at the beginning of an ID3v2 tag.

Returns:
    The parsed ID3v2.3 header, or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23Header
parseId3v23Header(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    /*
     * Parse transactionally. Only commit the copied cursor state after
     * the complete header has been validated.
     */
    auto probe =
        cursor;

    auto rawResult =
        probe.takeBytes(10);

    if (rawResult.hasError)
    {
        return
            ParseResult!Id3v23Header
                .failure(
                    rawResult.error
                );
    }

    const raw =
        rawResult.value;

    const data =
        raw.data;

    immutable ubyte[3] identifier =
        ['I', 'D', '3'];

    foreach (
        index;
        0 .. identifier.length
    )
    {
        if (
            data[index] !=
            identifier[index]
        )
        {
            return
                ParseResult!Id3v23Header
                    .failure(
                        ParseError(
                            ParseErrorCode
                                .invalidSignature,
                            raw.sourceOffset +
                                index
                        )
                    );
        }
    }

    const major =
        data[3];

    const revision =
        data[4];

    if (
        major != 3 ||
        revision == 0xFF
    )
    {
        return
            ParseResult!Id3v23Header
                .failure(
                    ParseError(
                        ParseErrorCode
                            .unsupportedVersion,
                        raw.sourceOffset +
                            (
                                major != 3
                                ? 3
                                : 4
                            )
                    )
                );
    }

    const flags =
        data[5];

    /*
     * ID3v2.3 defines only bits 7, 6 and 5.
     */
    if (
        (flags & 0x1F) != 0
    )
    {
        return
            ParseResult!Id3v23Header
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidFlags,
                        raw.sourceOffset + 5
                    )
                );
    }

    auto sizeCursor =
        ByteCursor(
            raw.subspan(
                6,
                4
            )
        );

    auto sizeResult =
        sizeCursor.readSynchsafe32();

    if (sizeResult.hasError)
    {
        return
            ParseResult!Id3v23Header
                .failure(
                    sizeResult.error
                );
    }

    const header =
        Id3v23Header(
            raw.sourceOffset,
            revision,
            flags,
            sizeResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23Header
            .success(header);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;
}


/// A minimal ID3v2.3.0 header consumes exactly ten bytes.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.sourceOffset == 100);
    assert(header.revision == 0);
    assert(header.flags == 0);
    assert(header.tagSize == 0);

    assert(!header.unsynchronisation);
    assert(!header.hasExtendedHeader);
    assert(!header.experimentalIndicator);

    assert(cursor.position == 10);
    assert(cursor.absoluteOffset == 110);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// All defined ID3v2.3 header flags are retained semantically.
unittest
{
    /*
     * 00 02 02 74 decodes to 33140.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0xE0,
            0x00, 0x02, 0x02, 0x74
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.flags == 0xE0);
    assert(header.tagSize == 33140);

    assert(header.unsynchronisation);
    assert(header.hasExtendedHeader);
    assert(header.experimentalIndicator);
}


/// Non-zero revision bytes are retained for provenance.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x01,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasValue);
    assert(result.value.revision == 1);
    assert(cursor.empty);
}


/// Truncated ID3 headers fail atomically at every possible length.
unittest
{
    const ubyte[] complete =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    foreach (
        length;
        0 .. 10
    )
    {
        auto cursor =
            ByteCursor(
                ByteSpan(
                    complete[
                        0 .. length
                    ],
                    200
                )
            );

        auto result =
            cursor.parseId3v23Header();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.endOfSpan
        );

        assert(result.error.offset == 200);
        assert(result.error.requested == 10);
        assert(result.error.available == length);

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 200);
        assert(cursor.remaining == length);
    }
}


/// Invalid identifier bytes report their exact absolute source offset.
unittest
{
    foreach (
        invalidIndex;
        0 .. 3
    )
    {
        ubyte[] bytes =
            [
                'I', 'D', '3',
                0x03, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x00
            ];

        bytes[invalidIndex] =
            0x00;

        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    300
                )
            );

        auto result =
            cursor.parseId3v23Header();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidSignature
        );

        assert(
            result.error.offset ==
            300 + invalidIndex
        );

        assert(cursor.position == 0);
    }
}


/// Other ID3 major versions are rejected by the v2.3 parser.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.unsupportedVersion
    );

    assert(result.error.offset == 403);
    assert(cursor.position == 0);
}


/// Revision 0xFF is not a valid ID3 version component.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0xFF,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.unsupportedVersion
    );

    assert(result.error.offset == 504);
    assert(cursor.position == 0);
}


/// Every undefined ID3v2.3 header flag bit is rejected.
unittest
{
    foreach (
        bit;
        0 .. 5
    )
    {
        const flags =
            cast(ubyte)
                (1u << bit);

        const ubyte[] bytes =
            [
                'I', 'D', '3',
                0x03, 0x00,
                flags,
                0x00, 0x00, 0x00, 0x00
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    600
                )
            );

        auto result =
            cursor.parseId3v23Header();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidFlags
        );

        assert(result.error.offset == 605);
        assert(cursor.position == 0);
    }
}


/// Invalid synchsafe tag-size bytes report the offending source byte.
unittest
{
    foreach (
        invalidIndex;
        0 .. 4
    )
    {
        ubyte[] bytes =
            [
                'I', 'D', '3',
                0x03, 0x00,
                0x00,
                0x01, 0x02, 0x03, 0x04
            ];

        bytes[
            6 + invalidIndex
        ] |=
            0x80;

        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    700
                )
            );

        auto result =
            cursor.parseId3v23Header();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode
                .invalidSynchsafeInteger
        );

        assert(
            result.error.offset ==
            706 + invalidIndex
        );

        assert(cursor.position == 0);
    }
}


/// The complete 28-bit ID3 tag-size domain is accepted.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x7F, 0x7F, 0x7F, 0x7F
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasValue);

    assert(
        result.value.tagSize ==
        0x0FFF_FFFF
    );

    assert(cursor.empty);
}


/// Header parsing retains absolute offsets after prior cursor movement.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x01,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    cursor.popFront();

    auto result =
        cursor.parseId3v23Header();

    assert(result.hasValue);

    assert(
        result.value.sourceOffset ==
        1001
    );

    assert(result.value.tagSize == 1);

    assert(cursor.position == 11);
    assert(cursor.absoluteOffset == 1011);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}
