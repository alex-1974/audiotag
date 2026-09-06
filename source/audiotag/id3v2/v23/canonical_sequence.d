/++
Projection of a validated ID3v2.3 frame sequence into canonical
metadata while preserving every native frame.

The structural frame-sequence parser has already separated complete
frame bytes from trailing padding. This module iterates those bounded
frame bytes and, for every frame:

1. reparses the structural frame envelope through the ID3v2.3 logical
   data cursor;
2. dispatches the frame to its native semantic codec;
3. maps the native outcome to canonical metadata;
4. appends both native frame and mapping result to the canonical
   projection.

ID3v2.3 whole-tag unsynchronisation may add physical stuffing bytes
inside frame headers, frame data, or across field boundaries. The
physical `frameBytes` span must therefore be traversed through
`Id3v23DataCursor` whenever tag-level unsynchronisation is active.

Unknown, transformation-pending and currently unrepresentable frames
remain preserved through `Id3v23CanonicalProjection`.

Parser or semantic-codec failures remain structured `ParseError`
results. No assertion is used to validate source data.
+/
module audiotag.id3v2.v23.canonical_sequence;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v23.canonical_dispatch :
    mapId3v23NativeFrameToCanonical;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.frame :
    parseId3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_sequence :
    Id3v23FrameSequenceLayout;

import audiotag.id3v2.v23.native_frame :
    decodeId3v23NativeFrame;


/++
Projects one already validated ID3v2.3 frame sequence into canonical
metadata while retaining every native frame.

The function reparses each bounded frame envelope through the same
logical cursor model used by the structural ID3v2.3 parser.

Structural or semantic errors are propagated as `ParseError`.

The declared `frameCount` is checked against the number of frames
actually consumed from `frameBytes`. A mismatch is reported as an
inconsistent structure rather than as a programmer assertion.

Params:
    layout = Validated ID3v2.3 frame-sequence layout.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    Provenance-preserving canonical projection, or a structured parser
    or semantic-codec error.
+/
ParseResult!Id3v23CanonicalProjection
projectId3v23FrameSequenceToCanonical(
    Id3v23FrameSequenceLayout layout,
    bool tagUnsynchronised = false
)
    @safe
{
    auto cursor =
        Id3v23DataCursor(
            layout.frameBytes,
            tagUnsynchronised
        );


    auto projection =
        Id3v23CanonicalProjection.init;


    size_t parsedFrameCount =
        0;


    while (
        !cursor.empty
    )
    {
        auto frameResult =
            cursor.parseId3v23FrameEnvelope();


        if (
            frameResult.hasError
        )
        {
            return
                ParseResult!Id3v23CanonicalProjection
                    .failure(
                        frameResult.error
                    );
        }


        auto nativeResult =
            decodeId3v23NativeFrame(
                frameResult.value,
                tagUnsynchronised
            );


        if (
            nativeResult.hasError
        )
        {
            return
                ParseResult!Id3v23CanonicalProjection
                    .failure(
                        nativeResult.error
                    );
        }


        auto mapping =
            mapId3v23NativeFrameToCanonical(
                nativeResult.value
            );


        projection.append(
            nativeResult.value,
            mapping
        );


        ++parsedFrameCount;
    }


    if (
        parsedFrameCount !=
        layout.frameCount
    )
    {
        return
            ParseResult!Id3v23CanonicalProjection
                .failure(
                    ParseError(
                        ParseErrorCode
                            .inconsistentStructure,
                        layout.frameBytes.sourceOffset
                    )
                );
    }


    return
        ParseResult!Id3v23CanonicalProjection
            .success(
                projection
            );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingStatus;

    import audiotag.id3v2.v23.frame_sequence :
        parseId3v23FrameSequenceLayout;
}


