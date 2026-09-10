/++
Mapping of decoded ID3v2.4 text-information frames to canonical
metadata fields.

This module is a bridge between the native ID3v2.4 semantic layer and
the format-independent canonical metadata model.

Only mappings whose canonical semantics are currently explicit are
implemented here:

- TIT2 -> title
- TPE1 -> artist
- TALB -> album
- TRCK -> track
- TPOS -> disc
- TCON -> genre
- TDRC -> recordingDate

Valid native metadata that cannot yet be represented without loss is
reported as such rather than being classified as malformed input.
+/
module audiotag.id3v2.v24.canonical_text;

import std.sumtype :
    match;

import audiotag.id3v2.common.genre :
    decodeId3v24Genres;

import audiotag.id3v2.common.position :
    parseId3v2Position;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.native_state :
    Id3v24NativeFrameState,
    id3v24NativeFrameState;

import audiotag.id3v2.v24.text_information :
    Id3v24TextInformationFrame,
    Id3v24TextInformationOutcome;

import audiotag.id3v2.v24.timestamp :
    Id3v24Timestamp,
    parseId3v24Timestamp;

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
    MetadataPosition,
    MetadataText,
    MetadataTextList,
    MetadataValue;


/++
Backward-compatible text-mapper name for the common ID3v2.4 canonical
mapping status.
+/
alias Id3v24CanonicalTextMappingStatus =
    Id3v24CanonicalMappingStatus;


/++
Backward-compatible text-mapper name for the common ID3v2.4 canonical
mapping result.
+/
alias Id3v24CanonicalTextMappingResult =
    Id3v24CanonicalMappingResult;


/++
Maps one decoded ID3v2.4 text-information frame to canonical metadata.

This function expects an already decoded native frame. Parsing,
character decoding, unsynchronisation and transformation availability
are responsibilities of the native ID3v2.4 codec layer.

Returns:
    A successful canonical field, an unsupported-frame result, or an
    explicit lossless-representation limitation.
+/
Id3v24CanonicalTextMappingResult
mapId3v24TextInformationFrameToCanonical(
    Id3v24TextInformationFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    if (idEquals(frame.id, "TIT2"))
    {
        if (frame.values.length != 1)
            return Id3v24CanonicalTextMappingResult.unrepresentable();

        return Id3v24CanonicalTextMappingResult.success(
            makeScalarTextField(
                "title",
                "TIT2",
                frame.values[0],
                frame.sourceOffset,
                sourceLength
            )
        );
    }

    if (idEquals(frame.id, "TPE1"))
    {
        auto values = frame.values.dup;

        auto field =
            MetadataField(
                MetadataKey("artist"),
                MetadataValue(
                    MetadataTextList(values)
                ),
                [
                    makeProvenance(
                        "TPE1",
                        frame.sourceOffset,
                        sourceLength
                    )
                ]
            );

        assertRegisteredShape(field);

        return Id3v24CanonicalTextMappingResult.success(
            field
        );
    }

    if (idEquals(frame.id, "TALB"))
    {
        if (frame.values.length != 1)
            return Id3v24CanonicalTextMappingResult.unrepresentable();

        return Id3v24CanonicalTextMappingResult.success(
            makeScalarTextField(
                "album",
                "TALB",
                frame.values[0],
                frame.sourceOffset,
                sourceLength
            )
        );
    }

    if (idEquals(frame.id, "TRCK"))
    {
        if (frame.values.length != 1)
            return Id3v24CanonicalTextMappingResult.unrepresentable();

        return mapPositionTextField(
            "track",
            "TRCK",
            frame.values[0],
            frame.sourceOffset,
            sourceLength
        );
    }

    if (idEquals(frame.id, "TPOS"))
    {
        if (frame.values.length != 1)
            return Id3v24CanonicalTextMappingResult.unrepresentable();

        return mapPositionTextField(
            "disc",
            "TPOS",
            frame.values[0],
            frame.sourceOffset,
            sourceLength
        );
    }

    if (idEquals(frame.id, "TCON"))
    {
        auto decoded =
            decodeId3v24Genres(
                frame.values
            );

        if (!decoded.representable)
        {
            return
                Id3v24CanonicalTextMappingResult
                    .unrepresentable();
        }

        return
            Id3v24CanonicalTextMappingResult
                .success(
                    makeTextListField(
                        "genre",
                        "TCON",
                        decoded.values,
                        frame.sourceOffset,
                        sourceLength
                    )
                );
    }

    if (idEquals(frame.id, "TDRC"))
    {
        if (frame.values.length == 0)
        {
            return
                Id3v24CanonicalTextMappingResult
                    .unrepresentable();
        }

        MetadataDateTime[] values;

        foreach (value; frame.values)
        {
            const parsed =
                parseId3v24Timestamp(
                    value
                );

            if (!parsed.parsed)
            {
                return
                    Id3v24CanonicalTextMappingResult
                        .unrepresentable();
            }

            values ~=
                toCanonicalDateTime(
                    parsed.value
                );
        }

        return
            Id3v24CanonicalTextMappingResult
                .success(
                    makeDateTimeListField(
                        "recordingDate",
                        "TDRC",
                        values,
                        frame.sourceOffset,
                        sourceLength
                    )
                );
    }

    return Id3v24CanonicalTextMappingResult.unsupported();
}


