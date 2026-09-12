/++
Mapping of decoded ID3v2.2 text-information frames to canonical metadata.

This module maps only semantics that are complete within one native frame:

- TT2 -> title
- TP1 -> artist
- TAL -> album
- TRK -> track
- TPA -> disc
- TCO -> genre

The legacy recording-time components TYE, TDA and TIM are intentionally not
mapped here. Their canonical `recordingDate` value depends on sequence-level
aggregation and is handled by a later dedicated mapper.

ID3v2.2 native frames remain unchanged. Canonical fields carry exact
provenance pointing back to the complete physical frame when the unified native
frame overload is used.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.canonical_text;

import std.sumtype :
    match;

import audiotag.id3v2.common.genre :
    decodeId3v22Genre;

import audiotag.id3v2.common.position :
    parseId3v2Position;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

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
    MetadataPosition,
    MetadataText,
    MetadataTextList,
    MetadataValue;


/++
Text-mapper name for the shared ID3v2.2 canonical mapping status.
+/
alias Id3v22CanonicalTextMappingStatus =
    Id3v22CanonicalMappingStatus;


/++
Text-mapper name for the shared ID3v2.2 canonical mapping result.
+/
alias Id3v22CanonicalTextMappingResult =
    Id3v22CanonicalMappingResult;


/++
Maps one decoded ID3v2.2 text-information frame to canonical metadata.

ID3v2.2 ordinary text frames contain one native information string.

`TP1` defines `/` as the separator between lead artists/performers. Empty
components are retained exactly rather than silently normalized.

`TRK` and `TPA` use the shared ID3v2 position parser.

`TCO` uses the ID3v2.2 legacy content-type grammar: ID3v1 numeric references,
multiple parenthesized references, `RX`/`CR`, and optional free-text
refinement.

`TYE`, `TDA` and `TIM` remain unsupported here because they form one compound
recording-time semantic value at sequence level.
+/
Id3v22CanonicalTextMappingResult
mapId3v22TextInformationFrameToCanonical(
    Id3v22TextInformationFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    if (idEquals(frame.id, "TT2"))
    {
        return Id3v22CanonicalTextMappingResult.success(
            makeScalarTextField(
                "title",
                "TT2",
                frame.value,
                frame.sourceOffset,
                sourceLength
            )
        );
    }

    if (idEquals(frame.id, "TP1"))
    {
        auto values = splitSlashList(frame.value);

        auto field =
            MetadataField(
                MetadataKey("artist"),
                MetadataValue(
                    MetadataTextList(values)
                ),
                [
                    makeProvenance(
                        "TP1",
                        frame.sourceOffset,
                        sourceLength
                    )
                ]
            );

        assertRegisteredShape(field);

        return Id3v22CanonicalTextMappingResult.success(
            field
        );
    }

    if (idEquals(frame.id, "TAL"))
    {
        return Id3v22CanonicalTextMappingResult.success(
            makeScalarTextField(
                "album",
                "TAL",
                frame.value,
                frame.sourceOffset,
                sourceLength
            )
        );
    }

    if (idEquals(frame.id, "TRK"))
    {
        return mapPositionTextField(
            "track",
            "TRK",
            frame.value,
            frame.sourceOffset,
            sourceLength
        );
    }

    if (idEquals(frame.id, "TPA"))
    {
        return mapPositionTextField(
            "disc",
            "TPA",
            frame.value,
            frame.sourceOffset,
            sourceLength
        );
    }

    if (idEquals(frame.id, "TCO"))
    {
        auto decoded = decodeId3v22Genre(frame.value);

        if (!decoded.representable)
        {
            return Id3v22CanonicalTextMappingResult
                .unrepresentable();
        }

        return Id3v22CanonicalTextMappingResult.success(
            makeTextListField(
                "genre",
                "TCO",
                decoded.values,
                frame.sourceOffset,
                sourceLength
            )
        );
    }

    return Id3v22CanonicalTextMappingResult.unsupported();
}


/++
Maps one unified native ID3v2.2 frame through the canonical text mapper.

Only ordinary decoded text-information native alternatives are mapped here.
Other native frame families and unknown frames remain valid native metadata but
are unsupported by this mapper.

Unlike the lower-level decoded-frame overload, this function has the complete
structural envelope and therefore records the exact physical frame length in
canonical provenance.
+/
Id3v22CanonicalTextMappingResult
mapId3v22NativeTextFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v22TextInformationFrame frame) =>
            mapId3v22TextInformationFrameToCanonical(
                frame,
                native.sourceLength
            ),

        _ =>
            Id3v22CanonicalTextMappingResult.unsupported()
    );
}