/// Mixed mapped and unknown frames preserve native and canonical order.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * TIT2 = Latin-1 "Title".
             */
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'T', 'i', 't', 'l', 'e',


            /*
             * Unknown but structurally valid frame.
             */
            'A', 'B', 'C', 'D',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x55,


            /*
             * TPE1 = Latin-1 "Artist".
             */
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,

            0x00,
            'A', 'r', 't', 'i', 's', 't'
        ];


    auto layoutResult =
        parseId3v23FrameSequenceLayout(
            ByteSpan(
                bytes,
                100
            )
        );


    assert(
        layoutResult.hasValue
    );


    assert(
        layoutResult.value.frameCount ==
        3
    );


    auto result =
        projectId3v23FrameSequenceToCanonical(
            layoutResult.value
        );


    assert(
        result.hasValue
    );


    const projection =
        result.value;


    assert(
        projection.frameCount ==
        3
    );


    assert(
        projection.metadata.length ==
        2
    );


    assert(
        projection.metadata[0]
            .key.name ==
        "title"
    );


    assert(
        projection.metadata[1]
            .key.name ==
        "artist"
    );


    assert(
        projection.frames[0]
            .status ==
        Id3v23CanonicalMappingStatus.mapped
    );


    assert(
        projection.frames[0]
            .canonicalStart ==
        0
    );


    assert(
        projection.frames[0]
            .canonicalCount ==
        1
    );


    assert(
        projection.frames[1]
            .status ==
        Id3v23CanonicalMappingStatus
            .unsupportedFrame
    );


    assert(
        projection.frames[1]
            .canonicalStart ==
        1
    );


    assert(
        projection.frames[1]
            .canonicalCount ==
        0
    );


    assert(
        projection.frames[1]
            .native.envelope.header.id[] ==
        "ABCD"
    );


    assert(
        projection.frames[2]
            .status ==
        Id3v23CanonicalMappingStatus.mapped
    );


    assert(
        projection.frames[2]
            .canonicalStart ==
        1
    );


    assert(
        projection.frames[2]
            .canonicalCount ==
        1
    );
}


/// Semantic codec errors propagate from the bounded frame sequence.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * Structurally valid TIT2 but UTF-8 marker $03 is invalid
             * in ID3v2.3.
             */
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03,
            'X'
        ];


    auto layoutResult =
        parseId3v23FrameSequenceLayout(
            ByteSpan(
                bytes,
                400
            )
        );


    assert(
        layoutResult.hasValue
    );


    auto result =
        projectId3v23FrameSequenceToCanonical(
            layoutResult.value
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );


    assert(
        result.error.offset ==
        410
    );
}


/// A stale or manually inconsistent frame count is a structured error.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            'X'
        ];


    auto layoutResult =
        parseId3v23FrameSequenceLayout(
            ByteSpan(
                bytes,
                700
            )
        );


    assert(
        layoutResult.hasValue
    );


    auto layout =
        layoutResult.value;


    assert(
        layout.frameCount ==
        1
    );


    layout.frameCount =
        2;


    auto result =
        projectId3v23FrameSequenceToCanonical(
            layout
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        ParseErrorCode
            .inconsistentStructure
    );


    assert(
        result.error.offset ==
        700
    );
}


/// Whole-tag unsynchronisation is respected while reparsing frame bytes.
unittest
{
    /*
     * Logical TIT2 frame data:
     *
     *   00 41 FF E1
     *
     * Latin-1 encoding marker, "A", FF, E1.
     *
     * Physical frame data:
     *
     *   00 41 FF 00 E1
     *
     * The frame header still declares four logical data bytes.
     */
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'A',
            0xFF,
            0x00,
            0xE1
        ];


    auto layoutResult =
        parseId3v23FrameSequenceLayout(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );


    assert(
        layoutResult.hasValue
    );


    assert(
        layoutResult.value.frameCount ==
        1
    );


    /*
     * Physical frame extent includes the stuffing zero.
     */
    assert(
        layoutResult.value.frameBytes.length ==
        bytes.length
    );


    auto result =
        projectId3v23FrameSequenceToCanonical(
            layoutResult.value,
            true
        );


    assert(
        result.hasValue
    );


    const projection =
        result.value;


    assert(
        projection.frameCount ==
        1
    );


    assert(
        projection.metadata.length ==
        1
    );


    assert(
        projection.metadata[0]
            .key.name ==
        "title"
    );


    assert(
        projection.frames[0]
            .status ==
        Id3v23CanonicalMappingStatus.mapped
    );


    /*
     * Canonical provenance retains the complete physical frame,
     * including the unsynchronisation stuffing byte.
     */
    assert(
        projection.metadata[0]
            .provenance[0]
            .sourceOffset ==
        1000
    );


    assert(
        projection.metadata[0]
            .provenance[0]
            .sourceLength ==
        bytes.length
    );


    assert(
        projection.frames[0]
            .native.sourceLength ==
        bytes.length
    );
}
