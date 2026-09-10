/++
Physical frame serialization for legacy ID3v2.3 recording-time components.

The semantic compound planner already decomposes one canonical
`recordingDate` into exact `TYER`, `TDAT` and `TIME` text values. These
components cannot use the ordinary canonical text-information frame writer
because that writer deliberately requires a one-key-to-one-frame reverse
canonical target.

This module serializes one already selected recording-time component as a
complete native ID3v2.3 frame while retaining the same structural regeneration
policy used by other mapped text-information frames.

No tag-level unsynchronisation, padding, tag header or container bytes are
handled here.
+/
module audiotag.id3v2.v23.recording_time_frame_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader;

import audiotag.id3v2.v23.frame_header_write :
    serializeId3v23FrameHeader;

import audiotag.id3v2.v23.recording_time :
    Id3v23RecordingTimeText,
    parseId3v23RecordingTime;

import audiotag.id3v2.v23.recording_time_group_write_plan :
    Id3v23RecordingTimeComponent;

import audiotag.id3v2.v23.regeneration_policy :
    Id3v23MappedFrameRegenerationFormatPlan;

import audiotag.id3v2.v23.text_information_write :
    serializeId3v23TextInformationPayload;


private string
frameIdFor(
    Id3v23RecordingTimeComponent component
)
    @safe pure nothrow @nogc
{
    final switch (component)
    {
        case Id3v23RecordingTimeComponent.year:
            return "TYER";

        case Id3v23RecordingTimeComponent.date:
            return "TDAT";

        case Id3v23RecordingTimeComponent.time:
            return "TIME";
    }
}


private bool
componentValueValid(
    Id3v23RecordingTimeComponent component,
    string value
)
    @safe pure nothrow @nogc
{
    Id3v23RecordingTimeText input;

    final switch (component)
    {
        case Id3v23RecordingTimeComponent.year:
            input.hasYear = true;
            input.year = value;
            break;

        case Id3v23RecordingTimeComponent.date:
            input.hasDate = true;
            input.date = value;
            break;

        case Id3v23RecordingTimeComponent.time:
            input.hasTime = true;
            input.time = value;
            break;
    }

    return
        parseId3v23RecordingTime(
            input
        ).parsed;
}


private SerializationResult!(ubyte[])
serializeComponentFrame(
    Id3v23RecordingTimeComponent component,
    string value,
    ubyte statusFlags,
    ubyte formatFlags,
    bool hasGroupingIdentity,
    ubyte groupingIdentity
)
    @safe
{
    if (!componentValueValid(component, value))
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue
                    )
                );
    }

    const groupingFlag =
        (
            formatFlags &
            0x20
        ) != 0;

    if (
        groupingFlag !=
        hasGroupingIdentity
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        9,
                        formatFlags
                    )
                );
    }

    auto payload =
        serializeId3v23TextInformationPayload(
            value
        );

    if (payload.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    payload.error
                );
    }

    const size_t prefixLength =
        hasGroupingIdentity
        ? 1
        : 0;

    if (
        payload.value.length >
        uint.max -
            prefixLength
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        4,
                        cast(ulong)
                            payload.value.length +
                            cast(ulong)
                                prefixLength,
                        uint.max
                    )
                );
    }

    const frameDataSize =
        prefixLength +
        payload.value.length;

    const frameId =
        frameIdFor(
            component
        );

    assert(frameId.length == 4);

    Id3v23FrameHeader header;

    foreach (index; 0 .. 4)
    {
        header.id[index] =
            frameId[index];
    }

    header.size =
        cast(uint)
            frameDataSize;

    header.statusFlags =
        statusFlags;

    header.formatFlags =
        formatFlags;

    auto encodedHeader =
        serializeId3v23FrameHeader(
            header
        );

    if (encodedHeader.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    encodedHeader.error
                );
    }

    auto output =
        new ubyte[
            encodedHeader.value.length +
            frameDataSize
        ];

    size_t position;

    output[
        position ..
        position + encodedHeader.value.length
    ] =
        encodedHeader.value[];

    position +=
        encodedHeader.value.length;

    if (hasGroupingIdentity)
    {
        output[position++] =
            groupingIdentity;
    }

    output[
        position ..
        position + payload.value.length
    ] =
        payload.value[];

    position +=
        payload.value.length;

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/++
Serializes one new TYER, TDAT or TIME frame.

