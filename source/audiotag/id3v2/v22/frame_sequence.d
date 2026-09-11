/++
ID3v2.2 frame-sequence and padding parsing.

This module validates one already bounded physical ID3v2.2
frames-and-padding region, with optional whole-tag unsynchronisation decoding
through the logical data cursor.

The region is partitioned into:

- one or more complete ID3v2.2 frames;
- optional trailing zero padding.

Frame payloads remain opaque. Frame boundaries and padding are recognized in
the logical byte stream so physical unsynchronisation stuffing remains part of
the preserved source representation without being mistaken for padding.
+/
module audiotag.id3v2.v22.frame_sequence;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

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
only after the final frame, and consists entirely of logical zero bytes.

Frame boundaries and padding are interpreted through `Id3v22DataCursor`.
This is essential for whole-tag-unsynchronised input: physical stuffing zeros
must not be mistaken for padding, and logical frame sizes may occupy larger
physical source regions.

Params:
    region = Already bounded physical frames-and-padding region.
    tagUnsynchronised = Whether the enclosing ID3v2.2 tag declares
        whole-tag unsynchronisation.

Returns:
    The validated layout or a structured parse error.

Safety:
    Frame parsing cannot read beyond `region`.
+/
ParseResult!Id3v22FrameSequenceLayout
parseId3v22FrameSequenceLayout(
    ByteSpan region,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    auto cursor =
        Id3v22DataCursor(
            region,
            tagUnsynchronised
        );

    size_t frameCount =
        0;

    while (!cursor.empty)
    {
        /*
         * Padding can only be recognized in the logical byte stream.
         * A copied cursor lets us inspect the next logical byte without
         * consuming the sequence parser's cursor.
         */
        const boundaryPhysicalPosition =
            cursor.physicalPosition;

        auto boundaryProbe =
            cursor;

        auto boundaryResult =
            boundaryProbe.takeByte();

        if (boundaryResult.hasError)
        {
            return
                ParseResult!Id3v22FrameSequenceLayout
                    .failure(
                        boundaryResult.error
                    );
        }

        if (
            boundaryResult.value.value ==
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

            /*
             * Validate the complete padding region logically. Starting
             * from the original boundary cursor also includes the first
             * zero inspected above.
             */
            auto paddingCursor =
                cursor;

            while (!paddingCursor.empty)
            {
                auto byteResult =
                    paddingCursor.takeByte();

                if (byteResult.hasError)
                {
                    return
                        ParseResult!Id3v22FrameSequenceLayout
                            .failure(
                                byteResult.error
                            );
                }

                if (
                    byteResult.value.value !=
                    0x00
                )
                {
                    return
                        ParseResult!Id3v22FrameSequenceLayout
                            .failure(
                                ParseError(
                                    ParseErrorCode
                                        .inconsistentStructure,
                                    byteResult.value
                                        .sourceOffset
                                )
                            );
                }
            }

            const paddingPhysicalLength =
                paddingCursor.physicalPosition -
                boundaryPhysicalPosition;

            const frameBytes =
                region.subspan(
                    0,
                    boundaryPhysicalPosition
                );

            const padding =
                region.subspan(
                    boundaryPhysicalPosition,
                    paddingPhysicalLength
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
/// Unsynchronisation stuffing inside frame data is never mistaken for padding.
unittest
{
    /*
     * Logical payload:
     *
     *   11 FF E1
     *
     * Physical payload:
     *
     *   11 FF 00 E1
     *
     * Two logical zero padding bytes follow the frame.
     */
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x03,

            0x11,
            0xFF, 0x00,
            0xE1,

            0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            2000
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    /*
     * Six physical header bytes plus four physical payload bytes.
     */
    assert(layout.frameBytes.length == 10);
    assert(layout.frameBytes.sourceOffset == 2000);

    assert(layout.padding.sourceOffset == 2010);
    assert(layout.padding.length == 2);

    assert(
        layout.padding.data ==
        [0x00, 0x00]
    );
}


/// Stuffing at the frame/padding boundary belongs to the frame representation.
unittest
{
    /*
     * Logical sequence:
     *
     *   TT2 size=1
     *   payload FF
     *   padding 00 00
     *
     * Because the logical payload FF is followed by logical 00 padding,
     * whole-tag unsynchronisation inserts one stuffing zero:
     *
     *   ... FF 00 00 00
     *       ^  ^  ^  ^
     *       |  |  padding
     *       |  stuffing
     *       payload
     */
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,

            0xFF, 0x00,
            0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            3000
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    /*
     * The one logical payload byte occupies two physical bytes.
     */
    assert(layout.frameBytes.length == 8);

    assert(
        layout.frameBytes.data ==
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0xFF, 0x00
        ]
    );

    assert(layout.padding.sourceOffset == 3008);
    assert(layout.padding.length == 2);
}


/// Non-zero logical data after unsynchronised padding begins is rejected.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0x55,

            0x00,
            0x42
        ];

    const region =
        ByteSpan(
            bytes,
            4000
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 4008);
}


/// A physical stuffing zero before a second frame does not start padding.
unittest
{
    /*
     * First frame payload is logical FF and is followed by a second frame
     * whose first logical byte is 'T'. The payload FF therefore does not
     * require stuffing at that boundary.
     *
     * The second frame payload contains FF E1 and is physically stuffed.
     */
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,
            0xFF,

            'T', 'P', '1',
            0x00, 0x00, 0x02,
            0xFF, 0x00, 0xE1
        ];

    const region =
        ByteSpan(
            bytes,
            5000
        );

    auto result =
        parseId3v22FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 2);
    assert(layout.frameBytes.length == bytes.length);
    assert(layout.padding.empty);
    assert(layout.padding.sourceOffset == 5016);
}
