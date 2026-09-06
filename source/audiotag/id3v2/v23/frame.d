/++
Bounded ID3v2.3 frame-envelope parsing.

This module parses one fixed ID3v2.3 frame header and then bounds
exactly the number of frame-data bytes declared by that header.

The frame data remains opaque. Compression size, encryption method,
grouping identity and semantic frame contents are handled by later
parsing stages.

Parsing is atomic: malformed or truncated frames leave the caller's
cursor unchanged.
+/
module audiotag.id3v2.v23.frame;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader,
    parseId3v23FrameHeader;


/++
The bounded outer structure of one ID3v2.3 frame.

`data` contains exactly `header.size` bytes and therefore includes any
optional ID3v2.3 frame-format fields encoded before the semantic frame
content.
+/
struct Id3v23FrameEnvelope
{
    /// Parsed ten-byte ID3v2.3 frame header.
    Id3v23FrameHeader header;

    /// Complete bounded frame-data region.
    ByteSpan data;


    /// Absolute offset immediately following this frame.
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
Parses and bounds one complete ID3v2.3 frame.

The declared frame size is interpreted only as a length inside the
caller's already bounded parent region. A frame may therefore declare
any non-zero 32-bit size, but parsing succeeds only when that many bytes
are actually available.

Params:
    cursor = Cursor positioned at the first byte of a frame header.

Returns:
    The parsed frame envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23FrameEnvelope
parseId3v23FrameEnvelope(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto headerResult =
        probe.parseId3v23FrameHeader();

    if (headerResult.hasError)
    {
        return
            ParseResult!Id3v23FrameEnvelope
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
            ParseResult!Id3v23FrameEnvelope
                .failure(
                    dataResult.error
                );
    }

    const frame =
        Id3v23FrameEnvelope(
            header,
            dataResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23FrameEnvelope
            .success(frame);
}


/// A complete frame exposes exactly the declared data region.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.sourceOffset == 100);
    assert(frame.header.id[] == "TIT2");
    assert(frame.header.size == 3);

    assert(frame.data.sourceOffset == 110);
    assert(frame.data.length == 3);

    assert(
        frame.data.data ==
        [0x01, 0x02, 0x03]
    );

    assert(frame.endOffset == 113);

    assert(cursor.absoluteOffset == 113);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x99);
}


/// A one-byte ID3v2.3 frame is structurally valid.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    assert(
        result.value.header.size ==
        1
    );

    assert(
        result.value.data.length ==
        1
    );

    assert(
        result.value.data.data[0] ==
        0x55
    );

    assert(cursor.absoluteOffset == 211);
    assert(cursor.empty);
}


/// A frame may end exactly at the end of its parent region.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    assert(
        result.value.endOffset ==
        312
    );

    assert(cursor.empty);
}


/// A truncated frame-data region leaves the original cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    /*
     * The header was parsed on the probe cursor. The exact data read
     * then failed at the first byte after the header.
     */
    assert(result.error.offset == 410);
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
            't', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 500);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// ID3v2.3 optional format bytes remain inside the bounded data region.
