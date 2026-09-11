/++
Projection of one ID3v2.2 native frame sequence into canonical metadata.

Canonical projection is intentionally separated from native decoding.

Two entry points are provided:

- `projectId3v22NativeFrameSequenceToCanonical` projects an already decoded
  native sequence without reparsing or re-decoding any bytes;
- `projectId3v22FrameSequenceToCanonical` is a convenience wrapper for a
  validated structural layout and delegates native decoding to
  `decodeId3v22NativeFrameSequence`.

Every native frame remains preserved in source order.

Ordinary one-frame semantics are mapped through the central canonical
dispatcher.

The legacy `TYE`/`TDA`/`TIM` group is aggregated many-to-one into one
`recordingDate` field. Every contributing native frame record links to that
same canonical field.

Unknown and currently unrepresentable native semantics remain preserved in the
projection with explicit mapping status.

Whole-tag unsynchronisation, structural frame-count validation and semantic
codec errors belong to the native-sequence decoder and are not duplicated
here.
+/
module audiotag.id3v2.v22.canonical_sequence;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v22.canonical_dispatch :
    mapId3v22NativeFrameToCanonical;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult;

import audiotag.id3v2.v22.canonical_projection :
    Id3v22CanonicalProjection;

import audiotag.id3v2.v22.canonical_recording_time :
    isId3v22RecordingTimeFrameId,
    mapId3v22RecordingTimeFramesToCanonical;

import audiotag.id3v2.v22.frame_sequence :
    Id3v22FrameSequenceLayout;

import audiotag.id3v2.v22.native_sequence :
    Id3v22NativeFrameSequence,
    decodeId3v22NativeFrameSequence;


/++
Projects one already decoded native ID3v2.2 frame sequence into canonical
metadata while retaining every native frame.

This function cannot produce a `ParseError`: structural parsing and semantic
native decoding have already completed successfully.

The legacy recording-time group is evaluated once for the complete native
sequence. If it maps successfully, the first contributing frame appends the
single canonical `recordingDate` field and later contributing frames link to
that same field.

If the group is invalid or ambiguous, every contributing recording-time frame
is preserved with the same explicit non-mapped outcome.

Params:
    sequence = Complete provenance-preserving native frame sequence.

Returns:
    Canonical projection retaining every native frame.
+/
Id3v22CanonicalProjection
projectId3v22NativeFrameSequenceToCanonical(
    Id3v22NativeFrameSequence sequence
)
    @safe
{
    Id3v22CanonicalMappingResult[] perFrameMappings;

    perFrameMappings.reserve(
        sequence.frames.length
    );


    foreach (
        native;
        sequence.frames
    )
    {
        perFrameMappings ~=
            mapId3v22NativeFrameToCanonical(
                native
            );
    }


    auto recordingTimeMapping =
        mapId3v22RecordingTimeFramesToCanonical(
            sequence.frames
        );


    auto projection =
        Id3v22CanonicalProjection.init;


    bool recordingTimeFieldAppended;
    size_t recordingTimeCanonicalStart;


    foreach (
        index,
        native;
        sequence.frames
    )
    {
        if (
            isId3v22RecordingTimeFrameId(
                native.envelope.header.id
            )
        )
        {
            if (
                recordingTimeMapping.mapped
            )
            {
                if (
                    !recordingTimeFieldAppended
                )
                {
                    recordingTimeCanonicalStart =
                        projection.metadata.length;


                    projection.append(
                        native,
                        recordingTimeMapping
                    );


                    recordingTimeFieldAppended =
                        true;
                }
                else
                {
                    projection.appendLinkedMapped(
                        native,
                        recordingTimeCanonicalStart
                    );
                }
            }
            else
            {
                projection.append(
                    native,
                    recordingTimeMapping
                );
            }


            continue;
        }


        projection.append(
            native,
            perFrameMappings[index]
        );
    }


    return projection;
}


/++
Decodes and canonically projects one validated ID3v2.2 frame sequence.

All structural traversal, whole-tag unsynchronisation handling, frame-count
validation and semantic codec failures are delegated to
`decodeId3v22NativeFrameSequence`.

