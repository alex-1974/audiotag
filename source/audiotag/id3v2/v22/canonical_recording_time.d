/++
Canonical aggregation of legacy ID3v2.2 recording-time frames.

ID3v2.2 represents one recording time through up to three ordinary text
information frames:

- `TYE` (YYYY)
- `TDA` (DDMM)
- `TIM` (HHMM)

These frames cannot be mapped correctly in isolation. This module combines the
complete native group into at most one canonical `recordingDate`.

Every contributing native frame remains preserved by the surrounding sequence
projection. The resulting canonical field carries exact provenance for all
contributing frames in source order. No timezone semantics are invented.

Unlike ID3v2.3, ID3v2.2 has no per-frame compression/encryption state. A
successfully decoded native recording-time frame therefore needs no
transformation-availability branch here.
+/
module audiotag.id3v2.v22.canonical_recording_time;

import std.sumtype :
    match;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.id3v2.v22.recording_time :
    Id3v22RecordingTimeText,
    parseId3v22RecordingTime;

import audiotag.id3v2.v22.text_information :
    Id3v22TextInformationFrame;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

import audiotag.metadata.provenance :
    MetadataConfidence,
    MetadataProvenance,
    MetadataSystem,
    NativeMetadataIdentifier;

import audiotag.metadata.registry :
    findMetadataFieldDefinition;

import audiotag.metadata.value :
    MetadataDateTime,
    MetadataDateTimeList,
    MetadataValue;


/++
Returns whether an identifier belongs to the legacy ID3v2.2 recording-time
group.
+/
bool
isId3v22RecordingTimeFrameId(
    const ref char[3] id
)
    @safe pure nothrow @nogc
{
    return
        idEquals(id, "TYE") ||
        idEquals(id, "TDA") ||
        idEquals(id, "TIM");
}


/++
Maps all legacy recording-time frames in one native sequence to at most one
canonical `recordingDate`.

Duplicate component identifiers or invalid decoded values are explicitly
unrepresentable rather than being silently selected or normalized.

Params:
    frames = Complete native frames from one ID3v2.2 frame sequence.

Returns:
    One canonical recording-date mapping result, `unsupportedFrame` when the
    sequence contains no legacy recording-time frame, or
    `unrepresentableValueShape` for an ambiguous/invalid group.
+/
Id3v22CanonicalMappingResult
mapId3v22RecordingTimeFramesToCanonical(
    Id3v22NativeFrame[] frames
)
    @safe
{
    bool present;
    bool seenYear;
    bool seenDate;
    bool seenTime;

    Id3v22RecordingTimeText input;
    MetadataProvenance[] provenance;


    foreach (
        native;
        frames
    )
    {
        if (
            !isId3v22RecordingTimeFrameId(
                native.envelope.header.id
            )
        )
        {
            continue;
        }


        present =
            true;


        if (
            idEquals(
                native.envelope.header.id,
                "TYE"
            )
        )
        {
            if (seenYear)
            {
                return
                    Id3v22CanonicalMappingResult
                        .unrepresentable();
            }

            seenYear =
                true;
        }
        else if (
            idEquals(
                native.envelope.header.id,
                "TDA"
            )
        )
        {
            if (seenDate)
            {
                return
                    Id3v22CanonicalMappingResult
                        .unrepresentable();
            }

            seenDate =
                true;
        }
        else
        {
            if (seenTime)
            {
                return
                    Id3v22CanonicalMappingResult
                        .unrepresentable();
            }

            seenTime =
                true;
        }


        const view =
            inspectTextFrame(
                native
            );


        if (
            !view.textInformation
        )
        {
            return
                Id3v22CanonicalMappingResult
                    .unrepresentable();
        }


        if (
            idEquals(
                native.envelope.header.id,
                "TYE"
            )
        )
        {
            input.hasYear =
                true;

            input.year =
                view.value;
        }
        else if (
            idEquals(
                native.envelope.header.id,
                "TDA"
            )
        )
        {
            input.hasDate =
                true;

            input.date =
                view.value;
        }
        else
        {
            input.hasTime =
                true;

            input.time =
                view.value;
        }


        provenance ~=
            makeProvenance(
                identifierFor(
                    native.envelope.header.id
                ),
                native.sourceOffset,
                native.sourceLength
            );
    }


    if (
        !present
    )
    {
        return
            Id3v22CanonicalMappingResult
                .unsupported();
    }


    const parsed =
        parseId3v22RecordingTime(
            input
        );


    if (
        !parsed.parsed
    )
    {
        return
            Id3v22CanonicalMappingResult
                .unrepresentable();
    }


    MetadataDateTime canonical;


    canonical.hasYear =
        parsed.value.hasYear;

    canonical.year =
        parsed.value.year;


    canonical.hasMonth =
        parsed.value.hasMonth;

    canonical.month =
        parsed.value.month;


    canonical.hasDay =
        parsed.value.hasDay;

    canonical.day =
        parsed.value.day;


    canonical.hasHour =
        parsed.value.hasHour;

    canonical.hour =
        parsed.value.hour;


    canonical.hasMinute =
        parsed.value.hasMinute;

    canonical.minute =
        parsed.value.minute;


    auto field =
        MetadataField(
            MetadataKey(
                "recordingDate"
            ),
            MetadataValue(
                MetadataDateTimeList(
                    [
                        canonical
                    ]
                )
            ),
            provenance
        );


    assertRegisteredShape(
        field
    );


    return
        Id3v22CanonicalMappingResult
            .success(
                field
            );
}


