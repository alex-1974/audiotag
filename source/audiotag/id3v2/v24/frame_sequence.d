/++
ID3v2.4 frame-sequence and padding parsing.

This module validates the complete region following the optional
extended header and partitions it into:

- one or more complete ID3v2.4 frames;
- optional trailing zero padding.

The individual frames are not collected into a dynamic container.
Instead, `frameBytes` preserves their complete contiguous physical
source representation for later iteration.

Padding is valid only after the final frame and every padding byte
must be zero. ID3v2.4 forbids padding when a footer is present.
+/
module audiotag.id3v2.v24.frame_sequence;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;
import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/++
Validated structural layout of an ID3v2.4 frame sequence.

`frameBytes` contains exactly all complete frames and no padding.

`padding` contains only trailing `$00` bytes. When no padding is
present it is an empty span positioned immediately after the final
frame.
+/
struct Id3v24FrameSequenceLayout
{
    /// Contiguous raw bytes containing all validated frames.
    ByteSpan frameBytes;

    /// Optional trailing zero padding.
    ByteSpan padding;

    /// Number of complete frames in `frameBytes`.
    size_t frameCount;
}


/++
Validates and partitions an ID3v2.4 frames-and-padding region.

At least one complete frame is required.

The first physical `$00` encountered where a new frame header would
begin starts the padding region. Every remaining byte must then also
be `$00`.

Params:
    region = Already bounded frames-and-padding region.
    footerPresent = Whether the enclosing ID3v2.4 tag has a footer.
        Padding is forbidden when this is true.

Returns:
    The validated frame-sequence layout or a structured parse error.

Safety:
    Frame parsing cannot read beyond `region`.
+/
ParseResult!Id3v24FrameSequenceLayout
parseId3v24FrameSequenceLayout(
    ByteSpan region,
    bool footerPresent = false
)
    @safe pure nothrow @nogc
{
    auto cursor = ByteCursor(region);

    size_t frameCount = 0;

    while (!cursor.empty)
    {
        // A zero where the next frame identifier would begin marks
        // the start of padding.
        if (cursor.front == 0x00)
        {
            const paddingStart = cursor.position;

            const padding =
                region.subspan(
                    paddingStart,
                    cursor.remaining
                );

            if (frameCount == 0)
            {
                return ParseResult!Id3v24FrameSequenceLayout.failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        region.sourceOffset
                    )
                );
            }

            foreach (index, value; padding.data)
            {
                if (value != 0x00)
                {
                    return ParseResult!Id3v24FrameSequenceLayout.failure(
                        ParseError(
                            ParseErrorCode.inconsistentStructure,
                            padding.sourceOffset + index
                        )
                    );
                }
            }

            if (footerPresent)
            {
                return ParseResult!Id3v24FrameSequenceLayout.failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        padding.sourceOffset
                    )
                );
            }

            const frameBytes =
                region.subspan(
                    0,
                    paddingStart
                );

            return ParseResult!Id3v24FrameSequenceLayout.success(
                Id3v24FrameSequenceLayout(
                    frameBytes,
                    padding,
                    frameCount
                )
            );
        }

        auto frameResult =
            cursor.parseId3v24FrameEnvelope();

        if (frameResult.hasError)
        {
            return ParseResult!Id3v24FrameSequenceLayout.failure(
                frameResult.error
            );
        }

        ++frameCount;
    }

    if (frameCount == 0)
    {
        return ParseResult!Id3v24FrameSequenceLayout.failure(
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

    return ParseResult!Id3v24FrameSequenceLayout.success(
        Id3v24FrameSequenceLayout(
            region,
            padding,
            frameCount
        )
    );
}


/// Multiple complete frames occupy the entire region without padding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x11,

            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x22, 0x33
        ];

    const region = ByteSpan(bytes, 100);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasValue);

    const layout = result.value;

    assert(layout.frameCount == 2);
    assert(layout.frameBytes.sourceOffset == 100);
    assert(layout.frameBytes.length == bytes.length);
    assert(layout.frameBytes.data == bytes);

    assert(layout.padding.empty);
    assert(layout.padding.sourceOffset == 123);
}


/// Trailing zero bytes are separated from the frame sequence.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00, 0x00, 0x00
        ];

    const region = ByteSpan(bytes, 200);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasValue);

    const layout = result.value;

    assert(layout.frameCount == 1);

    assert(layout.frameBytes.sourceOffset == 200);
    assert(layout.frameBytes.length == 11);

    assert(layout.padding.sourceOffset == 211);
    assert(layout.padding.length == 4);
    assert(
        layout.padding.data ==
        [0x00, 0x00, 0x00, 0x00]
    );
}


/// Zero bytes inside frame data are not mistaken for tag padding.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x00, 0x00, 0x55,

            0x00, 0x00
        ];

    const region = ByteSpan(bytes, 300);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasValue);

    const layout = result.value;

    assert(layout.frameCount == 1);
    assert(layout.frameBytes.length == 13);

    assert(layout.padding.sourceOffset == 313);
    assert(layout.padding.length == 2);
}


/// An empty frames-and-padding region cannot form a valid tag.
unittest
{
    const ubyte[] bytes = [];

    const region = ByteSpan(bytes, 400);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 400);
}


/// Padding without any preceding frame is invalid.
unittest
{
    const ubyte[] bytes =
        [0x00, 0x00, 0x00];

    const region = ByteSpan(bytes, 500);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 500);
}


/// A non-zero byte after padding has begun is rejected exactly there.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00,
            0x42,
            0x00
        ];

    const region = ByteSpan(bytes, 600);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 613);
}


/// A short non-zero trailing structure is a truncated frame, not padding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            'A', 'B', 'C'
        ];

    const region = ByteSpan(bytes, 700);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasError);

    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 711);
    assert(result.error.requested == 10);
    assert(result.error.available == 3);
}


/// Invalid frame headers are propagated instead of becoming padding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            'a', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x66
        ];

    const region = ByteSpan(bytes, 800);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 811);
}


/// Padding is forbidden when the enclosing tag has a footer.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00, 0x00
        ];

    const region = ByteSpan(bytes, 900);

    auto result =
        parseId3v24FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 911);
}


/// A footer is compatible with a sequence that has no padding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    const region = ByteSpan(bytes, 1000);

    auto result =
        parseId3v24FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);
    assert(result.value.frameCount == 1);
    assert(result.value.padding.empty);
}


/// Parent-relative source offsets remain absolute through the sequence.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'T', 'C', 'O', 'N',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x42,

            0x00, 0x00,

            0xAA
        ];

    const region =
        ByteSpan(bytes, 2000)
            .subspan(1, 13);

    auto result =
        parseId3v24FrameSequenceLayout(region);

    assert(result.hasValue);

    const layout = result.value;

    assert(layout.frameCount == 1);

    assert(layout.frameBytes.sourceOffset == 2001);
    assert(layout.frameBytes.length == 11);

    assert(layout.padding.sourceOffset == 2012);
    assert(layout.padding.length == 2);
}
