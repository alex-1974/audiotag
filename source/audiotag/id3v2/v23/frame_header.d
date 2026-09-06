/++
ID3v2.3 frame-header parsing.

This module parses only the fixed 10-byte frame header:

- four-byte frame identifier;
- four-byte unsigned big-endian frame size;
- two frame flag bytes.

Frame payload bounding and optional frame-format fields are handled by
later structural parsing stages.

Parsing is atomic: malformed or truncated frame headers leave the
caller's cursor unchanged.
+/
module audiotag.id3v2.v23.frame_header;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.numeric :
    readU32BE;

import audiotag.core.result :
    ParseResult;


/++
Parsed ID3v2.3 frame header.

`size` is the encoded frame-data size and excludes the ten-byte frame
header itself. Unlike ID3v2.4, the ID3v2.3 frame-size field is an
ordinary unsigned 32-bit big-endian integer rather than a synchsafe
integer.
+/
struct Id3v23FrameHeader
{
    /// Absolute source offset of the first frame-ID byte.
    size_t sourceOffset;

    /// Four-character ID3v2.3 frame identifier.
    char[4] id;

    /// Encoded frame-data size, excluding this header.
    uint size;

    /// Raw frame status flags.
    ubyte statusFlags;

    /// Raw frame format flags.
    ubyte formatFlags;


    /// Frame should be discarded if the tag is altered.
    @property
    bool discardOnTagAlter() const
        @safe pure nothrow @nogc
    {
        return
            (statusFlags & 0x80) != 0;
    }


    /// Frame should be discarded if the audio file is altered.
    @property
    bool discardOnFileAlter() const
        @safe pure nothrow @nogc
    {
        return
            (statusFlags & 0x40) != 0;
    }


    /// Frame contents are marked read-only.
    @property
    bool readOnly() const
        @safe pure nothrow @nogc
    {
        return
            (statusFlags & 0x20) != 0;
    }


    /// Frame data is compressed.
    @property
    bool compressed() const
        @safe pure nothrow @nogc
    {
        return
            (formatFlags & 0x80) != 0;
    }


    /// An encryption-method byte is present in the frame data.
    @property
    bool encrypted() const
        @safe pure nothrow @nogc
    {
        return
            (formatFlags & 0x40) != 0;
    }


    /// A grouping-identity byte is present in the frame data.
    @property
    bool hasGroupingIdentity() const
        @safe pure nothrow @nogc
    {
        return
            (formatFlags & 0x20) != 0;
    }
}


/++
Parses one ID3v2.3 frame header.

Frame identifiers may contain only uppercase ASCII letters `A`-`Z`
and digits `0`-`9`.

The frame size is an unsigned 32-bit big-endian integer and must be
non-zero. ID3v2.3 requires every frame to contain at least one byte of
frame data.

The status flag byte has the form `%abc00000`:

- bit 7: tag alter preservation;
- bit 6: file alter preservation;
- bit 5: read only.

The format flag byte has the form `%ijk00000`:

- bit 7: compression;
- bit 6: encryption;
- bit 5: grouping identity.

The lower five bits of each flag byte must be zero.

Params:
    cursor = Cursor positioned at the first byte of a frame header.

Returns:
    The parsed frame header or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23FrameHeader
parseId3v23FrameHeader(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto rawResult =
        probe.takeBytes(10);

    if (rawResult.hasError)
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    rawResult.error
                );
    }

    const raw =
        rawResult.value;

    const data =
        raw.data;

    char[4] id;

    foreach (
        index;
        0 .. 4
    )
    {
        const value =
            data[index];

        const valid =
            (
                value >= 'A' &&
                value <= 'Z'
            ) ||
            (
                value >= '0' &&
                value <= '9'
            );

        if (!valid)
        {
            return
                ParseResult!Id3v23FrameHeader
                    .failure(
                        ParseError(
                            ParseErrorCode
                                .invalidSignature,
                            raw.sourceOffset +
                                index
                        )
                    );
        }

        id[index] =
            cast(char) value;
    }

    /*
     * ID3v2.3 frame sizes are ordinary unsigned big-endian integers.
     * They are deliberately not decoded with readSynchsafe32().
     */
    auto sizeCursor =
        ByteCursor(
            raw.subspan(
                4,
                4
            )
        );

    auto sizeResult =
        sizeCursor.readU32BE();

    if (sizeResult.hasError)
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    sizeResult.error
                );
    }

    if (
        sizeResult.value == 0
    )
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidLength,
                        raw.sourceOffset + 4
                    )
                );
    }

    const statusFlags =
        data[8];

    const formatFlags =
        data[9];

    /*
     * ID3v2.3 status flags are %abc00000.
     */
    if (
        (statusFlags & 0x1F) != 0
    )
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidFlags,
                        raw.sourceOffset + 8
                    )
                );
    }

    /*
     * ID3v2.3 format flags are %ijk00000.
     */
    if (
        (formatFlags & 0x1F) != 0
    )
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidFlags,
                        raw.sourceOffset + 9
                    )
                );
    }

    const result =
        Id3v23FrameHeader(
            raw.sourceOffset,
            id,
            sizeResult.value,
            statusFlags,
            formatFlags
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23FrameHeader
            .success(result);
}


