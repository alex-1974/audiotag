/++
ID3v2.3 extended-header parsing.

The ID3v2.3 extended header consists of:

- four-byte unsigned big-endian size;
- two-byte extended flags;
- four-byte unsigned big-endian padding size;
- optional four-byte CRC-32.

The encoded `size` excludes its own four bytes and is therefore
currently either 6 or 10.

Because the extended header belongs to the ID3v2.3 tag body, parsing
operates on the logical tag-level byte stream and therefore respects
tag-level unsynchronisation.

The complete physical source representation is retained in `raw`.

Parsing is atomic: malformed or truncated input leaves the caller's
cursor unchanged.
+/
module audiotag.id3v2.v23.extended_header;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;


/++
Parsed ID3v2.3 extended header.

`size` is the ID3v2.3 extended-header size field and therefore excludes
the four bytes used to encode `size` itself.

`crc32` is meaningful only when `hasCrc` is true.

`raw` preserves the complete physical extended-header representation,
including any ID3v2.3 unsynchronisation stuffing bytes.
+/
struct Id3v23ExtendedHeader
{
    /// Absolute physical source offset of the first size byte.
    size_t sourceOffset;

    /// Logical extended-header size excluding the four size bytes.
    uint size;

    /// Raw 16-bit ID3v2.3 extended flags.
    ushort flags;

    /// Declared number of padding bytes at the end of the tag.
    uint paddingSize;

    /// Decoded CRC-32 value when present.
    uint crc32;

    /// Complete physical extended-header source representation.
    ByteSpan raw;


    /// Whether the optional CRC-32 field is present.
    @property
    bool hasCrc() const
        @safe pure nothrow @nogc
    {
        return
            (flags & 0x8000) != 0;
    }


    /// Logical byte length including the four-byte size field.
    @property
    size_t logicalLength() const
        @safe pure nothrow @nogc
    {
        return
            cast(size_t) size + 4;
    }
}


/++
Parses one ID3v2.3 extended header.

ID3v2.3 currently permits exactly two structural forms:

- size 6, flags 0, no CRC;
- size 10, CRC flag set, four CRC bytes appended.

Only bit 15 of the 16-bit extended flags is defined. Every other flag
bit must be clear.

The padding-size value is parsed structurally here but is not compared
against the enclosing tag layout. That validation belongs to the later
tag-body/frame-sequence stage.

Params:
    cursor = Logical ID3v2.3 tag-body cursor positioned at the first
        extended-header size byte.

Returns:
    The parsed extended header or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23ExtendedHeader
parseId3v23ExtendedHeader(
    ref Id3v23DataCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    const sourceOffset =
        probe.absoluteOffset;

    const startPhysicalPosition =
        probe.physicalPosition;

    /*
     * Keep a physical view beginning exactly at the structure start.
     * After successful logical parsing we can retain the precise raw
     * number of physical bytes consumed, including stuffing bytes.
     */
    const rawStart =
        cursor.remainingRaw;


    auto sizeResult =
        probe.takeU32BE();

    if (sizeResult.hasError)
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    sizeResult.error
                );
    }

    const size =
        sizeResult.value;

    /*
     * The v2.3 specification currently defines only:
     *
     *   6 bytes: flags + padding size
     *  10 bytes: flags + padding size + CRC
     */
    if (
        size != 6 &&
        size != 10
    )
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        sourceOffset
                    )
                );
    }


    auto highFlagsResult =
        probe.takeByte();

    if (highFlagsResult.hasError)
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    highFlagsResult.error
                );
    }

    const highFlags =
        highFlagsResult.value.value;

    /*
     * Only bit 7 of the first flag byte is defined.
     */
    if (
        (highFlags & 0x7F) != 0
    )
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    ParseError(
                        ParseErrorCode.invalidFlags,
                        highFlagsResult
                            .value
                            .sourceOffset
                    )
                );
    }


    auto lowFlagsResult =
        probe.takeByte();

    if (lowFlagsResult.hasError)
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    lowFlagsResult.error
                );
    }

    const lowFlags =
        lowFlagsResult.value.value;

    /*
     * No bit in the second v2.3 extended-flag byte is defined.
     */
    if (
        lowFlags != 0
    )
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    ParseError(
                        ParseErrorCode.invalidFlags,
                        lowFlagsResult
                            .value
                            .sourceOffset
                    )
                );
    }


    const flags =
        cast(ushort)
        (
            (
                cast(ushort) highFlags
                << 8
            ) |
            cast(ushort) lowFlags
        );

    const hasCrc =
        (flags & 0x8000) != 0;


    /*
     * The size and CRC flag describe one another and must agree.
     */
    if (
        (
            hasCrc &&
            size != 10
        ) ||
        (
            !hasCrc &&
            size != 6
        )
    )
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .inconsistentStructure,
                        highFlagsResult
                            .value
                            .sourceOffset
                    )
                );
    }


    auto paddingResult =
        probe.takeU32BE();

    if (paddingResult.hasError)
    {
        return
            ParseResult!Id3v23ExtendedHeader
                .failure(
                    paddingResult.error
                );
    }

    const paddingSize =
        paddingResult.value;


    uint crc32 =
        0;

    if (hasCrc)
    {
        auto crcResult =
            probe.takeU32BE();

        if (crcResult.hasError)
        {
            return
                ParseResult!Id3v23ExtendedHeader
                    .failure(
                        crcResult.error
                    );
        }

        crc32 =
            crcResult.value;
    }


    const consumedPhysical =
        probe.physicalPosition -
        startPhysicalPosition;

    const raw =
        rawStart.subspan(
            0,
            consumedPhysical
        );


    const result =
        Id3v23ExtendedHeader(
            sourceOffset,
            size,
            flags,
            paddingSize,
            crc32,
            raw
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23ExtendedHeader
            .success(result);
}


