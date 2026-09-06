/++
ID3v2.3 frame-sequence and padding parsing.

This module validates the complete physical region following the
optional extended header and partitions it into:

- one or more complete ID3v2.3 frames;
- optional trailing zero padding.

ID3v2.3 tag-level unsynchronisation applies across the complete tag
body. Frame boundaries and padding detection must therefore operate on
the logical byte stream rather than by examining physical bytes
directly.

The individual frames are not collected into a dynamic container.
Instead, `frameBytes` preserves their complete contiguous physical
source representation for later iteration.

`padding` preserves the physical trailing padding bytes. Valid padding
contains only logical `$00` bytes.
+/
module audiotag.id3v2.v23.frame_sequence;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.frame :
    parseId3v23FrameEnvelope;


/++
Validated structural layout of an ID3v2.3 frame sequence.

`frameBytes` contains exactly all complete frames in their original
physical source representation and contains no padding.

`padding` contains only trailing padding. When no padding is present it
is an empty physical span positioned immediately after the final frame.

`frameCount` counts complete logically parsed frames.
+/
struct Id3v23FrameSequenceLayout
{
    /// Contiguous physical bytes containing all validated frames.
    ByteSpan frameBytes;

    /// Optional trailing physical zero padding.
    ByteSpan padding;

    /// Number of complete frames represented by `frameBytes`.
    size_t frameCount;
}


/++
Validates and partitions an ID3v2.3 frames-and-padding region.

At least one complete frame is required by ID3v2.3.

At each logical frame boundary, a logical `$00` begins the padding
region. Every remaining logical byte must then also be `$00`.

This distinction is important for unsynchronised tags: a physical
stuffing zero following `$FF` is removed by `Id3v23DataCursor` and must
never be mistaken for padding.

The optional padding size declared by an ID3v2.3 extended header is not
validated here. That is a cross-layer consistency rule for the complete
tag-structure parser.

Params:
    region = Already bounded physical frames-and-padding region.
    tagUnsynchronised = Whether the enclosing ID3v2.3 tag declares
        tag-level unsynchronisation.

Returns:
    The validated frame-sequence layout or a structured parse error.

Safety:
    Frame parsing cannot read beyond `region`.