private struct TextFrameView
{
    bool textInformation;
    string value;
}


private TextFrameView
inspectTextFrame(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22TextInformationFrame frame) =>
                TextFrameView(
                    true,
                    frame.value
                ),

            _ =>
                TextFrameView.init
        );
}


private bool
idEquals(
    const ref char[3] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 3 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2];
}


private string
identifierFor(
    const ref char[3] id
)
    @safe pure nothrow @nogc
{
    if (
        idEquals(
            id,
            "TYE"
        )
    )
    {
        return "TYE";
    }


    if (
        idEquals(
            id,
            "TDA"
        )
    )
    {
        return "TDA";
    }


    if (
        idEquals(
            id,
            "TIM"
        )
    )
    {
        return "TIM";
    }


    return "";
}


private MetadataProvenance
makeProvenance(
    string nativeIdentifier,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return
        MetadataProvenance(
            NativeMetadataIdentifier(
                MetadataSystem.id3v2,
                nativeIdentifier
            ),
            sourceOffset,
            sourceLength,
            MetadataConfidence.exact
        );
}


private void
assertRegisteredShape(
    MetadataField field
)
    @safe
{
    const definition =
        findMetadataFieldDefinition(
            field.key
        );


    assert(
        definition.found
    );


    assert(
        definition.definition
            .accepts(
                field.value
            )
    );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.canonical_mapping :
        Id3v22CanonicalMappingStatus;

    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame;


    private Id3v22NativeFrame
    testRecordingTimeFrame(
        string id,
        string value,
        size_t sourceOffset
    )
        @safe
    {
        assert(
            id.length ==
            3
        );


        Id3v22TextInformationFrame text;


        text.sourceOffset =
            sourceOffset;


        text.id[] =
            id[];


        text.value =
            value;


        Id3v22NativeFrameContent content =
            text;


        Id3v22FrameEnvelope envelope;


        envelope.header.sourceOffset =
            sourceOffset;


        envelope.header.id[] =
            id[];


        envelope.data =
            ByteSpan(
                [],
                sourceOffset + 6
            );


        return
            Id3v22NativeFrame(
                envelope,
                content
            );
    }


    private Id3v22NativeFrame
    testMismatchedRecordingTimeFrame(
        string id,
        size_t sourceOffset
    )
        @safe
    {
        assert(
            id.length ==
            3
        );


        Id3v22NativeFrameContent content =
            Id3v22UnknownFrame();


        Id3v22FrameEnvelope envelope;


        envelope.header.sourceOffset =
            sourceOffset;


        envelope.header.id[] =
            id[];


        envelope.data =
            ByteSpan(
                [],
                sourceOffset + 6
            );


        return
            Id3v22NativeFrame(
                envelope,
                content
            );
    }
}


