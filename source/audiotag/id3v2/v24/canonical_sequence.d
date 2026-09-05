/++
Projection of a validated ID3v2.4 frame sequence into canonical
metadata while preserving every native frame.

The structural frame-sequence parser has already separated complete
frame bytes from trailing padding. This module iterates those bounded
frame bytes and, for every frame:

1. parses the structural frame envelope;
2. dispatches the frame to its native semantic codec;
3. maps the native outcome to canonical metadata;
4. appends both native frame and mapping result to the canonical
   projection.

Unknown, transformation-pending and currently unrepresentable frames
remain preserved through `Id3v24CanonicalProjection`.

Parser or semantic-codec failures remain structured `ParseError`
results. No assertion is used to validate source data.
+/
module audiotag.id3v2.v24.canonical_sequence;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v24.canonical_dispatch :
    mapId3v24NativeFrameToCanonical;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalProjection;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_sequence :
    Id3v24FrameSequenceLayout;

import audiotag.id3v2.v24.native_frame :
    decodeId3v24NativeFrame;


/++
Projects one already validated ID3v2.4 frame sequence into canonical
metadata while retaining every native frame.

The function reparses each bounded frame envelope rather than relying
on unchecked assumptions about the supplied layout. Structural or
semantic errors are propagated as `ParseError`.

The declared `frameCount` is checked against the number of frames
actually consumed from `frameBytes`. A mismatch is reported as an
inconsistent structure rather than as a programmer assertion.

Params:
    layout = Validated ID3v2.4 frame-sequence layout.
    tagUnsynchronised = Whether tag-level unsynchronisation applies to
        semantic frame decoding.

Returns:
    Provenance-preserving canonical projection, or a structured parser
    or semantic-codec error.
+/
ParseResult!Id3v24CanonicalProjection
projectId3v24FrameSequenceToCanonical(
    Id3v24FrameSequenceLayout layout,
    bool tagUnsynchronised = false
)
    @safe
{
    auto cursor =
        ByteCursor(
            layout.frameBytes
        );

    auto projection =
        Id3v24CanonicalProjection.init;

    size_t parsedFrameCount = 0;

    while (!cursor.empty)
    {
        auto frameResult =
            cursor.parseId3v24FrameEnvelope();

        if (frameResult.hasError)
        {
            return
                ParseResult!Id3v24CanonicalProjection
                    .failure(
                        frameResult.error
                    );
        }

        auto nativeResult =
            decodeId3v24NativeFrame(
                frameResult.value,
                tagUnsynchronised
            );

        if (nativeResult.hasError)
        {
            return
                ParseResult!Id3v24CanonicalProjection
                    .failure(
                        nativeResult.error
                    );
        }

        auto mapping =
            mapId3v24NativeFrameToCanonical(
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
            ParseResult!Id3v24CanonicalProjection
                .failure(
                    ParseError(
                        ParseErrorCode
                            .inconsistentStructure,
                        layout.frameBytes.sourceOffset
                    )
                );
    }

    return
        ParseResult!Id3v24CanonicalProjection
            .success(
                projection
            );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingStatus;

    import audiotag.id3v2.v24.frame_sequence :
        parseId3v24FrameSequenceLayout;
}


/// Mixed mapped and unknown frames preserve both native and canonical order.
unittest
{
    const ubyte[] bytes =
        [
            // TIT2 = UTF-8 "Title"
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x03,
            'T', 'i', 't', 'l', 'e',

            // Unknown structurally valid frame.
            'A', 'B', 'C', 'D',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55,

            // TPE1 = UTF-8 "Artist"
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,
            0x03,
            'A', 'r', 't', 'i', 's', 't'
        ];

    auto layoutResult =
        parseId3v24FrameSequenceLayout(
            ByteSpan(
                bytes,
                100
            )
        );

    assert(layoutResult.hasValue);
    assert(layoutResult.value.frameCount == 3);

    auto result =
        projectId3v24FrameSequenceToCanonical(
            layoutResult.value
        );

    assert(result.hasValue);

    const projection =
        result.value;

    assert(projection.frameCount == 3);
    assert(projection.metadata.length == 2);

    assert(
        projection.metadata[0].key.name ==
        "title"
    );

    assert(
        projection.metadata[1].key.name ==
        "artist"
    );

    assert(
        projection.frames[0].status ==
        Id3v24CanonicalMappingStatus.mapped
    );

    assert(
        projection.frames[0].canonicalStart ==
        0
    );

    assert(
        projection.frames[0].canonicalCount ==
        1
    );

    assert(
        projection.frames[1].status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );

    assert(
        projection.frames[1].canonicalStart ==
        1
    );

    assert(
        projection.frames[1].canonicalCount ==
        0
    );

    assert(
        projection.frames[1]
            .native.envelope.header.id[] ==
        "ABCD"
    );

    assert(
        projection.frames[2].status ==
        Id3v24CanonicalMappingStatus.mapped
    );

    assert(
        projection.frames[2].canonicalStart ==
        1
    );

    assert(
        projection.frames[2].canonicalCount ==
        1
    );
}


/// Semantic codec errors propagate from the bounded frame sequence.
unittest
{
    const ubyte[] bytes =
        [
            // Structurally valid TIT2 but invalid text-encoding marker.
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x04,
            'X'
        ];

    auto layoutResult =
        parseId3v24FrameSequenceLayout(
            ByteSpan(
                bytes,
                400
            )
        );

    assert(layoutResult.hasValue);

    auto result =
        projectId3v24FrameSequenceToCanonical(
            layoutResult.value
        );

    assert(result.hasError);

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
            0x03,
            'X'
        ];

    auto layoutResult =
        parseId3v24FrameSequenceLayout(
            ByteSpan(
                bytes,
                700
            )
        );

    assert(layoutResult.hasValue);

    auto layout =
        layoutResult.value;

    assert(layout.frameCount == 1);

    layout.frameCount = 2;

    auto result =
        projectId3v24FrameSequenceToCanonical(
            layout
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(
        result.error.offset ==
        700
    );
}
