/++
ID3v2.2 frame-header parsing.

This module parses only the fixed six-byte ID3v2.2 frame header:

- three-byte frame identifier;
- three-byte unsigned big-endian frame-data size.

Frame payload bounding, frame-sequence parsing and padding handling belong to
later structural stages.

Parsing is atomic: malformed or truncated frame headers leave the caller's
cursor unchanged.
+/
module audiotag.id3v2.v22.frame_header;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.numeric :
    readU24BE;

import audiotag.core.result :
    ParseResult;


/++
Parsed ID3v2.2 frame header.

`size` is the encoded frame-data size and excludes this six-byte frame header.
The value occupies an ordinary unsigned 24-bit big-endian field.
+/
struct Id3v22FrameHeader
{
    /// Absolute source offset of the first frame-ID byte.
    size_t sourceOffset;

    /// Three-character ID3v2.2 frame identifier.
    char[3] id;

    /// Encoded frame-data size, excluding this header.
    uint size;
}


/++
Parses one ID3v2.2 frame header.

Frame identifiers may contain only uppercase ASCII letters `A`-`Z` and digits
`0`-`9`. Identifiers beginning with `X`, `Y` or `Z` are therefore accepted
like every other structurally valid identifier; interpretation is a later
semantic concern.

The frame size is an ordinary unsigned 24-bit big-endian integer and must be
non-zero. ID3v2.2 requires every frame to contain at least one byte of frame
data.

Padding is not a frame header. A zero-filled region will therefore fail this
parser and must be recognized by the later frame-sequence layer before calling
this function.

Params:
    cursor = Cursor positioned at the first byte of a frame header.

Returns:
    The parsed frame header or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22FrameHeader
parseId3v22FrameHeader(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto rawResult =
        probe.takeBytes(6);

    if (rawResult.hasError)
    {
        return
            ParseResult!Id3v22FrameHeader
                .failure(
                    rawResult.error
                );
    }

    const raw =
        rawResult.value;

    const data =
        raw.data;

    char[3] id;

    foreach (
        index;
        0 .. 3
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
                ParseResult!Id3v22FrameHeader
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
     * ID3v2.2 frame sizes are ordinary unsigned 24-bit big-endian integers.
     * They are deliberately not synchsafe values.
     */
    auto sizeCursor =
        ByteCursor(
            raw.subspan(
                3,
                3
            )
        );

    auto sizeResult =
        sizeCursor.readU24BE();

    if (sizeResult.hasError)
    {
        return
            ParseResult!Id3v22FrameHeader
                .failure(
                    sizeResult.error
                );
    }

    if (
        sizeResult.value == 0
    )
    {
        return
            ParseResult!Id3v22FrameHeader
                .failure(
                    ParseError(
                        ParseErrorCode
                            .invalidLength,
                        raw.sourceOffset + 3
                    )
                );
    }

    const header =
        Id3v22FrameHeader(
            raw.sourceOffset,
            id,
            sizeResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v22FrameHeader
            .success(header);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;
}


/// A minimal frame header consumes exactly six bytes.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
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
        cursor.parseId3v22FrameHeader();

    assert(result.hasValue);

    const header =
        result.value;

    assert(header.sourceOffset == 100);

    assert(
        header.id[] ==
        "TT2"
    );

    assert(header.size == 1);

    assert(cursor.position == 6);
    assert(cursor.absoluteOffset == 106);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// The frame size is decoded as an ordinary 24-bit big-endian integer.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'I', 'C',
            0x01, 0x02, 0x03
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v22FrameHeader();

    assert(result.hasValue);
    assert(result.value.size == 0x01_02_03);
    assert(cursor.empty);
}


/// The complete 24-bit frame-size domain above zero is accepted.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0xFF, 0xFF, 0xFF
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto result =
        cursor.parseId3v22FrameHeader();

    assert(result.hasValue);
    assert(result.value.size == 0xFF_FF_FF);
    assert(cursor.empty);
}


/// Experimental identifiers are structurally valid frame identifiers.
unittest
{
    foreach (
        identifier;
        ["X01", "Y99", "ZAB"]
    )
    {
        const ubyte[] bytes =
            [
                cast(ubyte) identifier[0],
                cast(ubyte) identifier[1],
                cast(ubyte) identifier[2],
                0x00, 0x00, 0x01
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto result =
            cursor.parseId3v22FrameHeader();

        assert(result.hasValue);

        assert(
            result.value.id[] ==
            identifier
        );
    }
}


/// Truncated frame headers fail atomically at every possible length.
unittest
{
    const ubyte[] complete =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01
        ];

    foreach (
        length;
        0 .. 6
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
            cursor.parseId3v22FrameHeader();

        assert(result.hasError);

        assert(
            result.error.code ==
            ParseErrorCode.endOfSpan
        );

        assert(result.error.offset == 200);
        assert(result.error.requested == 6);
        assert(result.error.available == length);

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 200);
        assert(cursor.remaining == length);
    }
}


/// Invalid frame-ID bytes report their exact absolute source offset.
unittest
{
    foreach (
        invalidIndex;
        0 .. 3
    )
    {
        ubyte[] bytes =
            [
                'T', 'T', '2',
                0x00, 0x00, 0x01
            ];

        bytes[invalidIndex] =
            'a';

        auto cursor =
            ByteCursor(
                ByteSpan(
                    bytes,
                    300
                )
            );

        auto result =
            cursor.parseId3v22FrameHeader();

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


/// Padding bytes are not accepted as a frame header.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00,
            0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v22FrameHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 400);
    assert(cursor.position == 0);
}


/// A zero-length frame is rejected atomically at its size field.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v22FrameHeader();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 503);
    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// Frame-header parsing retains absolute offsets after prior cursor movement.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'T', 'R', 'K',
            0x00, 0x01, 0x00,

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
        cursor.parseId3v22FrameHeader();

    assert(result.hasValue);

    assert(
        result.value.sourceOffset ==
        1001
    );

    assert(
        result.value.id[] ==
        "TRK"
    );

    assert(result.value.size == 256);

    assert(cursor.position == 7);
    assert(cursor.absoluteOffset == 1007);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}