import audiotag.core.span :
    ByteSpan;


/// A normal ID3v2.3 frame header consumes exactly ten bytes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,
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
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.sourceOffset == 100);
    assert(header.id[] == "TIT2");
    assert(header.size == 3);
    assert(header.statusFlags == 0);
    assert(header.formatFlags == 0);

    assert(!header.discardOnTagAlter);
    assert(!header.discardOnFileAlter);
    assert(!header.readOnly);
    assert(!header.compressed);
    assert(!header.encrypted);
    assert(!header.hasGroupingIdentity);

    assert(cursor.position == 10);
    assert(cursor.absoluteOffset == 110);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// All defined ID3v2.3 status and format flags are exposed semantically.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x01,
            0xE0,
            0xE0
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.id[] == "ABC1");

    assert(header.discardOnTagAlter);
    assert(header.discardOnFileAlter);
    assert(header.readOnly);

    assert(header.compressed);
    assert(header.encrypted);
    assert(header.hasGroupingIdentity);
}


/// Frame headers truncated at any byte fail atomically.
unittest
{
    const ubyte[] complete =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00
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
            cursor.parseId3v23FrameHeader();

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


/// Every frame-ID position rejects bytes outside A-Z and 0-9.
unittest
{
    foreach (
        invalidIndex;
        0 .. 4
    )
    {
        foreach (
            invalidValue;
            [
                0x00,
                0x20,
                0x61,
                0x5F
            ]
        )
        {
            ubyte[] bytes =
                [
                    'T', 'I', 'T', '2',
                    0x00, 0x00, 0x00, 0x01,
                    0x00, 0x00
                ];

            bytes[invalidIndex] =
                cast(ubyte) invalidValue;

            auto cursor =
                ByteCursor(
                    ByteSpan(
                        bytes,
                        300
                    )
                );

            auto result =
                cursor.parseId3v23FrameHeader();

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
}


/// Digits are legal in ID3v2.3 frame identifiers.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'C', 'M', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);
    assert(result.value.id[] == "TCM1");
}


/// A frame size of zero is structurally invalid.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 404);
    assert(cursor.position == 0);
}


/// ID3v2.3 frame sizes use ordinary big-endian bytes, not synchsafe bytes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            /*
             * This high bit would be invalid in a synchsafe integer.
             * In ID3v2.3 it is an ordinary part of the uint value.
             */
            0x80, 0x00, 0x00, 0x00,

            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);
    assert(result.value.size == 0x8000_0000);
    assert(cursor.empty);
}


/// The complete non-zero 32-bit frame-size domain is accepted.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0xFF, 0xFF, 0xFF, 0xFF,
            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);
    assert(result.value.size == uint.max);
    assert(cursor.empty);
}


/// Every undefined ID3v2.3 status flag bit is rejected.
unittest
{
    foreach (
        flags;
        [
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
                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x01,
                cast(ubyte) flags,
                0x00
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    500
                )
            );

        auto result =
            cursor.parseId3v23FrameHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidFlags
        );

        assert(result.error.offset == 508);
        assert(cursor.position == 0);
    }
}


/// Every undefined ID3v2.3 format flag bit is rejected.
unittest
{
    foreach (
        flags;
        [
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
                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x01,
                0x00,
                cast(ubyte) flags
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    600
                )
            );

        auto result =
            cursor.parseId3v23FrameHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.invalidFlags
        );

        assert(result.error.offset == 609);
        assert(cursor.position == 0);
    }
}


/// Frame-header offsets remain absolute inside a parent region.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x01, 0x02,
            0x00, 0x00,

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
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);

    assert(
        result.value.sourceOffset ==
        1001
    );

    assert(result.value.id[] == "TIT2");
    assert(result.value.size == 0x0000_0102);

    assert(cursor.position == 11);
    assert(cursor.absoluteOffset == 1011);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;


/++
Parses one ID3v2.3 frame header from a logical tag-body cursor.

This overload is used when the enclosing ID3v2.3 tag body may be
unsynchronised. All ten frame-header bytes are therefore consumed from
the logical byte stream rather than directly from physical storage.