private string[]
splitSlashList(
    string value
)
    @safe
{
    string[] values;
    size_t start;

    for (
        size_t index = 0;
        index < value.length;
        ++index
    )
    {
        if (value[index] != '/')
            continue;

        values ~= value[start .. index];
        start = index + 1;
    }

    values ~= value[start .. value.length];

    return values;
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


private MetadataProvenance
makeProvenance(
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


private MetadataField
makeScalarTextField(
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
            MetadataKey(canonicalKey),
            MetadataValue(
                MetadataTextList(values)
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


private Id3v22CanonicalTextMappingResult
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
        return Id3v22CanonicalTextMappingResult
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

    return Id3v22CanonicalTextMappingResult.success(
        field
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

    assert(definition.found);
    assert(
        definition.definition.accepts(
            field.value
        )
    );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        decodeId3v22NativeFrame;

    import audiotag.id3v2.v22.text_encoding :
        Id3v22TextEncoding;


    private Id3v22TextInformationFrame
    testFrame(
        string id,
        string value,
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(id.length == 3);

        Id3v22TextInformationFrame frame;

        frame.sourceOffset = sourceOffset;
        frame.id[] = id[];
        frame.encoding = Id3v22TextEncoding.latin1;
        frame.value = value;

        return frame;
    }
}


/// TT2 maps to canonical scalar title.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TT2",
                "Example title",
                123
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "title");
    assert(result.field.provenance.length == 1);
    assert(
        result.field.provenance[0]
            .native.identifier ==
        "TT2"
    );
    assert(
        result.field.provenance[0]
            .sourceOffset ==
        123
    );
    assert(
        result.field.provenance[0]
            .sourceLength ==
        0
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "Example title",

            _ =>
                false
        );

    assert(matches);
}


/// TP1 slash-separated artists become an ordered canonical list.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TP1",
                "Artist A/Artist B"
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "artist");

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "Artist A",
                    "Artist B"
                ],

            _ =>
                false
        );

    assert(matches);
}


/// TP1 preserves empty list components exactly.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TP1",
                "/A//B/"
            )
        );

    assert(result.mapped);

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "",
                    "A",
                    "",
                    "B",
                    ""
                ],

            _ =>
                false
        );

    assert(matches);
}


/// TAL maps to canonical scalar album.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TAL",
                "Example album"
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "album");

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "Example album",

            _ =>
                false
        );

    assert(matches);
}


/// TRK maps number and optional total to canonical track position.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TRK",
                "04/09"
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "track");

    const matches =
        result.field.value.match!(
            (MetadataPosition position) =>
                position.hasNumber &&
                position.number == 4 &&
                position.hasTotal &&
                position.total == 9,

            _ =>
                false
        );

    assert(matches);
}


/// TPA maps a number-only value to canonical disc position.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TPA",
                "2"
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "disc");

    const matches =
        result.field.value.match!(
            (MetadataPosition position) =>
                position.hasNumber &&
                position.number == 2 &&
                !position.hasTotal,

            _ =>
                false
        );

    assert(matches);
}


/// Invalid position syntax remains native but is not canonically invented.
unittest
{
    foreach (
        id;
        [
            "TRK",
            "TPA"
        ]
    )
    {
        auto result =
            mapId3v22TextInformationFrameToCanonical(
                testFrame(
                    id,
                    "not-a-position"
                )
            );

        assert(!result.mapped);
        assert(
            result.status ==
            Id3v22CanonicalMappingStatus
                .unrepresentableValueShape
        );
    }
}


/// TCO resolves legacy references and keeps free-text refinement order.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TCO",
                "(4)Eurodisco"
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "genre");

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "Disco",
                    "Eurodisco"
                ],

            _ =>
                false
        );

    assert(matches);
}


/// Unknown explicit TCO references remain unrepresentable.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TCO",
                "(255)"
            )
        );

    assert(!result.mapped);
    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unrepresentableValueShape
    );
}


/// Legacy recording-time components are deferred to sequence aggregation.
unittest
{
    foreach (
        id;
        [
            "TYE",
            "TDA",
            "TIM"
        ]
    )
    {
        auto result =
            mapId3v22TextInformationFrameToCanonical(
                testFrame(
                    id,
                    "1999"
                )
            );

        assert(!result.mapped);
        assert(
            result.status ==
            Id3v22CanonicalMappingStatus
                .unsupportedFrame
        );
    }
}


/// Other valid text-information frames remain unsupported, not malformed.
unittest
{
    auto result =
        mapId3v22TextInformationFrameToCanonical(
            testFrame(
                "TCM",
                "Composer"
            )
        );

    assert(!result.mapped);
    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}


/// Unified native mapping records the complete physical frame length.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x02,

            0x00,
            'X'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto envelope =
        cursor.parseId3v22FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto result =
        mapId3v22NativeTextFrameToCanonical(
            native.value
        );

    assert(result.mapped);
    assert(
        result.field.provenance[0]
            .sourceOffset ==
        900
    );
    assert(
        result.field.provenance[0]
            .sourceLength ==
        8
    );
}