Params:
    layout = Previously validated ID3v2.2 frame-sequence layout.
    tagUnsynchronised = Whether the enclosing ID3v2.2 tag declares whole-tag
        unsynchronisation.

Returns:
    Canonical projection or the structured native-sequence decoding error.
+/
ParseResult!Id3v22CanonicalProjection
projectId3v22FrameSequenceToCanonical(
    Id3v22FrameSequenceLayout layout,
    bool tagUnsynchronised = false
)
    @safe
{
    auto nativeResult =
        decodeId3v22NativeFrameSequence(
            layout,
            tagUnsynchronised
        );


    if (
        nativeResult.hasError
    )
    {
        return
            ParseResult!Id3v22CanonicalProjection
                .failure(
                    nativeResult.error
                );
    }


    return
        ParseResult!Id3v22CanonicalProjection
            .success(
                projectId3v22NativeFrameSequenceToCanonical(
                    nativeResult.value
                )
            );
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.canonical_mapping :
        Id3v22CanonicalMappingStatus;

    import audiotag.id3v2.v22.frame_sequence :
        parseId3v22FrameSequenceLayout;

    import audiotag.metadata.value :
        MetadataDateTimeList,
        MetadataText;
}


/// Mixed mapped and unknown frames preserve native and canonical order.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * TT2 = Latin-1 "Title".
             */
            'T', 'T', '2',
            0x00, 0x00, 0x06,

            0x00,
            'T', 'i', 't', 'l', 'e',


            /*
             * Unknown but structurally valid frame.
             */
            'Z', 'Z', 'Z',
            0x00, 0x00, 0x01,

            0x55,


            /*
             * TP1 = Latin-1 "Artist".
             */
            'T', 'P', '1',
            0x00, 0x00, 0x07,

            0x00,
            'A', 'r', 't', 'i', 's', 't'
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
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
        projectId3v22FrameSequenceToCanonical(
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
        Id3v22CanonicalMappingStatus.mapped
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
        Id3v22CanonicalMappingStatus
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
        "ZZZ"
    );


    assert(
        projection.frames[2]
            .status ==
        Id3v22CanonicalMappingStatus.mapped
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


/// The native-sequence overload performs no second parse or semantic decode.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,

            0x00,
            'X'
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                300
            )
        );


    assert(
        layoutResult.hasValue
    );


    auto nativeResult =
        decodeId3v22NativeFrameSequence(
            layoutResult.value
        );


    assert(
        nativeResult.hasValue
    );


    const projection =
        projectId3v22NativeFrameSequenceToCanonical(
            nativeResult.value
        );


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
        projection.metadata[0]
            .value.match!(
                (MetadataText text) =>
                    text.value ==
                    "X",

                _ =>
                    false
            )
    );


    assert(
        projection.frames[0]
            .native.sourceOffset ==
        300
    );


    assert(
        projection.frames[0]
            .native.sourceLength ==
        bytes.length
    );
}


/// Semantic native-codec errors propagate through the convenience wrapper.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * Structurally valid TT2 but encoding marker 0x02 is invalid in
             * ID3v2.2.
             */
            'T', 'T', '2',
            0x00, 0x00, 0x02,

            0x02,
            'X'
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                400
            )
        );


    assert(
        layoutResult.hasValue
    );


    auto result =
        projectId3v22FrameSequenceToCanonical(
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
        406
    );
}


