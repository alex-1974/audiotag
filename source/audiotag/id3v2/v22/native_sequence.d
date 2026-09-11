/++
Native semantic decoding of one validated ID3v2.2 frame sequence.

The structural frame-sequence parser has already separated complete frame bytes
from trailing padding. This module traverses those bounded frame bytes through
`Id3v22DataCursor`, decodes every frame through `native_frame.d`, and preserves
the original validated sequence layout alongside the decoded native frames.

Unknown but structurally valid frames remain native frames with an explicit
`Id3v22UnknownFrame` semantic marker and their complete frame envelope.

ID3v2.2 whole-tag unsynchronisation is applied only during logical traversal.
All raw spans retained by the structural and semantic layers continue to point
at the exact physical source representation.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.native_sequence;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    parseId3v22FrameEnvelope;

import audiotag.id3v2.v22.frame_sequence :
    Id3v22FrameSequenceLayout;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame,
    decodeId3v22NativeFrame;


/++
One provenance-preserving native ID3v2.2 frame sequence.

`layout` is the previously validated physical frame/padding partition.

`frames` contains every decoded native frame in original source order.
+/
struct Id3v22NativeFrameSequence
{
    /// Original validated structural layout.
    Id3v22FrameSequenceLayout layout;

    /// Native frames in source order.
    Id3v22NativeFrame[] frames;


    /// Number of decoded native frames.
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        return
            frames.length;
    }
}


/++
Decodes every frame in one validated ID3v2.2 frame sequence.

The function reparses each bounded frame envelope through the same logical
cursor model used by the structural parser. This is required when whole-tag
unsynchronisation is active because logical frame sizes may occupy a larger
physical source region.

The number of reparsed frames must equal `layout.frameCount`. A mismatch is
reported as `inconsistentStructure`; it is not treated as an internal
assertion because callers may construct a layout value manually.

Params:
    layout = Previously validated ID3v2.2 frame-sequence layout.
    tagUnsynchronised = Whether the enclosing tag declares whole-tag
        unsynchronisation.

Returns:
    Native frame sequence or a structured parser/semantic-codec error.
+/
ParseResult!Id3v22NativeFrameSequence
decodeId3v22NativeFrameSequence(
    Id3v22FrameSequenceLayout layout,
    bool tagUnsynchronised = false
)
    @safe
{
    auto cursor =
        Id3v22DataCursor(
            layout.frameBytes,
            tagUnsynchronised
        );

    Id3v22NativeFrame[] frames;

    while (
        !cursor.empty
    )
    {
        auto frameResult =
            cursor.parseId3v22FrameEnvelope();

        if (
            frameResult.hasError
        )
        {
            return
                ParseResult!Id3v22NativeFrameSequence
                    .failure(
                        frameResult.error
                    );
        }


        auto nativeResult =
            decodeId3v22NativeFrame(
                frameResult.value,
                tagUnsynchronised
            );

        if (
            nativeResult.hasError
        )
        {
            return
                ParseResult!Id3v22NativeFrameSequence
                    .failure(
                        nativeResult.error
                    );
        }


        frames ~=
            nativeResult.value;
    }


    if (
        frames.length !=
        layout.frameCount
    )
    {
        return
            ParseResult!Id3v22NativeFrameSequence
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        layout.frameBytes.sourceOffset
                    )
                );
    }


    return
        ParseResult!Id3v22NativeFrameSequence
            .success(
                Id3v22NativeFrameSequence(
                    layout,
                    frames
                )
            );
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.attached_picture :
        Id3v22AttachedPictureFrame;

    import audiotag.id3v2.v22.frame_sequence :
        parseId3v22FrameSequenceLayout;

    import audiotag.id3v2.v22.native_frame :
        Id3v22UnknownFrame;

    import audiotag.id3v2.v22.text_information :
        Id3v22TextInformationFrame;

    import audiotag.id3v2.v22.unique_file_identifier :
        Id3v22UniqueFileIdentifierFrame;
}