/++
Maps one unified native ID3v2.4 frame through the basic canonical
text mapper.

Only decoded ordinary text-information outcomes are mapped here.
Unknown frames, non-text native outcomes and transformation-pending
content remain successful native data but produce no canonical text
field.

Unlike the lower-level decoded-frame overload, this function has the
complete structural envelope and therefore records the exact physical
frame length in canonical provenance.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical text mapping result.
+/
Id3v24CanonicalTextMappingResult
mapId3v24NativeTextFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    const state =
        id3v24NativeFrameState(native);

    if (
        state ==
        Id3v24NativeFrameState.unknownSemanticFrame
    )
    {
        return
            Id3v24CanonicalTextMappingResult.unsupported();
    }

    if (state != Id3v24NativeFrameState.decoded)
    {
        return
            Id3v24CanonicalTextMappingResult
                .transformationRequired();
    }

    return native.content.match!(
        (Id3v24TextInformationOutcome outcome) =>
            mapId3v24TextInformationFrameToCanonical(
                outcome.text,
                native.sourceLength
            ),

        _ =>
            Id3v24CanonicalTextMappingResult.unsupported()
    );
}


/++
Tests a fixed ID3 frame identifier without allocating.
+/
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


/++
Constructs provenance for one mapped native frame.

The current native semantic frame exposes the frame's absolute source
offset but not a complete physical frame extent in the canonical
mapping API. A zero source length therefore deliberately identifies
the exact origin position without inventing a byte range.
+/
private MetadataProvenance makeProvenance(
    string nativeIdentifier,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return MetadataProvenance(
        NativeMetadataIdentifier(
            MetadataSystem.id3v2,
            nativeIdentifier
        ),
        sourceOffset,
        sourceLength,
        MetadataConfidence.exact
    );
}


/++
Constructs one scalar-text canonical field.
+/
private MetadataField makeScalarTextField(
    string canonicalKey,
    string nativeIdentifier,
    string value,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe
{
    auto field =
        MetadataField(
            MetadataKey(canonicalKey),
            MetadataValue(
                MetadataText(value)
            ),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ]
        );

    assertRegisteredShape(field);

    return field;
}


/++
Constructs one canonical ordered text-list field.
+/
private MetadataField
makeTextListField(
    string canonicalKey,
    string nativeIdentifier,
    string[] values,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe
{
    auto field =
        MetadataField(
            MetadataKey(
                canonicalKey
            ),
            MetadataValue(
                MetadataTextList(
                    values
                )
            ),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ]
        );

    assertRegisteredShape(
        field
    );

    return field;
}


/++
Converts one validated native ID3v2.4 timestamp to canonical components.

ID3v2.4 specifies every timestamp as UTC, including reduced-precision values.
No fractional second is produced because it is outside the v2.4 timestamp
grammar.
+/
private MetadataDateTime
toCanonicalDateTime(
    const Id3v24Timestamp timestamp
)
    @safe pure nothrow @nogc
{
    MetadataDateTime result;

    result.hasYear = true;
    result.year = timestamp.year;

    if (timestamp.hasMonth)
    {
        result.hasMonth = true;
        result.month = timestamp.month;
    }

    if (timestamp.hasDay)
    {
        result.hasDay = true;
        result.day = timestamp.day;
    }

    if (timestamp.hasHour)
    {
        result.hasHour = true;
        result.hour = timestamp.hour;
    }

    if (timestamp.hasMinute)
    {
        result.hasMinute = true;
        result.minute = timestamp.minute;
    }

    if (timestamp.hasSecond)
    {
        result.hasSecond = true;
        result.second = timestamp.second;
    }

    result.hasUtcOffset = true;
    result.utcOffsetMinutes = 0;

    return result;
}