+/
ParseResult!Id3v23FrameSequenceLayout
parseId3v23FrameSequenceLayout(
    ByteSpan region,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    auto cursor =
        Id3v23DataCursor(
            region,
            tagUnsynchronised
        );

    size_t frameCount =
        0;

    while (!cursor.empty)
    {
        /*
         * Padding can only be recognised in the logical byte stream.
         *
         * Use a copied cursor so merely inspecting the next logical
         * byte does not consume the sequence parser's cursor.
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
                ParseResult!Id3v23FrameSequenceLayout
                    .failure(
                        boundaryResult.error
                    );
        }

        if (
            boundaryResult.value.value ==
            0x00
        )
        {
            /*
             * ID3v2.3 requires at least one frame. A body consisting
             * only of padding is therefore invalid.
             */
            if (
                frameCount == 0
            )
            {
                return
                    ParseResult!Id3v23FrameSequenceLayout
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
                        ParseResult!Id3v23FrameSequenceLayout
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
                        ParseResult!Id3v23FrameSequenceLayout
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
                ParseResult!Id3v23FrameSequenceLayout
                    .success(
                        Id3v23FrameSequenceLayout(
                            frameBytes,
                            padding,
                            frameCount
                        )
                    );
        }

        /*
         * The next logical byte is non-zero, so this must be another
         * complete frame rather than padding.
         */
        auto frameResult =
            cursor.parseId3v23FrameEnvelope();

        if (frameResult.hasError)
        {
            return
                ParseResult!Id3v23FrameSequenceLayout
                    .failure(
                        frameResult.error
                    );
        }

        ++frameCount;
    }

    /*
     * ID3v2.3 explicitly requires at least one frame.
     */
    if (
        frameCount == 0
    )
    {
        return
            ParseResult!Id3v23FrameSequenceLayout
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
        ParseResult!Id3v23FrameSequenceLayout
            .success(
                Id3v23FrameSequenceLayout(
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
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x11,

            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x22, 0x33
        ];

    const region =
        ByteSpan(
            bytes,
            100
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 2);

    assert(
        layout.frameBytes.sourceOffset ==
        100
    );

    assert(
        layout.frameBytes.length ==
        bytes.length
    );

    assert(
        layout.frameBytes.data ==
        bytes
    );

    assert(layout.padding.empty);

    assert(
        layout.padding.sourceOffset ==
        123
    );
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

    const region =
        ByteSpan(
            bytes,
            200
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    assert(
        layout.frameBytes.sourceOffset ==
        200
    );

    assert(
        layout.frameBytes.length ==
        11
    );

    assert(
        layout.padding.sourceOffset ==
        211
    );

    assert(
        layout.padding.length ==
        4
    );

    assert(
        layout.padding.data ==
        [0x00, 0x00, 0x00, 0x00]
    );
}


/// Zero bytes inside frame data are not mistaken for padding.
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

    const region =
        ByteSpan(
            bytes,
            300
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);
    assert(layout.frameBytes.length == 13);

    assert(
        layout.padding.sourceOffset ==
        313
    );

    assert(layout.padding.length == 2);
}


/// An empty region cannot form a valid ID3v2.3 tag body.
unittest
{
    const ubyte[] bytes = [];

    const region =
        ByteSpan(
            bytes,
            400
        );

    auto result =
        parseId3v23FrameSequenceLayout(
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
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 500);
}


/// A non-zero logical byte after padding begins is rejected there.
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

    const region =
        ByteSpan(
            bytes,
            600
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(
        result.error.offset ==
        613
    );
}


/// A short non-zero tail is a truncated frame rather than padding.
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

    const region =
        ByteSpan(
            bytes,
            700
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    /*
     * The logical v2.3 frame-header parser consumes individual
     * logical bytes transactionally. It therefore fails at the
     * physical end of the bounded region.
     */
    assert(result.error.offset == 714);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);
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

    const region =
        ByteSpan(
            bytes,
            800
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 811);
}


/// Unsynchronised payload bytes remain part of one physical frame.
unittest
{
    /*
     * Logical payload:
     *
     *   FF E1
     *
     * Physical payload:
     *
     *   FF 00 E1
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0xFF, 0x00,
            0xE1
        ];

    const region =
        ByteSpan(
            bytes,
            900
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    /*
     * Ten physical header bytes plus three physical payload bytes.
     */
    assert(layout.frameBytes.length == 13);
    assert(layout.frameBytes.data == bytes);

    assert(layout.padding.empty);
    assert(layout.padding.sourceOffset == 913);
}


/// Stuffing at the frame/padding boundary is not padding itself.
unittest
{
    /*
     * Logical structure:
     *
     *   frame payload = FF
     *   padding       = 00 00
     *
     * Whole-tag unsynchronisation sees the logical boundary pair
     * `FF 00` and inserts one stuffing zero:
     *
     *   physical payload/padding boundary =
     *
     *       FF 00 00 00
     *          ^  ^^^^^
     *          |    actual two padding bytes
     *          stuffing
     *
     * The stuffing byte belongs to the physical frame region consumed
     * while producing the final logical payload byte.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0xFF,
            0x00,

            0x00, 0x00
        ];

    const region =
        ByteSpan(
            bytes,
            1000
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    /*
     * Ten-byte header + FF + its stuffing zero.
     */
    assert(layout.frameBytes.length == 12);

    assert(
        layout.frameBytes.data ==
        bytes[0 .. 12]
    );

    assert(
        layout.padding.sourceOffset ==
        1012
    );

    assert(layout.padding.length == 2);

    assert(
        layout.padding.data ==
        [0x00, 0x00]
    );
}


/// Unsynchronisation inside a frame header does not shift frame bounds.
unittest
{
    /*
     * Logical frame size:
     *
     *   00 00 00 FF
     *
     * followed by logical status byte 00.
     *
     * Whole-tag unsynchronisation therefore stores:
     *
     *   ... 00 00 00 FF 00 00 00
     *                    ^  ^  ^
     *                 stuffing/status/format
     *
     * The frame declares 255 logical data bytes.
     */
    ubyte[] bytes =
        [
            'A', 'B', 'C', '1',

            0x00, 0x00, 0x00,
            0xFF,

            /*
             * Stuffing after the final size byte.
             */
            0x00,

            /*
             * Status and format flags.
             */
            0x00,
            0x00
        ];

    bytes.length += 255;

    const region =
        ByteSpan(
            bytes,
            1100
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    /*
     * Eleven physical header bytes + 255 physical data bytes.
     */
    assert(layout.frameBytes.length == 266);
    assert(layout.frameBytes.data == bytes);

    assert(layout.padding.empty);

    assert(
        layout.padding.sourceOffset ==
        1366
    );
}


/// Truncated unsynchronised frame data fails at the physical boundary.
unittest
{
    /*
     * Three logical payload bytes are declared, but:
     *
     *   FF 00 42
     *
     * contains only two logical bytes.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0xFF, 0x00,
            0x42
        ];

    const region =
        ByteSpan(
            bytes,
            1400
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 1413);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);
}


/// Malformed padding is checked through the logical unsynchronised stream.
unittest
{
    /*
     * The first logical byte after the frame is zero and therefore
     * begins padding. A later physical `FF 00` represents logical FF,
     * which is not valid padding.
     */
    const ubyte[] bytes =
        [
            'A', 'B', 'C', '1',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            0x00,
            0xFF, 0x00,
            0x00
        ];

    const region =
        ByteSpan(
            bytes,
            1500
        );

    auto result =
        parseId3v23FrameSequenceLayout(
            region,
            true
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    /*
     * Frame occupies offsets 1500..1510.
     * Padding starts at 1511.
     * The logical FF comes from physical offset 1512.
     */
    assert(result.error.offset == 1512);
}


/// Parent-relative physical source offsets remain absolute.
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
        ByteSpan(
            bytes,
            2000
        )
            .subspan(
                1,
                13
            );

    auto result =
        parseId3v23FrameSequenceLayout(
            region
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(layout.frameCount == 1);

    assert(
        layout.frameBytes.sourceOffset ==
        2001
    );

    assert(
        layout.frameBytes.length ==
        11
    );

    assert(
        layout.padding.sourceOffset ==
        2012
    );

    assert(layout.padding.length == 2);
}