/// A stale or manually inconsistent frame count remains a structured error.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,

            0x00,
            'X'
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
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
        projectId3v22FrameSequenceToCanonical(
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


/// Whole-tag unsynchronisation is delegated to native-sequence decoding.
unittest
{
    /*
     * Logical TT2 frame data:
     *
     *   00 41 FF E1
     *
     * Physical representation:
     *
     *   00 41 FF 00 E1
     *
     * The frame header declares four logical data bytes.
     */
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x04,

            0x00,
            'A',
            0xFF,
            0x00,
            0xE1
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
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


    assert(
        layoutResult.value.frameBytes.length ==
        bytes.length
    );


    auto result =
        projectId3v22FrameSequenceToCanonical(
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
        Id3v22CanonicalMappingStatus.mapped
    );


    /*
     * Canonical provenance retains the complete physical frame, including the
     * unsynchronisation stuffing byte.
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


/// Legacy recording-time frames aggregate into one shared canonical field.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'Y', 'E',
            0x00, 0x00, 0x05,

            0x00,
            '2', '0', '0', '0',


            'T', 'T', '2',
            0x00, 0x00, 0x02,

            0x00,
            'X',


            'T', 'D', 'A',
            0x00, 0x00, 0x05,

            0x00,
            '2', '9', '0', '2',


            'T', 'I', 'M',
            0x00, 0x00, 0x05,

            0x00,
            '2', '3', '5', '9'
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                1500
            )
        );


    assert(
        layoutResult.hasValue
    );


    assert(
        layoutResult.value.frameCount ==
        4
    );


    auto result =
        projectId3v22FrameSequenceToCanonical(
            layoutResult.value
        );


    assert(
        result.hasValue
    );


    const projection =
        result.value;


    assert(
        projection.frameCount ==
        4
    );


    /*
     * recordingDate is inserted when the first recording-time frame is
     * encountered; title follows at its own source position.
     */
    assert(
        projection.metadata.length ==
        2
    );


    assert(
        projection.metadata[0]
            .key.name ==
        "recordingDate"
    );


    assert(
        projection.metadata[1]
            .key.name ==
        "title"
    );


    assert(
        projection.metadata[0]
            .provenance.length ==
        3
    );


    assert(
        projection.metadata[0]
            .provenance[0]
            .native.identifier ==
        "TYE"
    );


    assert(
        projection.metadata[0]
            .provenance[1]
            .native.identifier ==
        "TDA"
    );


    assert(
        projection.metadata[0]
            .provenance[2]
            .native.identifier ==
        "TIM"
    );


    assert(
        projection.metadata[0]
            .value.match!(
                (const(MetadataDateTimeList) list) =>
                    list.values.length == 1 &&
                    list.values[0].hasYear &&
                    list.values[0].year == 2000 &&
                    list.values[0].hasMonth &&
                    list.values[0].month == 2 &&
                    list.values[0].hasDay &&
                    list.values[0].day == 29 &&
                    list.values[0].hasHour &&
                    list.values[0].hour == 23 &&
                    list.values[0].hasMinute &&
                    list.values[0].minute == 59 &&
                    !list.values[0].hasUtcOffset,

                _ =>
                    false
            )
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
            .canonicalStart ==
        1
    );


    assert(
        projection.frames[1]
            .canonicalCount ==
        1
    );


    assert(
        projection.frames[2]
            .canonicalStart ==
        0
    );


    assert(
        projection.frames[2]
            .canonicalCount ==
        1
    );


    assert(
        projection.frames[3]
            .canonicalStart ==
        0
    );


    assert(
        projection.frames[3]
            .canonicalCount ==
        1
    );
}


/// Invalid recording-time groups remain preserved as unrepresentable native frames.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'Y', 'E',
            0x00, 0x00, 0x05,

            0x00,
            '2', '0', '0', '1',


            'T', 'D', 'A',
            0x00, 0x00, 0x05,

            0x00,
            '2', '9', '0', '2'
        ];


    auto layoutResult =
        parseId3v22FrameSequenceLayout(
            ByteSpan(
                bytes,
                2000
            )
        );


    assert(
        layoutResult.hasValue
    );


    auto result =
        projectId3v22FrameSequenceToCanonical(
            layoutResult.value
        );


    assert(
        result.hasValue
    );


    const projection =
        result.value;


    assert(
        projection.frameCount ==
        2
    );


    assert(
        projection.metadata.empty
    );


    foreach (
        record;
        projection.frames
    )
    {
        assert(
            record.status ==
            Id3v22CanonicalMappingStatus
                .unrepresentableValueShape
        );


        assert(
            record.canonicalCount ==
            0
        );
    }
}