/++
Constructs one canonical ordered date/time-list field.
+/
private MetadataField
makeDateTimeListField(
    string canonicalKey,
    string nativeIdentifier,
    MetadataDateTime[] values,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe
{
    auto field =
        MetadataField(
            MetadataKey(
                canonicalKey
            ),
            MetadataValue(
                MetadataDateTimeList(
                    values
                )
            ),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ]
        );

    assertRegisteredShape(
        field
    );

    return field;
}


/++
Parses and constructs one canonical track/disc position field.

Invalid native position text remains preserved native metadata but is not
silently normalized into invented canonical semantics.
+/
private Id3v24CanonicalTextMappingResult
mapPositionTextField(
    string canonicalKey,
    string nativeIdentifier,
    string value,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe
{
    const parsed = parseId3v2Position(value);

    if (!parsed.parsed)
    {
        return Id3v24CanonicalTextMappingResult
            .unrepresentable();
    }

    MetadataPosition position =
        parsed.value.hasTotal
            ? MetadataPosition.numberAndTotal(
                parsed.value.number,
                parsed.value.total
            )
            : MetadataPosition.numberOnly(
                parsed.value.number
            );

    auto field =
        MetadataField(
            MetadataKey(canonicalKey),
            MetadataValue(position),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ]
        );

    assertRegisteredShape(field);

    return Id3v24CanonicalTextMappingResult
        .success(field);
}


/++
Checks the mapper/registry contract as a programmer invariant.
+/
private void assertRegisteredShape(
    MetadataField field
)
    @safe
{
    auto definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);
    assert(definition.definition.accepts(field.value));
}


/++
Creates a decoded text-information frame for mapping tests.
+/
private Id3v24TextInformationFrame testFrame(
    string id,
    string[] values,
    size_t sourceOffset = 100
)
    @safe
{
    assert(id.length == 4);

    Id3v24TextInformationFrame frame;

    frame.id[] = id[];
    frame.values = values;
    frame.sourceOffset = sourceOffset;

    return frame;
}


/// TIT2 maps to the canonical scalar title field.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TIT2",
                ["Example title"],
                123
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "title");
    assert(result.field.provenance.length == 1);

    assert(
        result.field.provenance[0].native.identifier ==
        "TIT2"
    );

    assert(
        result.field.provenance[0].sourceOffset ==
        123
    );

    assert(
        result.field.provenance[0].sourceLength ==
        0
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "Example title",
            _ => false
        );

    assert(matches);
}


/// TPE1 preserves ordered multiple artist values.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                ["Artist A", "Artist B"]
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "artist");

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["Artist A", "Artist B"],
            _ => false
        );

    assert(matches);
}


/// TALB maps to the canonical scalar album field.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TALB",
                ["Example album"]
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "album");

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "Example album",
            _ => false
        );

    assert(matches);
}


/// Multiple TIT2 values are not silently collapsed.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TIT2",
                ["First title", "Second title"]
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalTextMappingStatus
            .unrepresentableValueShape
    );
}


/// Multiple TALB values are likewise preserved as an explicit limitation.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TALB",
                ["Album A", "Album B"]
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalTextMappingStatus
            .unrepresentableValueShape
    );
}


/// Native-frame mapping records the complete physical frame extent.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'T', 'i', 't', 'l', 'e'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeTextFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);
    assert(mapped.field.provenance.length == 1);

    assert(
        mapped.field.provenance[0].sourceOffset ==
        700
    );

    assert(
        mapped.field.provenance[0].sourceLength ==
        bytes.length
    );
}


/// Transformation-pending native text is not treated as malformed.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeTextFrameToCanonical(
            native.value
        );

    assert(!mapped.mapped);

    assert(
        mapped.status ==
        Id3v24CanonicalTextMappingStatus
            .requiresTransformation
    );
}


/// Unknown native frames remain unsupported rather than erroneous.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'G', 'E', 'O', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeTextFrameToCanonical(
            native.value
        );

    assert(!mapped.mapped);

    assert(
        mapped.status ==
        Id3v24CanonicalTextMappingStatus
            .unsupportedFrame
    );
}


/// TRCK maps number/total to canonical track position.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame("TRCK", ["004/009"], 1500),
            19
        );

    assert(result.mapped);
    assert(result.field.key.name == "track");

    assert(
        result.field.value.match!(
            (MetadataPosition position) =>
                position.hasNumber &&
                position.number == 4 &&
                position.hasTotal &&
                position.total == 9,
            _ => false
        )
    );

    assert(
        result.field.provenance[0].native.identifier ==
        "TRCK"
    );
    assert(result.field.provenance[0].sourceOffset == 1500);
    assert(result.field.provenance[0].sourceLength == 19);
}


