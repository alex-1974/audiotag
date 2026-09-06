/++
Mapping of decoded ID3v2.3 text-information frames to canonical
metadata fields.

This module is the version-specific semantic bridge between the native
ID3v2.3 text layer and the format-independent canonical metadata model.

The currently explicit mappings are:

- TIT2 -> title
- TPE1 -> artist
- TALB -> album

ID3v2.3 stores one native information string in an ordinary text frame.
For TPE1, the ID3v2.3 specification defines "/" as the separator between
multiple lead artists/performers. That version-specific interpretation
belongs here rather than in the low-level text decoder.

Valid native metadata without a current canonical mapping remains
explicitly unsupported rather than being discarded or treated as
malformed.
+/
module audiotag.id3v2.v23.canonical_text;

import std.sumtype :
    match;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult,
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

import audiotag.id3v2.v23.native_state :
    Id3v23NativeFrameState,
    id3v23NativeFrameState;

import audiotag.id3v2.v23.text_information :
    Id3v23TextInformationFrame,
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
    MetadataText,
    MetadataTextList,
    MetadataValue;


/++
Text-mapper alias for the common ID3v2.3 canonical mapping status.
+/
alias Id3v23CanonicalTextMappingStatus =
    Id3v23CanonicalMappingStatus;


/++
Text-mapper alias for the common ID3v2.3 canonical mapping result.
+/
alias Id3v23CanonicalTextMappingResult =
    Id3v23CanonicalMappingResult;


/++
Maps one decoded ID3v2.3 text-information frame to canonical metadata.

ID3v2.3 ordinary text frames contain one native information string.
TIT2 and TALB map that string directly to scalar canonical text.

TPE1 is version-specific: its native string is interpreted as an
ordered "/"-separated list. Empty components are retained exactly so
that canonicalization does not silently normalize valid native text.

Params:
    frame = Decoded native ID3v2.3 text-information frame.
    sourceLength = Complete physical native frame length when known.
        Zero means point provenance only.

Returns:
    A mapped canonical field, unsupported-frame result, or explicit
    representability limitation.
+/
Id3v23CanonicalTextMappingResult
mapId3v23TextInformationFrameToCanonical(
    Id3v23TextInformationFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    if (
        idEquals(
            frame.id,
            "TIT2"
        )
    )
    {
        return
            Id3v23CanonicalTextMappingResult
                .success(
                    makeScalarTextField(
                        "title",
                        "TIT2",
                        frame.value,
                        frame.sourceOffset,
                        sourceLength
                    )
                );
    }


    if (
        idEquals(
            frame.id,
            "TPE1"
        )
    )
    {
        auto values =
            splitId3v23SlashList(
                frame.value
            );

        auto field =
            MetadataField(
                MetadataKey(
                    "artist"
                ),
                MetadataValue(
                    MetadataTextList(
                        values
                    )
                ),
                [
                    makeProvenance(
                        "TPE1",
                        frame.sourceOffset,
                        sourceLength
                    )
                ]
            );

        assertRegisteredShape(
            field
        );

        return
            Id3v23CanonicalTextMappingResult
                .success(
                    field
                );
    }


    if (
        idEquals(
            frame.id,
            "TALB"
        )
    )
    {
        return
            Id3v23CanonicalTextMappingResult
                .success(
                    makeScalarTextField(
                        "album",
                        "TALB",
                        frame.value,
                        frame.sourceOffset,
                        sourceLength
                    )
                );
    }


    return
        Id3v23CanonicalTextMappingResult
            .unsupported();
}


/++
Maps one unified native ID3v2.3 frame through the canonical text mapper.

Only decoded ordinary text-information outcomes are mapped here.

Unknown semantic frames and other native frame families remain
unsupported. Transformation-pending text information remains valid
native metadata and produces `requiresTransformation`.

The complete native frame is available here, so exact physical frame
length is included in canonical provenance.
+/
Id3v23CanonicalTextMappingResult
mapId3v23NativeTextFrameToCanonical(
    Id3v23NativeFrame native
)
    @safe
{
    const state =
        id3v23NativeFrameState(
            native
        );


    if (
        state ==
        Id3v23NativeFrameState
            .unknownSemanticFrame
    )
    {
        return
            Id3v23CanonicalTextMappingResult
                .unsupported();
    }


    if (
        state !=
        Id3v23NativeFrameState.decoded
    )
    {
        return
            Id3v23CanonicalTextMappingResult
                .transformationRequired();
    }


    return
        native.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                mapId3v23TextInformationFrameToCanonical(
                    outcome.text,
                    native.sourceLength
                ),

            _ =>
                Id3v23CanonicalTextMappingResult
                    .unsupported()
        );
}


/++
Splits one ID3v2.3 slash-separated semantic list.

Every separator creates a component. Empty components are retained,
including leading, trailing and adjacent empty values:

    ""      -> [""]
    "A/B"   -> ["A", "B"]
    "A//B"  -> ["A", "", "B"]
    "/A"    -> ["", "A"]
    "A/"    -> ["A", ""]

The native frame itself remains unchanged and continues to preserve the
original unsplit string.
+/
private string[]
splitId3v23SlashList(
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
        if (
            value[index] != '/'
        )
        {
            continue;
        }


        values ~=
            value[
                start ..
                index
            ];

        start =
            index + 1;
    }


    values ~=
        value[
            start ..
            value.length
        ];


    return values;
}


/++
Tests a fixed four-character native frame identifier without allocating.
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
Constructs exact canonical provenance for one mapped native frame.
+/
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