/// Complete legacy components map to one floating recording timestamp.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TYE",
                "2000",
                100
            ),
            testRecordingTimeFrame(
                "TDA",
                "2902",
                200
            ),
            testRecordingTimeFrame(
                "TIM",
                "2359",
                300
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        mapping.mapped
    );


    assert(
        mapping.field.key.name ==
        "recordingDate"
    );


    assert(
        mapping.field.provenance.length ==
        3
    );


    assert(
        mapping.field.provenance[0]
            .native.identifier ==
        "TYE"
    );


    assert(
        mapping.field.provenance[1]
            .native.identifier ==
        "TDA"
    );


    assert(
        mapping.field.provenance[2]
            .native.identifier ==
        "TIM"
    );


    assert(
        mapping.field.provenance[0]
            .sourceOffset ==
        100
    );


    assert(
        mapping.field.provenance[0]
            .sourceLength ==
        6
    );


    assert(
        mapping.field.value.match!(
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
}


/// A partial native group preserves exactly the components that are present.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TIM",
                "0745",
                100
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        mapping.mapped
    );


    assert(
        mapping.field.value.match!(
            (const(MetadataDateTimeList) list) =>
                list.values.length == 1 &&
                !list.values[0].hasDate &&
                list.values[0].hasHour &&
                list.values[0].hour == 7 &&
                list.values[0].hasMinute &&
                list.values[0].minute == 45 &&
                !list.values[0].hasUtcOffset,

            _ =>
                false
        )
    );
}


/// Contributing provenance remains in native source order.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TIM",
                "0745",
                100
            ),
            testRecordingTimeFrame(
                "TYE",
                "1999",
                200
            ),
            testRecordingTimeFrame(
                "TDA",
                "1206",
                300
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        mapping.mapped
    );


    assert(
        mapping.field.provenance[0]
            .native.identifier ==
        "TIM"
    );


    assert(
        mapping.field.provenance[1]
            .native.identifier ==
        "TYE"
    );


    assert(
        mapping.field.provenance[2]
            .native.identifier ==
        "TDA"
    );
}


/// Duplicate component identifiers are ambiguous and remain native-only.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TYE",
                "1999",
                100
            ),
            testRecordingTimeFrame(
                "TYE",
                "2000",
                200
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        !mapping.mapped
    );


    assert(
        mapping.status ==
        Id3v22CanonicalMappingStatus
            .unrepresentableValueShape
    );
}


/// Invalid component syntax is preserved native-only.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TYE",
                "20A1",
                100
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        !mapping.mapped
    );


    assert(
        mapping.status ==
        Id3v22CanonicalMappingStatus
            .unrepresentableValueShape
    );
}


/// Impossible calendar combinations are preserved native-only.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TYE",
                "2001",
                100
            ),
            testRecordingTimeFrame(
                "TDA",
                "2902",
                200
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        !mapping.mapped
    );


    assert(
        mapping.status ==
        Id3v22CanonicalMappingStatus
            .unrepresentableValueShape
    );
}


/// A recording-time identifier with incompatible native content is explicit.
unittest
{
    auto frames =
        [
            testMismatchedRecordingTimeFrame(
                "TYE",
                100
            )
        ];


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        !mapping.mapped
    );


    assert(
        mapping.status ==
        Id3v22CanonicalMappingStatus
            .unrepresentableValueShape
    );
}


/// Absence of legacy recording-time frames is not a mapping failure.
unittest
{
    Id3v22NativeFrame[] frames;


    const mapping =
        mapId3v22RecordingTimeFramesToCanonical(
            frames
        );


    assert(
        !mapping.mapped
    );


    assert(
        mapping.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}
