/++
Canonical aggregation of legacy ID3v2.3 recording-time frames.

ID3v2.3 represents one recording time through up to three text-information
frames: `TYER` (YYYY), `TDAT` (DDMM), and `TIME` (HHMM). These frames cannot
be mapped correctly in isolation, so this module combines the complete native
group into at most one canonical `recordingDate`.

Every contributing native frame remains preserved by the surrounding sequence
projection. The resulting canonical field carries exact provenance for all
contributing frames in source order. No timezone semantics are invented.
+/
module audiotag.id3v2.v23.canonical_recording_time;

import std.sumtype : match;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

import audiotag.id3v2.v23.recording_time :
    Id3v23RecordingTimeParseResult,
    Id3v23RecordingTimeText,
    parseId3v23RecordingTime;

import audiotag.id3v2.v23.text_information :
    Id3v23TextInformationOutcome;

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
Returns whether an identifier belongs to the legacy ID3v2.3 recording-time
group.
+/
bool isId3v23RecordingTimeFrameId(
    const ref char[4] id
)
    @safe pure nothrow @nogc
{
    return
        idEquals(id, "TYER") ||
        idEquals(id, "TDAT") ||
        idEquals(id, "TIME");
}


/++
Maps all legacy recording-time frames in one native sequence to at most one
canonical `recordingDate`.

No partial value is emitted when one component requires transformation.
Duplicate component identifiers or invalid decoded values are explicitly
unrepresentable rather than being silently selected or normalized.
+/
Id3v23CanonicalMappingResult
mapId3v23RecordingTimeFramesToCanonical(
    Id3v23NativeFrame[] frames
)
    @safe
{
    bool present;
    bool seenYear;
    bool seenDate;
    bool seenTime;
    bool requiresTransformation;

    Id3v23RecordingTimeText input;
    MetadataProvenance[] provenance;

    foreach (native; frames)
    {
        if (
            !isId3v23RecordingTimeFrameId(
                native.envelope.header.id
            )
        )
        {
            continue;
        }

        present = true;

        if (
            idEquals(
                native.envelope.header.id,
                "TYER"
            )
        )
        {
            if (seenYear)
            {
                return
                    Id3v23CanonicalMappingResult
                        .unrepresentable();
            }

            seenYear = true;
        }
        else if (
            idEquals(
                native.envelope.header.id,
                "TDAT"
            )
        )
        {
            if (seenDate)
            {
                return
                    Id3v23CanonicalMappingResult
                        .unrepresentable();
            }

            seenDate = true;
        }
        else
        {
            if (seenTime)
            {
                return
                    Id3v23CanonicalMappingResult
                        .unrepresentable();
            }

            seenTime = true;
        }

        const view =
            inspectTextOutcome(
                native
            );

        if (!view.textInformation)
        {
            return
                Id3v23CanonicalMappingResult
                    .unrepresentable();
        }

        if (!view.decoded)
        {
            requiresTransformation = true;
            continue;
        }

        if (
            idEquals(
                native.envelope.header.id,
                "TYER"
            )
        )
        {
            input.hasYear = true;
            input.year = view.value;
        }
        else if (
            idEquals(
                native.envelope.header.id,
                "TDAT"
            )
        )
        {
            input.hasDate = true;
            input.date = view.value;
        }
        else
        {
            input.hasTime = true;
            input.time = view.value;
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

    if (!present)
    {
        return
            Id3v23CanonicalMappingResult
                .unsupported();
    }

    const hasDecodedComponent =
        input.hasYear ||
        input.hasDate ||
        input.hasTime;

    Id3v23RecordingTimeParseResult parsed;

    if (hasDecodedComponent)
    {
        parsed =
            parseId3v23RecordingTime(
                input
            );

        if (!parsed.parsed)
        {
            return
                Id3v23CanonicalMappingResult
                    .unrepresentable();
        }
    }

    if (requiresTransformation)
    {
        return
            Id3v23CanonicalMappingResult
                .transformationRequired();
    }

    if (!hasDecodedComponent)
    {
        return
            Id3v23CanonicalMappingResult
                .unrepresentable();
    }

    MetadataDateTime canonical;

    canonical.hasYear = parsed.value.hasYear;
    canonical.year = parsed.value.year;

    canonical.hasMonth = parsed.value.hasMonth;
    canonical.month = parsed.value.month;

    canonical.hasDay = parsed.value.hasDay;
    canonical.day = parsed.value.day;

    canonical.hasHour = parsed.value.hasHour;
    canonical.hour = parsed.value.hour;

    canonical.hasMinute = parsed.value.hasMinute;
    canonical.minute = parsed.value.minute;

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
        Id3v23CanonicalMappingResult
            .success(
                field
            );
}


private struct TextOutcomeView
{
    bool textInformation;
    bool decoded;
    string value;
}


private TextOutcomeView inspectTextOutcome(
    Id3v23NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                TextOutcomeView(
                    true,
                    outcome.decoded,
                    outcome.decoded
                        ? outcome.text.value
                        : ""
                ),

            _ =>
                TextOutcomeView.init
        );
}


private bool idEquals(
    const ref char[4] id,
    string expected
)
    @safe pure nothrow @nogc
{
    return
        expected.length == 4 &&
        id[0] == expected[0] &&
        id[1] == expected[1] &&
        id[2] == expected[2] &&
        id[3] == expected[3];
}


private string identifierFor(
    const ref char[4] id
)
    @safe pure nothrow @nogc
{
    if (idEquals(id, "TYER"))
        return "TYER";

    if (idEquals(id, "TDAT"))
        return "TDAT";

    if (idEquals(id, "TIME"))
        return "TIME";

    return "";
}


private MetadataProvenance makeProvenance(
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


private void assertRegisteredShape(
    MetadataField field
)
    @safe
{
    const definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);

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

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent;

    import audiotag.id3v2.v23.text_information :
        Id3v23TextInformationAvailability,
        Id3v23TextInformationFrame;


    private Id3v23NativeFrame testRecordingTimeFrame(
        string id,
        string value,
        size_t sourceOffset,
        Id3v23TextInformationAvailability availability =
            Id3v23TextInformationAvailability.decoded
    )
        @safe
    {
        assert(id.length == 4);

        Id3v23TextInformationFrame text;

        text.sourceOffset =
            sourceOffset;

        text.id[] =
            id[];

        text.value =
            value;

        Id3v23TextInformationOutcome outcome;

        outcome.availability =
            availability;

        outcome.text =
            text;

        Id3v23NativeFrameContent content =
            outcome;

        Id3v23FrameEnvelope envelope;

        envelope.header.sourceOffset =
            sourceOffset;

        envelope.header.id[] =
            id[];

        envelope.data =
            ByteSpan(
                [],
                sourceOffset + 10
            );

        return
            Id3v23NativeFrame(
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
                "TYER",
                "2000",
                100
            ),
            testRecordingTimeFrame(
                "TDAT",
                "2902",
                200
            ),
            testRecordingTimeFrame(
                "TIME",
                "2359",
                300
            )
        ];

    const mapping =
        mapId3v23RecordingTimeFramesToCanonical(
            frames
        );

    assert(mapping.mapped);

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
        "TYER"
    );

    assert(
        mapping.field.provenance[1]
            .native.identifier ==
        "TDAT"
    );

    assert(
        mapping.field.provenance[2]
            .native.identifier ==
        "TIME"
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
                "TIME",
                "0745",
                100
            )
        ];

    const mapping =
        mapId3v23RecordingTimeFramesToCanonical(
            frames
        );

    assert(mapping.mapped);

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


