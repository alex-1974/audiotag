/++
ID3v2.2 frame-sequence and padding parsing for directly addressable bytes.

This module validates one already bounded ID3v2.2 frames-and-padding region
when whole-tag unsynchronisation has not been applied to the supplied byte
stream.

The region is partitioned into:

- one or more complete ID3v2.2 frames;
- optional trailing zero padding.

Frame payloads remain opaque. Whole-tag unsynchronisation requires a later
logical cursor and is intentionally not handled by this ByteSpan parser.
+/
module audiotag.id3v2.v22.frame_sequence;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.frame :
    parseId3v22FrameEnvelope;


/++
Validated structural layout of an ID3v2.2 frame sequence.

`frameBytes` contains exactly all complete frames in their original source
representation and excludes padding.

`padding` contains only trailing zero bytes. When no padding is present it is
an empty span positioned immediately after the final frame.

`frameCount` counts complete parsed frames.
+/
struct Id3v22FrameSequenceLayout
{
    ByteSpan frameBytes;
    ByteSpan padding;
    size_t frameCount;
}


/++
Validates and partitions an ID3v2.2 frames-and-padding region.

ID3v2.2 requires at least one complete frame. Padding is optional, may occur
only after the final frame, and consists entirely of zero bytes.

This overload expects directly addressable logical bytes. It must not be used
to interpret a physical whole-tag-unsynchronised body before that body has
been exposed through the later logical-cursor layer.

Params:
    region = Already bounded frames-and-padding region.

Returns:
    The validated layout or a structured parse error.

Safety:
    Frame parsing cannot read beyond `region`.
+/
ParseResult!Id3v22FrameSequenceLayout
parseId3v22FrameSequenceLayout(
    ByteSpan region
)
    @safe pure nothrow @nogc
{
    auto cursor =
        ByteCursor(region);

    size_t frameCount =
        0;

    while (!cursor.empty)
    {
        const boundary =
            cursor.position;

        if (
            cursor.front ==
            0x00
        )
        {
            if (
                frameCount ==
                0
            )
            {
                return
                    ParseResult!Id3v22FrameSequenceLayout
                        .failure(
                            ParseError(
                                ParseErrorCode.invalidLength,
                                region.sourceOffset
                            )
                        );
            }

            while (!cursor.empty)
            {
                if (
                    cursor.front !=
                    0x00
                )
                {
                    return
                        ParseResult!Id3v22FrameSequenceLayout
                            .failure(
                                ParseError(
                                    ParseErrorCode
                                        .inconsistentStructure,
                                    cursor.absoluteOffset
                                )
                            );
                }

                cursor.popFront();
            }

            const frameBytes =
                region.subspan(
                    0,
                    boundary
                );

            const padding =
                region.subspan(
                    boundary,
                    region.length -
                        boundary
                );

            return
                ParseResult!Id3v22FrameSequenceLayout
                    .success(
                        Id3v22FrameSequenceLayout(
                            frameBytes,
                            padding,
                            frameCount
                        )
                    );
        }

        auto frameResult =
            cursor.parseId3v22FrameEnvelope();

        if (frameResult.hasError)
        {
            return
                ParseResult!Id3v22FrameSequenceLayout
                    .failure(
                        frameResult.error
                    );
        }

        ++frameCount;
    }

    if (
        frameCount ==
        0
    )
    {
        return
            ParseResult!Id3v22FrameSequenceLayout
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        region.sourceOffset
                    )
                );
    }

    const padding =
        region.subspan(
            region.length,
            0
        );

    return
        ParseResult!Id3v22FrameSequenceLayout
            .success(
                Id3v22FrameSequenceLayout(
                    region,
                    padding,
                    frameCount
                )
            );
}


/// Multiple complete frames may occupy the complete region.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x11,

            'T', 'P', '1',
            0x00, 0x00, 0x02,
            0x22, 0x33
        ];

    const region =
        ByteSpan(
            bytes,
            100
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 2);
    assert(layout.frameBytes.sourceOffset == 100);
    assert(layout.frameBytes.length == bytes.length);
    assert(layout.frameBytes.data == bytes);
    assert(layout.padding.empty);
    assert(layout.padding.sourceOffset == 115);
}


/// Trailing zero bytes are separated from the frame sequence.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L',
            0x00, 0x00, 0x01,
            0x55,

            0x00, 0x00, 0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            200
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);
    assert(layout.frameBytes.sourceOffset == 200);
    assert(layout.frameBytes.length == 7);
    assert(layout.padding.sourceOffset == 207);
    assert(layout.padding.length == 4);

    assert(
        layout.padding.data ==
        [0x00, 0x00, 0x00, 0x00]
    );
}


/// Zero bytes inside bounded frame data are not mistaken for padding.
unittest
{
    const ubyte[] bytes =
        [
            'X', '0', '1',
            0x00, 0x00, 0x03,

            0x00, 0x00, 0x55,

            0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            300
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);
    assert(layout.frameBytes.length == 9);
    assert(layout.padding.sourceOffset == 309);
    assert(layout.padding.length == 2);
}


/// An empty region cannot form a valid ID3v2.2 tag body.
unittest
{
    const ubyte[] bytes = [];

    const region =
        ByteSpan(
            bytes,
            400
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 400);
}


/// Padding without a preceding frame is invalid.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            500
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 500);
}


/// A non-zero byte after padding begins is rejected at its exact offset.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            0x00, 0x00,
            0x42,
            0x00
        ];

    const region =
        ByteSpan(
            bytes,
            600
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 609);
}


/// Truncated frame data propagates its bounded-read failure.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x04,

            0x11, 0x22
        ];

    const region =
        ByteSpan(
            bytes,
            700
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 706);
    assert(result.error.requested == 4);
    assert(result.error.available == 2);
}


/// Invalid frame headers propagate their exact structural error.
unittest
{
    const ubyte[] bytes =
        [
            't', 'T', '2',
            0x00, 0x00, 0x01,
            0x55
        ];

    const region =
        ByteSpan(
            bytes,
            800
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 800);
}


/// Absolute frame and padding offsets survive a non-zero source origin.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x02,
            0xAA, 0xBB,

            'T', 'R', 'K',
            0x00, 0x00, 0x01,
            0x04,

            0x00, 0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            1000
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 2);
    assert(layout.frameBytes.sourceOffset == 1000);
    assert(layout.frameBytes.length == 15);
    assert(layout.padding.sourceOffset == 1015);
    assert(layout.padding.length == 3);
}