/// The six-byte form contains flags and padding size but no CRC.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * Extended-header size excludes these four bytes.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * No extended flags.
             */
            0x00, 0x00,

            /*
             * Padding size = 16.
             */
            0x00, 0x00, 0x00, 0x10,

            /*
             * Outside the extended header.
             */
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                100
            ),
            false
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.sourceOffset == 100);
    assert(header.size == 6);
    assert(header.logicalLength == 10);

    assert(header.flags == 0);
    assert(!header.hasCrc);

    assert(header.paddingSize == 16);
    assert(header.crc32 == 0);

    assert(header.raw.sourceOffset == 100);
    assert(header.raw.length == 10);

    assert(cursor.logicalPosition == 10);
    assert(cursor.physicalPosition == 10);
    assert(cursor.absoluteOffset == 110);

    assert(cursor.remainingRaw.data == [0x55]);
}


/// The ten-byte form contains an ordinary big-endian CRC-32.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00, 0x0A,

            /*
             * CRC present.
             */
            0x80, 0x00,

            /*
             * Padding size.
             */
            0x00, 0x00, 0x01, 0x00,

            /*
             * CRC-32.
             */
            0x12, 0x34, 0x56, 0x78
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                200
            ),
            false
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.size == 10);
    assert(header.logicalLength == 14);

    assert(header.flags == 0x8000);
    assert(header.hasCrc);

    assert(header.paddingSize == 256);
    assert(header.crc32 == 0x1234_5678);

    assert(header.raw.length == 14);

    assert(cursor.logicalPosition == 14);
    assert(cursor.physicalPosition == 14);
    assert(cursor.empty);
}


/// Only extended-header sizes six and ten are structurally defined.
unittest
{
    foreach (
        invalidSize;
        [
            0u,
            5u,
            7u,
            9u,
            11u
        ]
    )
    {
        ubyte[] bytes =
            [
                cast(ubyte)
                    (invalidSize >> 24),
                cast(ubyte)
                    (invalidSize >> 16),
                cast(ubyte)
                    (invalidSize >> 8),
                cast(ubyte)
                    invalidSize,

                0x00, 0x00,
                0x00, 0x00, 0x00, 0x00
            ];

        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    300
                ),
                false
            );

        auto result =
            cursor.parseId3v23ExtendedHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidLength
        );

        assert(result.error.offset == 300);

        assert(cursor.logicalPosition == 0);
        assert(cursor.physicalPosition == 0);
        assert(cursor.absoluteOffset == 300);
    }
}


/// Undefined bits in the first extended-flag byte are rejected.
unittest
{
    foreach (
        flags;
        [
            0x40,
            0x20,
            0x10,
            0x08,
            0x04,
            0x02,
            0x01
        ]
    )
    {
        const ubyte[] bytes =
            [
                0x00, 0x00, 0x00, 0x06,

                cast(ubyte) flags,
                0x00,

                0x00, 0x00, 0x00, 0x00
            ];

        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    400
                ),
                false
            );

        auto result =
            cursor.parseId3v23ExtendedHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidFlags
        );

        assert(result.error.offset == 404);

        assert(cursor.logicalPosition == 0);
        assert(cursor.physicalPosition == 0);
    }
}