/// Duplicate component identifiers are ambiguous and remain native-only.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TYER",
                "1999",
                100
            ),
            testRecordingTimeFrame(
                "TYER",
                "2000",
                200
            )
        ];

    const mapping =
        mapId3v23RecordingTimeFramesToCanonical(
            frames
        );

    assert(!mapping.mapped);

    assert(
        mapping.status ==
        Id3v23CanonicalMappingResult
            .unrepresentable()
            .status
    );
}


/// A transformed component blocks partial canonical projection.
unittest
{
    auto frames =
        [
            testRecordingTimeFrame(
                "TYER",
                "",
                100,
                Id3v23TextInformationAvailability
                    .requiresDecompression
            ),
            testRecordingTimeFrame(
                "TDAT",
                "1206",
                200
            )
        ];

    const mapping =
        mapId3v23RecordingTimeFramesToCanonical(
            frames
        );

    assert(!mapping.mapped);

    assert(
        mapping.status ==
        Id3v23CanonicalMappingResult
            .transformationRequired()
            .status
    );
}


/// Absence of legacy recording-time frames is not a mapping failure.
unittest
{
    Id3v23NativeFrame[] frames;

    const mapping =
        mapId3v23RecordingTimeFramesToCanonical(
            frames
        );

    assert(!mapping.mapped);

    assert(
        mapping.status ==
        Id3v23CanonicalMappingResult
            .unsupported()
            .status
    );
}