Physical source offsets are retained for diagnostics and provenance.

Params:
    cursor = Logical cursor positioned at the first frame-header byte.

Returns:
    The parsed frame header or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23FrameHeader
parseId3v23FrameHeader(
    ref Id3v23DataCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    const sourceOffset =
        probe.absoluteOffset;

    char[4] id;

    foreach (
        index;
        0 .. 4
    )
    {
        auto byteResult =
            probe.takeByte();

        if (byteResult.hasError)
        {
            return
                ParseResult!Id3v23FrameHeader
                    .failure(
                        byteResult.error
                    );
        }

        const decoded =
            byteResult.value;

        const value =
            decoded.value;

        const valid =
            (
                value >= 'A' &&
                value <= 'Z'
            ) ||
            (
                value >= '0' &&
                value <= '9'
            );

        if (!valid)
        {
            return
                ParseResult!Id3v23FrameHeader
                    .failure(
                        ParseError(
                            ParseErrorCode
                                .invalidSignature,
                            decoded.sourceOffset
                        )
                    );
        }

        id[index] =
            cast(char) value;
    }

    /*
     * The v2.3 frame-size field is a normal U32BE value. With
     * tag-level unsynchronisation active its four logical bytes may
     * occupy more than four physical source bytes.
     */
    const sizeOffset =
        probe.absoluteOffset;

    auto sizeResult =
        probe.takeU32BE();

    if (sizeResult.hasError)
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    sizeResult.error
                );
    }

    if (
        sizeResult.value == 0
    )
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidLength,
                        sizeOffset
                    )
                );
    }

    auto statusResult =
        probe.takeByte();

    if (statusResult.hasError)
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    statusResult.error
                );
    }

    const statusFlags =
        statusResult.value.value;

    if (
        (statusFlags & 0x1F) != 0
    )
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidFlags,
                        statusResult
                            .value
                            .sourceOffset
                    )
                );
    }

    auto formatResult =
        probe.takeByte();

    if (formatResult.hasError)
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    formatResult.error
                );
    }

    const formatFlags =
        formatResult.value.value;

    if (
        (formatFlags & 0x1F) != 0
    )
    {
        return
            ParseResult!Id3v23FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidFlags,
                        formatResult
                            .value
                            .sourceOffset
                    )
                );
    }

    const result =
        Id3v23FrameHeader(
            sourceOffset,
            id,
            sizeResult.value,
            statusFlags,
            formatFlags
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23FrameHeader
            .success(result);
}


/// Logical frame-header parsing is identical without unsynchronisation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                3000
            ),
            false
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.sourceOffset == 3000);
    assert(header.id[] == "TIT2");
    assert(header.size == 3);
    assert(header.statusFlags == 0);
    assert(header.formatFlags == 0);

    assert(cursor.logicalPosition == 10);
    assert(cursor.physicalPosition == 10);
    assert(cursor.absoluteOffset == 3010);
    assert(cursor.remainingPhysical == 1);
}


/// Unsynchronisation may expand bytes inside the frame-size field.
unittest
{
    /*
     * Logical header:
     *
     *   TIT2 FF 00 00 01 00 00
     *
     * Physical header after tag-level unsynchronisation:
     *
     *   TIT2 FF 00 00 00 01 00 00
     *
     * The logical frame size is therefore $FF000001.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            0xFF,
            0x00,
            0x00,
            0x00,
            0x01,

            0x00,
            0x00,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                3100
            ),
            true
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasValue);

    assert(
        result.value.size ==
        0xFF00_0001
    );

    assert(cursor.logicalPosition == 10);
    assert(cursor.physicalPosition == 11);
    assert(cursor.absoluteOffset == 3111);

    assert(cursor.remainingPhysical == 1);
    assert(cursor.remainingRaw.data == [0x55]);
}


/// Logical header failures preserve both logical and physical positions.
unittest
{
    /*
     * The size begins with an unsynchronised $FF but the logical
     * header ends before all four logical size bytes are available.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0xFF, 0x00,
            0x01
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                3200
            ),
            true
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 3200);
}


/// Logical flag diagnostics retain physical offsets after stuffing.
unittest
{
    /*
     * Stuffing occurs in the size field, shifting the physical status
     * byte by one relative to its logical position.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',

            0xFF, 0x00,
            0x00, 0x00, 0x01,

            0x01,
            0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                3300
            ),
            true
        );

    auto result =
        cursor.parseId3v23FrameHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidFlags
    );

    /*
     * Four ID bytes occupy offsets 3300..3303.
     * The logical four-byte size occupies five physical bytes
     * 3304..3308. Status therefore begins at 3309.
     */
    assert(result.error.offset == 3309);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
}