/// TPOS maps number-only text to canonical disc position.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame("TPOS", ["2"])
        );

    assert(result.mapped);
    assert(result.field.key.name == "disc");

    assert(
        result.field.value.match!(
            (MetadataPosition position) =>
                position.hasNumber &&
                position.number == 2 &&
                !position.hasTotal,
            _ => false
        )
    );
}


/// Invalid and multi-valued ID3v2.4 positions remain native-only.
unittest
{
    foreach (
        values;
        [
            [""],
            ["/9"],
            ["4/"],
            ["4//9"],
            [" 4"],
            ["18446744073709551616"],
            ["1", "2"]
        ]
    )
    {
        auto result =
            mapId3v24TextInformationFrameToCanonical(
                testFrame("TRCK", values)
            );

        assert(!result.mapped);
        assert(
            result.status ==
            Id3v24CanonicalTextMappingStatus
                .unrepresentableValueShape
        );
    }
}


/// TCON maps ordered v2.4 numeric, free-text and keyword values.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TCON",
                [
                    "17",
                    "Ambient",
                    "RX",
                    "CR"
                ],
                1700
            ),
            32
        );

    assert(result.mapped);
    assert(result.field.key.name == "genre");

    assert(
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "Rock",
                    "Ambient",
                    "Remix",
                    "Cover"
                ],
            _ => false
        )
    );

    assert(
        result.field.provenance[0].native.identifier ==
        "TCON"
    );
    assert(result.field.provenance[0].sourceOffset == 1700);
    assert(result.field.provenance[0].sourceLength == 32);
}


/// Free-text ID3v2.4 genres preserve native order and spelling.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TCON",
                [
                    "Electronic",
                    "Ambient"
                ]
            )
        );

    assert(result.mapped);

    assert(
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "Electronic",
                    "Ambient"
                ],
            _ => false
        )
    );
}


/// Unknown explicit ID3v2.4 numeric genre references remain native-only.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TCON",
                ["255"]
            )
        );

    assert(!result.mapped);
    assert(
        result.status ==
        Id3v24CanonicalTextMappingStatus
            .unrepresentableValueShape
    );
}


/// TDRC maps reduced-precision UTC timestamps in native order.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TDRC",
                [
                    "1999",
                    "2001-06-12T23:45:01"
                ],
                1800
            ),
            41
        );

    assert(result.mapped);
    assert(result.field.key.name == "recordingDate");

    assert(
        result.field.value.match!(
            (MetadataDateTimeList list)
            {
                if (list.values.length != 2)
                    return false;

                const first = list.values[0];

                if (
                    !first.hasYear ||
                    first.year != 1999 ||
                    first.hasMonth ||
                    first.hasTime ||
                    !first.hasUtcOffset ||
                    first.utcOffsetMinutes != 0
                )
                {
                    return false;
                }

                const second = list.values[1];

                return
                    second.hasYear &&
                    second.year == 2001 &&
                    second.hasMonth &&
                    second.month == 6 &&
                    second.hasDay &&
                    second.day == 12 &&
                    second.hasHour &&
                    second.hour == 23 &&
                    second.hasMinute &&
                    second.minute == 45 &&
                    second.hasSecond &&
                    second.second == 1 &&
                    !second.hasFractionalSecond &&
                    second.hasUtcOffset &&
                    second.utcOffsetMinutes == 0;
            },

            _ => false
        )
    );

    assert(
        result.field.provenance[0].native.identifier ==
        "TDRC"
    );

    assert(result.field.provenance[0].sourceOffset == 1800);
    assert(result.field.provenance[0].sourceLength == 41);
}


/// Invalid TDRC timestamp syntax remains valid native-only metadata.
unittest
{
    foreach (
        values;
        [
            [""],
            ["1999-13"],
            ["1999-02-29"],
            ["1999-01-01T24:00"],
            ["1999-01-01T12:00Z"],
            ["1999-01-01T12:00:00.1"],
            ["1999", "not-a-date"]
        ]
    )
    {
        auto result =
            mapId3v24TextInformationFrameToCanonical(
                testFrame(
                    "TDRC",
                    values
                )
            );

        assert(!result.mapped);

        assert(
            result.status ==
            Id3v24CanonicalTextMappingStatus
                .unrepresentableValueShape
        );
    }
}


/// An empty native TDRC value list is not invented as an empty date field.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TDRC",
                []
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalTextMappingStatus
            .unrepresentableValueShape
    );
}


/// Other text-information frames remain unsupported by this mapper.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TBPM",
                ["120"]
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalTextMappingStatus
            .unsupportedFrame
    );
}