/// Every bit in the second extended-flag byte is undefined.
unittest
{
    foreach (
        flags;
        [
            0x80,
            0x40,
            0x20,
            0x10,
            0x08,
            0x04,
            0x02,
            0x01
        ]
    )
    {
        const ubyte[] bytes =
            [
                0x00, 0x00, 0x00, 0x06,

                0x00,
                cast(ubyte) flags,

                0x00, 0x00, 0x00, 0x00
            ];

        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    bytes,
                    500
                ),
                false
            );

        auto result =
            cursor.parseId3v23ExtendedHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidFlags
        );

        assert(result.error.offset == 505);

        assert(cursor.logicalPosition == 0);
        assert(cursor.physicalPosition == 0);
    }
}


/// A CRC flag requires the ten-byte extended-header form.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00, 0x06,

            0x80, 0x00,

            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            false
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 604);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
}


/// The ten-byte form requires the CRC flag.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00,

            0x00, 0x00, 0x00, 0x00,

            0x12, 0x34, 0x56, 0x78
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                700
            ),
            false
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 704);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
}


/// Every truncation of the minimal logical structure fails atomically.
unittest
{
    const ubyte[] complete =
        [
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    foreach (
        length;
        0 .. complete.length
    )
    {
        auto cursor =
            Id3v23DataCursor(
                ByteSpan(
                    complete[
                        0 .. length
                    ],
                    800
                ),
                false
            );

        auto result =
            cursor.parseId3v23ExtendedHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.endOfSpan
        );

        assert(cursor.logicalPosition == 0);
        assert(cursor.physicalPosition == 0);
        assert(cursor.absoluteOffset == 800);
    }
}


/// A declared CRC must contain all four logical CRC bytes.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,

            0x00, 0x00, 0x00, 0x00,

            /*
             * CRC truncated to three bytes.
             */
            0x12, 0x34, 0x56
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                900
            ),
            false
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 913);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
}


/// Unsynchronisation may expand the physical padding-size field.
unittest
{
    /*
     * Logical padding-size bytes:
     *
     *   00 FF 00 02
     *
     * Physical representation:
     *
     *   00 FF 00 00 02
     */
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00, 0x06,

            0x00, 0x00,

            0x00,
            0xFF, 0x00,
            0x00,
            0x02,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.paddingSize == 0x00FF_0002);

    /*
     * Ten logical extended-header bytes occupy eleven physical bytes.
     */
    assert(header.logicalLength == 10);
    assert(header.raw.length == 11);

    assert(cursor.logicalPosition == 10);
    assert(cursor.physicalPosition == 11);
    assert(cursor.absoluteOffset == 1011);

    assert(cursor.remainingRaw.data == [0x55]);
}


/// Unsynchronisation may also expand the physical CRC field.
unittest
{
    /*
     * Logical CRC:
     *
     *   12 FF E1 34
     *
     * Physical representation:
     *
     *   12 FF 00 E1 34
     */
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00, 0x0A,

            0x80, 0x00,

            0x00, 0x00, 0x00, 0x00,

            0x12,
            0xFF, 0x00,
            0xE1,
            0x34,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            true
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.hasCrc);
    assert(header.crc32 == 0x12FF_E134);

    /*
     * Fourteen logical bytes occupy fifteen physical bytes.
     */
    assert(header.logicalLength == 14);
    assert(header.raw.length == 15);

    assert(cursor.logicalPosition == 14);
    assert(cursor.physicalPosition == 15);
    assert(cursor.absoluteOffset == 1115);

    assert(cursor.remainingRaw.data == [0x55]);
}


/// Absolute physical offsets survive a bounded parent subspan.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,

            0x55
        ];

    const span =
        ByteSpan(
            bytes,
            2000
        )
            .subspan(
                1,
                11
            );

    auto cursor =
        Id3v23DataCursor(
            span,
            false
        );

    auto result =
        cursor.parseId3v23ExtendedHeader();

    assert(result.hasValue);

    assert(
        result.value.sourceOffset ==
        2001
    );

    assert(
        result.value.raw.sourceOffset ==
        2001
    );

    assert(cursor.absoluteOffset == 2011);
    assert(cursor.remainingRaw.data == [0x55]);
}
