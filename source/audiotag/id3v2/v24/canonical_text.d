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

Valid native metadata that cannot yet be represented without loss is
reported as such rather than being classified as malformed input.
+/
module audiotag.id3v2.v24.canonical_text;

import std.sumtype :
    match;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.id3v2.v24.native_state :
    Id3v24NativeFrameState,
    id3v24NativeFrameState;

import audiotag.id3v2.v24.text_information :
    Id3v24TextInformationFrame,
    Id3v24TextInformationOutcome;

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
Outcome of mapping one decoded ID3v2.4 text-information frame.
+/
enum Id3v24CanonicalTextMappingStatus : ubyte
{
    /// A canonical field was produced.
    mapped,

    /// This native frame identifier/content has no mapping in this module.
    unsupportedFrame,

    /// Semantic content exists but requires a transformation that is not
    /// currently available.
    requiresTransformation,

    /// The native value is valid but the current canonical field shape
    /// cannot represent it without loss.
    unrepresentableValueShape
}


/++
Result of mapping one decoded ID3v2.4 text-information frame.
+/
struct Id3v24CanonicalTextMappingResult
{
    /// Mapping outcome.
    Id3v24CanonicalTextMappingStatus status;

    /// Canonical field when `status == mapped`.
    MetadataField field;

    /++
    Returns whether a canonical field was produced.
    +/
    @property
    bool mapped() const
        @safe pure nothrow @nogc
    {
        return status ==
            Id3v24CanonicalTextMappingStatus.mapped;
    }

    /++
    Constructs a successful mapping result.
    +/
    static Id3v24CanonicalTextMappingResult success(
        MetadataField field
    )
        @safe
    {
        return Id3v24CanonicalTextMappingResult(
            Id3v24CanonicalTextMappingStatus.mapped,
            field
        );
    }

    /++
    Constructs a result for an unsupported native frame identifier.
    +/
    static Id3v24CanonicalTextMappingResult unsupported()
        @safe pure nothrow @nogc
    {
        return Id3v24CanonicalTextMappingResult(
            Id3v24CanonicalTextMappingStatus.unsupportedFrame,
            MetadataField.init
        );
    }

    /++
    Constructs a result for semantic content that requires a currently
    unavailable transformation.
    +/
    static Id3v24CanonicalTextMappingResult
    transformationRequired()
        @safe pure nothrow @nogc
    {
        return Id3v24CanonicalTextMappingResult(
            Id3v24CanonicalTextMappingStatus.requiresTransformation,
            MetadataField.init
        );
    }

    /++
    Constructs a result for a valid native value whose shape cannot
    yet be represented losslessly by the canonical registry.
    +/
    static Id3v24CanonicalTextMappingResult
    unrepresentable()
        @safe pure nothrow @nogc
    {
        return Id3v24CanonicalTextMappingResult(
            Id3v24CanonicalTextMappingStatus.unrepresentableValueShape,
            MetadataField.init
        );
    }
}


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


/// Other text-information frames remain unsupported by this mapper.
unittest
{
    auto result =
        mapId3v24TextInformationFrameToCanonical(
            testFrame(
                "TCON",
                ["Rock"]
            )
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalTextMappingStatus
            .unsupportedFrame
    );
}