/++
Constructs one scalar canonical text field.
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
            MetadataKey(
                canonicalKey
            ),
            MetadataValue(
                MetadataText(
                    value
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
Checks the mapper/registry contract as a programmer invariant.
+/
private void assertRegisteredShape(
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
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope,
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame,
        decodeId3v23NativeFrame;

    import audiotag.id3v2.v23.text_information :
        Id3v23TextInformationAvailability;


    /++
    Creates one decoded synthetic text-information frame.
    +/
    private Id3v23TextInformationFrame testFrame(
        string id,
        string value,
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(
            id.length ==
            4
        );

        Id3v23TextInformationFrame frame;

        frame.id[] =
            id[];

        frame.value =
            value;

        frame.sourceOffset =
            sourceOffset;

        return frame;
    }
}


/// TIT2 maps to canonical scalar title.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TIT2",
                "Example title",
                123
            )
        );

    assert(
        result.mapped
    );

    assert(
        result.field.key.name ==
        "title"
    );

    assert(
        result.field.provenance.length ==
        1
    );

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "TIT2"
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
                text.value ==
                "Example title",

            _ =>
                false
        );

    assert(
        matches
    );
}


/// TALB maps to canonical scalar album.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TALB",
                "Example album"
            )
        );

    assert(
        result.mapped
    );

    assert(
        result.field.key.name ==
        "album"
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value ==
                "Example album",

            _ =>
                false
        );

    assert(
        matches
    );
}


/// A single TPE1 artist remains a one-element canonical artist list.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                "Artist A"
            )
        );

    assert(
        result.mapped
    );

    assert(
        result.field.key.name ==
        "artist"
    );

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["Artist A"],

            _ =>
                false
        );

    assert(
        matches
    );
}


/// ID3v2.3 TPE1 slash-separated performers become an ordered list.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                "Artist A/Artist B/Artist C"
            )
        );

    assert(
        result.mapped
    );

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "Artist A",
                    "Artist B",
                    "Artist C"
                ],

            _ =>
                false
        );

    assert(
        matches
    );
}


/// Empty slash-list components are preserved rather than normalized away.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                "A//B"
            )
        );

    assert(
        result.mapped
    );

    const matches =
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [
                    "A",
                    "",
                    "B"
                ],

            _ =>
                false
        );

    assert(
        matches
    );
}


/// Leading and trailing empty TPE1 components remain explicit.
unittest
{
    auto leading =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                "/A"
            )
        );

    assert(
        leading.mapped
    );

    assert(
        leading.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["", "A"],

            _ =>
                false
        )
    );


    auto trailing =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                "A/"
            )
        );

    assert(
        trailing.mapped
    );

    assert(
        trailing.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["A", ""],

            _ =>
                false
        )
    );
}


/// An empty native TPE1 remains one explicit empty artist value.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TPE1",
                ""
            )
        );

    assert(
        result.mapped
    );

    assert(
        result.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                [""],

            _ =>
                false
        )
    );
}


/// Native-frame mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            /*
             * Latin-1 encoding + "Title".
             */
            0x00,
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
        cursor.parseId3v23FrameEnvelope();

    assert(
        envelope.hasValue
    );

    assert(
        cursor.empty
    );


    auto native =
        decodeId3v23NativeFrame(
            envelope.value
        );

    assert(
        native.hasValue
    );


    auto mapped =
        mapId3v23NativeTextFrameToCanonical(
            native.value
        );

    assert(
        mapped.mapped
    );

    assert(
        mapped.field.provenance.length ==
        1
    );

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        700
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );
}


/// Native TPE1 decoding keeps the unsplit value while canonical mapping splits it.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            'A', '/', 'B'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto envelope =
        cursor.parseId3v23FrameEnvelope();

    assert(
        envelope.hasValue
    );


    auto native =
        decodeId3v23NativeFrame(
            envelope.value
        );

    assert(
        native.hasValue
    );


    const nativeUnsplit =
        native.value.content.match!(
            (Id3v23TextInformationOutcome outcome) =>
                outcome.text.value ==
                "A/B",

            _ =>
                false
        );

    assert(
        nativeUnsplit
    );


    auto mapped =
        mapId3v23NativeTextFrameToCanonical(
            native.value
        );

    assert(
        mapped.mapped
    );

    assert(
        mapped.field.value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["A", "B"],

            _ =>
                false
        )
    );
}


/// Transformation-pending native text is not treated as malformed.
unittest
{
    Id3v23TextInformationOutcome outcome;

    outcome.availability =
        Id3v23TextInformationAvailability
            .requiresDecompression;

    Id3v23NativeFrameContent content =
        outcome;

    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v23NativeTextFrameToCanonical(
            native
        );

    assert(
        !result.mapped
    );

    assert(
        result.status ==
        Id3v23CanonicalTextMappingStatus
            .requiresTransformation
    );
}


/// Unknown native frames remain unsupported rather than erroneous.
unittest
{
    Id3v23NativeFrameContent content =
        Id3v23UnknownFrame();

    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v23NativeTextFrameToCanonical(
            native
        );

    assert(
        !result.mapped
    );

    assert(
        result.status ==
        Id3v23CanonicalTextMappingStatus
            .unsupportedFrame
    );
}


/// Other decoded text-information frames remain unsupported for now.
unittest
{
    auto result =
        mapId3v23TextInformationFrameToCanonical(
            testFrame(
                "TCON",
                "Rock"
            )
        );

    assert(
        !result.mapped
    );

    assert(
        result.status ==
        Id3v23CanonicalTextMappingStatus
            .unsupportedFrame
    );
}
