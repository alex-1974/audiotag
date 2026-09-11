/++
Bounded ID3v2.2 frame-envelope parsing.

This module parses one fixed ID3v2.2 frame header and then bounds exactly the
number of frame-data bytes declared by that header.

The frame data remains opaque. Text decoding, picture parsing and other
semantic frame contents are handled by later parsing stages.

This ByteCursor-based parser operates on a byte stream in which frame-header
and frame-data lengths are directly addressable. Whole-tag ID3v2.2
unsynchronisation requires a later logical cursor so that logical frame sizes
can still preserve the expanded physical source representation.

Parsing is atomic: malformed or truncated frames leave the caller's cursor
unchanged.
+/
module audiotag.id3v2.v22.frame;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.frame_header :
    Id3v22FrameHeader,
    parseId3v22FrameHeader;


/++
The bounded outer structure of one ID3v2.2 frame.

`data` contains exactly `header.size` bytes from the byte stream supplied to
this parser.
+/
struct Id3v22FrameEnvelope
{
    /// Parsed six-byte ID3v2.2 frame header.
    Id3v22FrameHeader header;

    /// Complete bounded frame-data region.
    ByteSpan data;


    /// Absolute source offset immediately following this frame.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            data.sourceOffset +
            data.length;
    }
}


/++
Parses and bounds one complete ID3v2.2 frame.

The declared 24-bit frame size is interpreted only as a length inside the
caller's already bounded parent region. Parsing succeeds only when the
complete declared frame-data region is available.

This overload does not perform whole-tag unsynchronisation decoding. A later
logical-cursor overload will provide that behavior while preserving physical
source provenance.

Params:
    cursor = Cursor positioned at the first byte of a frame header.

Returns:
    The parsed frame envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22FrameEnvelope
parseId3v22FrameEnvelope(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto headerResult =
        probe.parseId3v22FrameHeader();

    if (headerResult.hasError)
    {
        return
            ParseResult!Id3v22FrameEnvelope
                .failure(
                    headerResult.error
                );
    }

    const header =
        headerResult.value;

    auto dataResult =
        probe.takeBytes(
            header.size
        );

    if (dataResult.hasError)
    {
        return
            ParseResult!Id3v22FrameEnvelope
                .failure(
                    dataResult.error
                );
    }

    const frame =
        Id3v22FrameEnvelope(
            header,
            dataResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v22FrameEnvelope
            .success(frame);
}


/// A complete frame exposes exactly the declared data region.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x03,

            0x01, 0x02, 0x03,

            0x99
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.sourceOffset == 100);
    assert(frame.header.id[] == "TT2");
    assert(frame.header.size == 3);

    assert(frame.data.sourceOffset == 106);
    assert(frame.data.length == 3);

    assert(
        frame.data.data ==
        [0x01, 0x02, 0x03]
    );

    assert(frame.endOffset == 109);

    assert(cursor.absoluteOffset == 109);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x99);
}


/// A one-byte ID3v2.2 frame is structurally valid.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L',
            0x00, 0x00, 0x01,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasValue);
    assert(result.value.header.size == 1);
    assert(result.value.data.length == 1);
    assert(result.value.data.data[0] == 0x55);

    assert(cursor.absoluteOffset == 207);
    assert(cursor.empty);
}


/// A frame may end exactly at the end of its parent region.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', '1',
            0x00, 0x00, 0x02,

            0xAA, 0xBB
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasValue);
    assert(result.value.endOffset == 308);
    assert(cursor.empty);
}


/// A truncated frame-data region leaves the original cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x05,

            0x11, 0x22
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 406);
    assert(result.error.requested == 5);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 400);
    assert(cursor.remaining == bytes.length);
}


/// Header errors propagate without consuming the caller's cursor.
unittest
{
    const ubyte[] bytes =
        [
            't', 'T', '2',
            0x00, 0x00, 0x01,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 500);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// Unknown but structurally valid frame identifiers remain opaque.
unittest
{
    const ubyte[] bytes =
        [
            'Z', '9', 'X',
            0x00, 0x00, 0x04,

            0xDE, 0xAD, 0xBE, 0xEF
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.id[] == "Z9X");
    assert(frame.data.sourceOffset == 606);
    assert(frame.data.length == 4);

    assert(
        frame.data.data ==
        [0xDE, 0xAD, 0xBE, 0xEF]
    );

    assert(cursor.empty);
}


/// Frame-envelope offsets remain absolute after prior cursor movement.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'U', 'F', 'I',
            0x00, 0x00, 0x02,

            0xAA, 0xBB,

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
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.sourceOffset == 1001);
    assert(frame.data.sourceOffset == 1007);
    assert(frame.endOffset == 1009);

    assert(cursor.position == 9);
    assert(cursor.absoluteOffset == 1009);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// The largest possible declared v2.2 frame size is still bounded by input.
unittest
{
    const ubyte[] bytes =
        [
            'G', 'E', 'O',
            0xFF, 0xFF, 0xFF,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                2000
            )
        );

    auto result =
        cursor.parseId3v22FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 2006);
    assert(result.error.requested == 0xFF_FF_FF);
    assert(result.error.available == 1);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 2000);
}