New frames use zero status and format flags because there is no native source
frame whose structural state should be inherited.
+/
SerializationResult!(ubyte[])
serializeNewId3v23RecordingTimeComponentFrame(
    Id3v23RecordingTimeComponent component,
    string value
)
    @safe
{
    return
        serializeComponentFrame(
            component,
            value,
            0,
            0,
            false,
            0
        );
}


/++
Serializes one regenerated existing TYER, TDAT or TIME frame.

The supplied format plan must already have been derived from the matching
source-native frame. Writable alteration flags and grouping identity are
preserved exactly; compressed, encrypted or read-only source structures remain
blocked by the regeneration-policy layer.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23RecordingTimeComponentFrame(
    Id3v23RecordingTimeComponent component,
    string value,
    const(Id3v23MappedFrameRegenerationFormatPlan) formatPlan
)
    @safe
{
    if (!formatPlan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        0,
                        cast(ulong)
                            formatPlan.status
                    )
                );
    }

    if (
        (
            formatPlan.statusFlags &
            0x3F
        ) != 0
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidFlags,
                        8,
                        formatPlan.statusFlags,
                        0xC0
                    )
                );
    }

    if (
        (
            formatPlan.formatFlags &
            0xDF
        ) != 0
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidFlags,
                        9,
                        formatPlan.formatFlags,
                        0x20
                    )
                );
    }

    return
        serializeComponentFrame(
            component,
            value,
            formatPlan.statusFlags,
            formatPlan.formatFlags,
            formatPlan.hasGroupingIdentity,
            formatPlan.groupingIdentity
        );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.regeneration_policy :
        planId3v23MappedFrameRegenerationFormat;


    private Id3v23MappedFrameRegenerationFormatPlan
    regenerationPlanFromSource(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto frame =
            cursor.parseId3v23FrameEnvelope();

        assert(frame.hasValue);
        assert(cursor.empty);

        auto planned =
            planId3v23MappedFrameRegenerationFormat(
                frame.value
            );

        assert(planned.hasValue);
        assert(planned.value.writable);

        return planned.value;
    }
}


/// New recording-time components use exact native identifiers and text payloads.
unittest
{
    struct Case
    {
        Id3v23RecordingTimeComponent component;
        string value;
        string id;
    }

    foreach (
        testCase;
        [
            Case(
                Id3v23RecordingTimeComponent.year,
                "2000",
                "TYER"
            ),
            Case(
                Id3v23RecordingTimeComponent.date,
                "2902",
                "TDAT"
            ),
            Case(
                Id3v23RecordingTimeComponent.time,
                "2359",
                "TIME"
            )
        ]
    )
    {
        auto serialized =
            serializeNewId3v23RecordingTimeComponentFrame(
                testCase.component,
                testCase.value
            );

        assert(serialized.hasValue);
        assert(serialized.value.length == 15);

        assert(
            serialized.value[0 .. 4] ==
            cast(const(ubyte)[])
                testCase.id
        );

        assert(
            serialized.value[4 .. 10] ==
            [
                0x00, 0x00, 0x00, 0x05,
                0x00, 0x00
            ]
        );

        assert(serialized.value[10] == 0x00);

        assert(
            serialized.value[11 .. 15] ==
            cast(const(ubyte)[])
                testCase.value
        );
    }
}


/// Malformed component text is rejected defensively.
unittest
{
    auto invalidYear =
        serializeNewId3v23RecordingTimeComponentFrame(
            Id3v23RecordingTimeComponent.year,
            "200"
        );

    assert(invalidYear.hasError);

    assert(
        invalidYear.error.code ==
        SerializationErrorCode.invalidValue
    );

    auto invalidTime =
        serializeNewId3v23RecordingTimeComponentFrame(
            Id3v23RecordingTimeComponent.time,
            "2460"
        );

    assert(invalidTime.hasError);
}


/// Regeneration preserves a source grouping identity and writable flags.
unittest
{
    const ubyte[] source =
        [
            'T', 'Y', 'E', 'R',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x20,
            0x42,
            0x00,
            '1', '9', '9', '9'
        ];

    const formatPlan =
        regenerationPlanFromSource(
            source
        );

    assert(formatPlan.hasGroupingIdentity);
    assert(formatPlan.groupingIdentity == 0x42);

    auto serialized =
        serializeRegeneratedId3v23RecordingTimeComponentFrame(
            Id3v23RecordingTimeComponent.year,
            "2000",
            formatPlan
        );

    assert(serialized.hasValue);

    const ubyte[] expected =
        [
            'T', 'Y', 'E', 'R',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x20,
            0x42,
            0x00,
            '2', '0', '0', '0'
        ];

    assert(
        serialized.value ==
        expected
    );
}