unittest
{
    /*
     * Compression + encryption + grouping are signalled in the header.
     *
     * Their format-specific prefix bytes are deliberately opaque here:
     *
     *   4-byte decompressed size
     *   1-byte encryption method
     *   1-byte grouping identity
     *   remaining semantic payload
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x08,
            0x00, 0xE0,

            0x00, 0x00, 0x00, 0x10,
            0x07,
            0x22,
            0xAA, 0xBB
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto result =
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.compressed);
    assert(frame.header.encrypted);
    assert(frame.header.hasGroupingIdentity);

    assert(frame.data.sourceOffset == 610);
    assert(frame.data.length == 8);

    assert(
        frame.data.data ==
        [
            0x00, 0x00, 0x00, 0x10,
            0x07,
            0x22,
            0xAA, 0xBB
        ]
    );

    assert(cursor.empty);
}


/// Frame-envelope offsets remain absolute after prior cursor movement.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(
        frame.header.sourceOffset ==
        1001
    );

    assert(
        frame.data.sourceOffset ==
        1011
    );

    assert(frame.endOffset == 1013);

    assert(cursor.position == 13);
    assert(cursor.absoluteOffset == 1013);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// Large declared sizes are bounded by the available parent span.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0xFF, 0xFF, 0xFF, 0xFF,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 2010);

    assert(
        result.error.requested ==
        uint.max
    );

    assert(result.error.available == 1);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 2000);
}


import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;


/++
Parses and bounds one complete ID3v2.3 frame from a logical tag-body
cursor.

The ten-byte frame header and the declared frame-data length are both
interpreted in the logical byte stream. The returned `data` span
preserves the complete physical source representation, including any
ID3v2.3 unsynchronisation stuffing bytes.

Params:
    cursor = Logical cursor positioned at the first frame-header byte.

Returns:
    The parsed frame envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23FrameEnvelope
parseId3v23FrameEnvelope(
    ref Id3v23DataCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    auto headerResult =
        probe.parseId3v23FrameHeader();

    if (headerResult.hasError)
    {
        return
            ParseResult!Id3v23FrameEnvelope
                .failure(
                    headerResult.error
                );
    }

    const header =
        headerResult.value;

    auto dataResult =
        probe.takeLogicalRegion(
            header.size
        );

    if (dataResult.hasError)
    {
        return
            ParseResult!Id3v23FrameEnvelope
                .failure(
                    dataResult.error
                );
    }

    const frame =
        Id3v23FrameEnvelope(
            header,
            dataResult.value
        );

    cursor =
        probe;

    return
        ParseResult!Id3v23FrameEnvelope
            .success(frame);
}


/// Logical frame envelopes are unchanged without unsynchronisation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x11, 0x22, 0x33,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                4000
            ),
            false
        );

    auto result =
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.id[] == "TIT2");
    assert(frame.header.size == 3);

    assert(frame.data.sourceOffset == 4010);
    assert(frame.data.length == 3);

    assert(
        frame.data.data ==
        [0x11, 0x22, 0x33]
    );

    assert(frame.endOffset == 4013);

    assert(cursor.logicalPosition == 13);
    assert(cursor.physicalPosition == 13);
    assert(cursor.absoluteOffset == 4013);

    assert(cursor.remainingRaw.data == [0x55]);
}


/// Unsynchronised frame data preserves its expanded physical region.
unittest
{
    /*
     * Logical frame payload:
     *
     *   11 FF E1
     *
     * Physical payload:
     *
     *   11 FF 00 E1
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x11,
            0xFF, 0x00,
            0xE1,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                4100
            ),
            true
        );

    auto result =
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    const frame =
        result.value;

    assert(frame.header.size == 3);

    assert(frame.data.sourceOffset == 4110);

    /*
     * Three logical payload bytes occupy four physical bytes.
     */
    assert(frame.data.length == 4);

    assert(
        frame.data.data ==
        [
            0x11,
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(frame.endOffset == 4114);

    assert(cursor.logicalPosition == 13);
    assert(cursor.physicalPosition == 14);
    assert(cursor.absoluteOffset == 4114);

    assert(cursor.remainingRaw.data == [0x55]);
}


/// Stuffing in both header and payload is handled in one logical frame.
unittest
{
    /*
     * Logical frame:
     *
     *   ABC1
     *   00 00 00 03
     *   00 00
     *   FF E1 42
     *
     * Only the payload requires stuffing in this particular example.
     * The test verifies that one logical cursor owns both stages.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0xFF, 0x00,
            0xE1,
            0x42
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                4200
            ),
            true
        );

    auto result =
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasValue);

    assert(result.value.header.id[] == "ABC1");
    assert(result.value.header.size == 3);

    assert(result.value.data.length == 4);

    assert(cursor.logicalPosition == 13);
    assert(cursor.physicalPosition == 14);
    assert(cursor.empty);
}


/// Truncated logical frame data leaves the original cursor unchanged.
unittest
{
    /*
     * Declared logical payload size is three bytes, but only two
     * logical bytes are present despite three physical bytes.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0xFF, 0x00,
            0x42
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                4300
            ),
            true
        );

    auto result =
        cursor.parseId3v23FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 4313);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 4300);
}