/// Mixed known and unknown frames remain in original source order.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * TT2 = "Title".
             */
            'T', 'T', '2',
            0x00, 0x00, 0x06,
            0x00,
            'T', 'i', 't', 'l', 'e',

            /*
             * Unknown ZZZ frame.
             */
            'Z', 'Z', 'Z',
            0x00, 0x00, 0x03,
            0x11, 0x22, 0x33,

            /*
             * PIC with empty description and one opaque image byte.
             */
            'P', 'I', 'C',
            0x00, 0x00, 0x07,
            0x00,
            'J', 'P', 'G',
            0x03,
            0x00,
            0xAA,

            /*
             * Padding.
             */
            0x00, 0x00
        ];

    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                100
            )
        );

    assert(layoutResult.hasValue);

    auto result =
        decodeId3v22NativeFrameSequence(
            layoutResult.value
        );

    assert(result.hasValue);

    auto sequence =
        result.value;

    assert(sequence.frameCount == 3);
    assert(sequence.layout.frameCount == 3);
    assert(sequence.layout.padding.length == 2);

    const firstIsTitle =
        sequence.frames[0].content.match!(
            (Id3v22TextInformationFrame text) =>
                text.id[] == "TT2" &&
                text.value == "Title",

            _ =>
                false
        );

    assert(firstIsTitle);

    const secondIsUnknown =
        sequence.frames[1].content.match!(
            (Id3v22UnknownFrame unknown) =>
                true,

            _ =>
                false
        );

    assert(secondIsUnknown);

    assert(
        sequence.frames[1]
            .envelope.header.id[] ==
        "ZZZ"
    );

    assert(
        sequence.frames[1]
            .envelope.data.data ==
        [0x11, 0x22, 0x33]
    );

    const thirdIsPicture =
        sequence.frames[2].content.match!(
            (Id3v22AttachedPictureFrame picture) =>
                picture.imageFormat[] == "JPG" &&
                picture.rawPictureData.data == [0xAA],

            _ =>
                false
        );

    assert(thirdIsPicture);

    assert(sequence.frames[0].sourceOffset == 100);
    assert(sequence.frames[1].sourceOffset == 112);
    assert(sequence.frames[2].sourceOffset == 121);
}


/// The original frame/padding partition is retained unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L',
            0x00, 0x00, 0x02,
            0x00,
            'A',

            0x00, 0x00, 0x00
        ];

    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                500
            )
        );

    assert(layoutResult.hasValue);

    const layout =
        layoutResult.value;

    auto result =
        decodeId3v22NativeFrameSequence(
            layout
        );

    assert(result.hasValue);

    const sequence =
        result.value;

    assert(
        sequence.layout.frameBytes.data ==
        layout.frameBytes.data
    );

    assert(
        sequence.layout.frameBytes.sourceOffset ==
        layout.frameBytes.sourceOffset
    );

    assert(
        sequence.layout.padding.data ==
        [0x00, 0x00, 0x00]
    );

    assert(sequence.layout.padding.sourceOffset == 508);
}


/// A forged frame-count mismatch is reported as source structure failure.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,
            0x00,
            'A'
        ];

    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                700
            )
        );

    assert(layoutResult.hasValue);

    auto layout =
        layoutResult.value;

    layout.frameCount =
        2;

    auto result =
        decodeId3v22NativeFrameSequence(
            layout
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 700);
}


/// Malformed semantic content from a known frame propagates unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,

            /*
             * Invalid ID3v2.2 text encoding marker.
             */
            0x02
        ];

    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                800
            )
        );

    assert(layoutResult.hasValue);

    auto result =
        decodeId3v22NativeFrameSequence(
            layoutResult.value
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 806);
}


/// Whole-tag unsynchronisation is forwarded through the complete sequence.
unittest
{
    /*
     * Logical sequence:
     *
     *   UFI size=4
     *   x 00 FF E0
     *
     *   TT2 size=2
     *   00 A
     *
     * Physical UFI data contains one stuffing byte after FF.
     */
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x04,
            'x',
            0x00,
            0xFF, 0x00,
            0xE0,

            'T', 'T', '2',
            0x00, 0x00, 0x02,
            0x00,
            'A',

            0x00, 0x00
        ];

    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    assert(layoutResult.hasValue);
    assert(layoutResult.value.frameCount == 2);

    auto result =
        decodeId3v22NativeFrameSequence(
            layoutResult.value,
            true
        );

    assert(result.hasValue);

    const sequence =
        result.value;

    assert(sequence.frameCount == 2);

    const firstPreserved =
        sequence.frames[0].content.match!(
            (Id3v22UniqueFileIdentifierFrame identifier) =>
                identifier.effectiveUnsynchronisation &&
                identifier.ownerIdentifier == "x" &&
                identifier.logicalIdentifierLength == 2 &&
                identifier.rawIdentifier.data ==
                    [
                        0xFF, 0x00,
                        0xE0
                    ],

            _ =>
                false
        );

    assert(firstPreserved);

    const secondDecoded =
        sequence.frames[1].content.match!(
            (Id3v22TextInformationFrame text) =>
                text.value == "A" &&
                text.effectiveUnsynchronisation,

            _ =>
                false
        );

    assert(secondDecoded);

    assert(sequence.layout.padding.length == 2);
}
