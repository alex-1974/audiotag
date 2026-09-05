/++
Bounded ID3v2.4 frame-envelope parsing.

This module parses one fixed frame header and then bounds exactly the
number of frame-data bytes declared by that header.

The frame data remains opaque. Grouping identity, encryption method,
data-length indicator and semantic frame contents are handled by later
parsing stages.

Parsing is atomic: malformed or truncated frames leave the caller's
cursor unchanged.
+/
module audiotag.id3v2.v24.frame;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;
import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader,
    parseId3v24FrameHeader;


/++
The bounded outer structure of one ID3v2.4 frame.

`data` contains exactly `header.size` bytes and therefore includes any
optional format fields encoded before the frame's semantic content.
+/
struct Id3v24FrameEnvelope
{
    /// Parsed ten-byte frame header.
    Id3v24FrameHeader header;

    /// Complete bounded frame-data region.
    ByteSpan data;

    /// Absolute offset immediately following this frame.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return data.sourceOffset + data.length;
    }
}


/++
Parses and bounds one complete ID3v2.4 frame.

Params:
    cursor = Cursor positioned at the first byte of a frame header.

Returns:
    The parsed frame envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24FrameEnvelope parseId3v24FrameEnvelope(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto headerResult =
        probe.parseId3v24FrameHeader();

    if (headerResult.hasError)
    {
        return ParseResult!Id3v24FrameEnvelope.failure(
            headerResult.error
        );
    }

    const header = headerResult.value;

    auto dataResult =
        probe.takeBytes(header.size);

    if (dataResult.hasError)
    {
        return ParseResult!Id3v24FrameEnvelope.failure(
            dataResult.error
        );
    }

    const frame = Id3v24FrameEnvelope(
        header,
        dataResult.value
    );

    cursor = probe;

    return ParseResult!Id3v24FrameEnvelope.success(frame);
}


/// A complete frame exposes exactly the declared data region.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x00,

         0x01, 0x02, 0x03,

         0x99];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasValue);

    const frame = result.value;

    assert(frame.header.sourceOffset == 100);
    assert(frame.header.id[] == "TIT2");
    assert(frame.header.size == 3);

    assert(frame.data.sourceOffset == 110);
    assert(frame.data.length == 3);
    assert(frame.data.data == [0x01, 0x02, 0x03]);

    assert(frame.endOffset == 113);

    assert(cursor.absoluteOffset == 113);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x99);
}


/// A one-byte frame is structurally valid.
unittest
{
    const ubyte[] bytes =
        ['T', 'A', 'L', 'B',
         0x00, 0x00, 0x00, 0x01,
         0x00, 0x00,

         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));
    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasValue);
    assert(result.value.header.size == 1);
    assert(result.value.data.length == 1);
    assert(result.value.data.data[0] == 0x55);

    assert(cursor.absoluteOffset == 211);
    assert(cursor.empty);
}


/// A frame may end exactly at the end of its parent region.
unittest
{
    const ubyte[] bytes =
        ['T', 'P', 'E', '1',
         0x00, 0x00, 0x00, 0x02,
         0x00, 0x00,

         0xAA, 0xBB];

    auto cursor = ByteCursor(ByteSpan(bytes, 300));
    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasValue);
    assert(result.value.endOffset == 312);
    assert(cursor.empty);
}


/// A truncated frame-data region leaves the original cursor unchanged.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x05,
         0x00, 0x00,

         0x11, 0x22];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));
    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    // Header was parsed on the probe cursor. The exact data read then
    // failed at the first byte after the header.
    assert(result.error.offset == 410);
    assert(result.error.requested == 5);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 400);
    assert(cursor.remaining == bytes.length);
}


/// Header errors are propagated without consuming the caller's cursor.
unittest
{
    const ubyte[] bytes =
        ['t', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x01,
         0x00, 0x00,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));
    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
    assert(result.error.offset == 500);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 500);
}


/// Optional frame-format bytes remain inside the bounded data region.
unittest
{
    // Grouping + compression + encryption + DLI.
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x07,
         0x00,
         0x4D,

         // These are still opaque frame data at this layer.
         0x12,
         0x34,
         0x00, 0x00, 0x00, 0x03,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 600));
    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasValue);

    const frame = result.value;

    assert(frame.header.hasGroupingIdentity);
    assert(frame.header.compressed);
    assert(frame.header.encrypted);
    assert(frame.header.hasDataLengthIndicator);

    assert(frame.data.sourceOffset == 610);
    assert(frame.data.length == 7);

    assert(
        frame.data.data ==
        [0x12,
         0x34,
         0x00, 0x00, 0x00, 0x03,
         0x55]
    );
}


/// Absolute offsets survive parsing inside a bounded parent region.
unittest
{
    const ubyte[] bytes =
        [0x99,

         'T', 'C', 'O', 'N',
         0x00, 0x00, 0x00, 0x02,
         0x00, 0x00,

         0x11, 0x22,

         0xAA];

    auto cursor = ByteCursor(ByteSpan(bytes, 1000));
    cursor.popFront();

    auto result = cursor.parseId3v24FrameEnvelope();

    assert(result.hasValue);

    assert(result.value.header.sourceOffset == 1001);
    assert(result.value.data.sourceOffset == 1011);
    assert(result.value.endOffset == 1013);

    assert(cursor.absoluteOffset == 1013);
    assert(cursor.front == 0xAA);
}
