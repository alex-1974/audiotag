/++
Complete serialization of canonical ID3v2.4 unique-file-identifier
(`UFID`) frames.

Canonical UFID metadata consists of:

- one `MetadataBinary` identifier value;
- exactly one non-empty `owner` qualifier;
- no canonical media type, language or description.

The semantic payload is delegated to
`unique_file_identifier_write`.

New frames use zero status and format flags.

Regenerated existing frames follow the common mapped-frame policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported;
- frame-level unsynchronisation is removed;
- DLI presence is preserved and recomputed from the regenerated
  semantic UFID payload.
+/
module audiotag.id3v2.v24.unique_file_identifier_frame_write;

import std.sumtype :
    match;

import audiotag.core.numeric :
    encodeSynchsafe32;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataBinary;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;

import audiotag.id3v2.v24.frame_header_write :
    serializeId3v24FrameHeader;

import audiotag.id3v2.v24.new_frame_plan :
    planId3v24CanonicalField;

import audiotag.id3v2.v24.regeneration_policy :
    Id3v24MappedFrameRegenerationFormatPlan;

import audiotag.id3v2.v24.unique_file_identifier_write :
    serializeId3v24UniqueFileIdentifierPayload;


/++
Serializes the semantic UFID payload represented by one canonical
field.

The public frame writers consult the canonical planner first. This
helper also validates the expected field shape defensively.
+/
private SerializationResult!(ubyte[])
serializeCanonicalUniqueFileIdentifierPayload(
    ref const(MetadataField) field
)
    @safe
{
    if (
        field.qualifiers.length != 1 ||
        field.qualifiers[0].name != "owner"
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    return field.value.match!(
        (const(MetadataBinary) binary)
        {
            /*
             * UFID has no native media-type field.
             */
            if (binary.mediaType.length != 0)
            {
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .unsupportedRepresentation
                            )
                        );
            }

            return
                serializeId3v24UniqueFileIdentifierPayload(
                    field.qualifiers[0].value,
                    binary.data
                );
        },

        _ =>
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                )
    );
}


/++
Serializes one newly introduced canonical unique-file-identifier field
as a complete ID3v2.4 `UFID` frame.

New native frames use:

    statusFlags = 0
    formatFlags = 0
+/
SerializationResult!(ubyte[])
serializeNewId3v24UniqueFileIdentifierFrame(
    ref const(MetadataField) field
)
    @safe
{
    const plan =
        planId3v24CanonicalField(
            field
        );

    if (!plan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        0,
                        cast(ulong) plan.status
                    )
                );
    }

    if (
        plan.target.family !=
        Id3v24CanonicalTargetFamily
            .uniqueFileIdentifier
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    auto payload =
        serializeCanonicalUniqueFileIdentifierPayload(
            field
        );

    if (payload.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    payload.error
                );
    }

    assert(
        plan.target.frameId ==
        "UFID"
    );

    /*
     * At minimum:
     *
     * non-empty owner 1
     * terminator       1
     */
    assert(payload.value.length >= 2);

    assert(
        payload.value.length <=
        0x0FFF_FFFF
    );

    Id3v24FrameHeader header;

    foreach (index; 0 .. 4)
    {
        header.id[index] =
            plan.target.frameId[index];
    }

    header.size =
        cast(uint)
            payload.value.length;

    header.statusFlags = 0;
    header.formatFlags = 0;

    auto encodedHeader =
        serializeId3v24FrameHeader(
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
            payload.value.length
        ];

    output[
        0 ..
        encodedHeader.value.length
    ] =
        encodedHeader.value[];

    output[
        encodedHeader.value.length ..
        $
    ] =
        payload.value[];

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/++
Serializes modified canonical unique-file-identifier metadata as a
regenerated existing ID3v2.4 `UFID` frame.

When a DLI is retained, its value is the length of the semantic UFID
payload only. Grouping and DLI prefix bytes contribute to physical
frame size but not to the DLI value.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24UniqueFileIdentifierFrame(
    ref const(MetadataField) field,
    const(Id3v24MappedFrameRegenerationFormatPlan) formatPlan
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
                        cast(ulong) formatPlan.status
                    )
                );
    }

    if (
        (
            formatPlan.statusFlags &
            0x9F
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
                        0x60
                    )
                );
    }

    if (
        (
            formatPlan.formatFlags &
            0xBE
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
                        0x41
                    )
                );
    }

    const groupingFlag =
        (
            formatPlan.formatFlags &
            0x40
        ) != 0;

    const dliFlag =
        (
            formatPlan.formatFlags &
            0x01
        ) != 0;

    if (
        groupingFlag !=
        formatPlan.hasGroupingIdentity
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        9,
                        formatPlan.formatFlags
                    )
                );
    }

    if (
        dliFlag !=
        formatPlan.hasDataLengthIndicator
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .inconsistentStructure,
                        9,
                        formatPlan.formatFlags
                    )
                );
    }

    const canonicalPlan =
        planId3v24CanonicalField(
            field
        );

    if (!canonicalPlan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        0,
                        cast(ulong) canonicalPlan.status
                    )
                );
    }

    if (
        canonicalPlan.target.family !=
        Id3v24CanonicalTargetFamily
            .uniqueFileIdentifier
    )
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation
                    )
                );
    }

    auto payload =
        serializeCanonicalUniqueFileIdentifierPayload(
            field
        );

    if (payload.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    payload.error
                );
    }

    assert(
        canonicalPlan.target.frameId ==
        "UFID"
    );

    assert(payload.value.length >= 2);

    enum size_t maximumFrameDataSize =
        0x0FFF_FFFF;

    size_t prefixLength;

    if (formatPlan.hasGroupingIdentity)
        ++prefixLength;

    if (formatPlan.hasDataLengthIndicator)
        prefixLength += 4;

    if (
        payload.value.length >
        maximumFrameDataSize -
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
                        cast(ulong) payload.value.length +
                            cast(ulong) prefixLength,
                        maximumFrameDataSize
                    )
                );
    }

    const frameDataSize =
        prefixLength +
        payload.value.length;

    assert(frameDataSize != 0);

    Id3v24FrameHeader header;

    foreach (index; 0 .. 4)
    {
        header.id[index] =
            canonicalPlan.target.frameId[index];
    }

    header.size =
        cast(uint)
            frameDataSize;

    header.statusFlags =
        formatPlan.statusFlags;

    header.formatFlags =
        formatPlan.formatFlags;

    auto encodedHeader =
        serializeId3v24FrameHeader(
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

    ubyte[4] encodedDli;

    if (formatPlan.hasDataLengthIndicator)
    {
        auto dli =
            encodeSynchsafe32(
                cast(uint)
                    payload.value.length
            );

        assert(dli.hasValue);

        encodedDli =
            dli.value;
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

    if (formatPlan.hasGroupingIdentity)
    {
        output[position++] =
            formatPlan.groupingIdentity;
    }

    if (formatPlan.hasDataLengthIndicator)
    {
        output[
            position ..
            position + encodedDli.length
        ] =
            encodedDli[];

        position +=
            encodedDli.length;
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


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataKey,
        MetadataQualifier;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.regeneration_policy :
        Id3v24MappedFrameRegenerationStatus;

    import audiotag.id3v2.v24.unique_file_identifier :
        decodeId3v24UniqueFileIdentifierFrame;


    private MetadataField
    uniqueFileIdentifierField(
        string owner,
        const(ubyte)[] identifier
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataBinary.copyFrom(
                identifier
            );

        auto result =
            MetadataField(
                MetadataKey(
                    "uniqueFileIdentifier"
                ),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "owner",
                    owner
                )
            ];

        return result;
    }


    private Id3v24MappedFrameRegenerationFormatPlan
    writableFormatPlan(
        ubyte statusFlags = 0,
        ubyte formatFlags = 0,
        bool hasGroupingIdentity = false,
        ubyte groupingIdentity = 0,
        bool hasDataLengthIndicator = false
    )
        @safe pure nothrow @nogc
    {
        Id3v24MappedFrameRegenerationFormatPlan result;

        result.status =
            Id3v24MappedFrameRegenerationStatus.ready;

        result.statusFlags =
            statusFlags;

        result.formatFlags =
            formatFlags;

        result.hasGroupingIdentity =
            hasGroupingIdentity;

        result.groupingIdentity =
            groupingIdentity;

        result.hasDataLengthIndicator =
            hasDataLengthIndicator;

        return result;
    }
}


/// Canonical identifier metadata becomes one complete UFID frame.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "example.com",
            [
                cast(ubyte) 0x11,
                cast(ubyte) 0x22,
                cast(ubyte) 0xFE,
                cast(ubyte) 0xFF
            ]
        );

    auto serialized =
        serializeNewId3v24UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                100
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "UFID"
    );

    assert(
        envelope.value.header.statusFlags ==
        0
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    assert(
        envelope.value.header.size ==
        16
    );

    auto decoded =
        envelope.value
            .decodeId3v24UniqueFileIdentifierFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.uniqueFileIdentifier
            .ownerIdentifier ==
        "example.com"
    );

    assert(
        decoded.value.uniqueFileIdentifier
            .rawIdentifier.data ==
        [
            0x11,
            0x22,
            0xFE,
            0xFF
        ]
    );

    assert(
        decoded.value.uniqueFileIdentifier
            .logicalIdentifierLength ==
        4
    );
}


/// Empty identifier data remains a valid UFID payload.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            []
        );

    auto serialized =
        serializeNewId3v24UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.size ==
        6
    );

    auto decoded =
        envelope.value
            .decodeId3v24UniqueFileIdentifierFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.uniqueFileIdentifier
            .ownerIdentifier ==
        "owner"
    );

    assert(
        decoded.value.uniqueFileIdentifier
            .rawIdentifier.length ==
        0
    );

    assert(
        decoded.value.uniqueFileIdentifier
            .logicalIdentifierLength ==
        0
    );
}


/// Exactly 64 identifier bytes remain writable as a complete frame.
unittest
{
    ubyte[64] identifier;

    foreach (index; 0 .. identifier.length)
    {
        identifier[index] =
            cast(ubyte) index;
    }

    const field =
        uniqueFileIdentifierField(
            "owner",
            identifier[]
        );

    auto serialized =
        serializeNewId3v24UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    auto decoded =
        envelope.value
            .decodeId3v24UniqueFileIdentifierFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.uniqueFileIdentifier
            .logicalIdentifierLength ==
        64
    );
}


/// Regenerated UFID retains allowed alteration-status flags.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            [cast(ubyte) 0xAA]
        );

    const formatPlan =
        writableFormatPlan(
            0x60
        );

    auto serialized =
        serializeRegeneratedId3v24UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "UFID"
    );

    assert(
        envelope.value.header.statusFlags ==
        0x60
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );
}


/// Grouping and DLI precede the regenerated UFID semantic payload.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            [
                cast(ubyte) 0xAA,
                cast(ubyte) 0x00
            ]
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x41,
            true,
            0x33,
            true
        );

    auto serialized =
        serializeRegeneratedId3v24UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    /*
     * Semantic UFID payload:
     *
     *   "owner" 00 AA 00
     *
     * = 8 bytes.
     *
     * Physical frame data:
     *
     * grouping 1 + DLI 4 + payload 8 = 13 bytes.
     */
    assert(
        envelope.value.header.size ==
        13
    );

    assert(
        envelope.value.header.formatFlags ==
        0x41
    );

    assert(
        envelope.value.data.data ==
        [
            0x33,

            0x00, 0x00, 0x00, 0x08,

            'o', 'w', 'n', 'e', 'r',
            0x00,

            0xAA, 0x00
        ]
    );

    auto decoded =
        envelope.value
            .decodeId3v24UniqueFileIdentifierFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.uniqueFileIdentifier
            .ownerIdentifier ==
        "owner"
    );

    assert(
        decoded.value.uniqueFileIdentifier
            .rawIdentifier.data ==
        [0xAA, 0x00]
    );

    assert(
        decoded.value.uniqueFileIdentifier
            .logicalIdentifierLength ==
        2
    );
}


/// Contradictory grouping information is rejected defensively.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            []
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x40,
            false,
            0,
            false
        );

    auto serialized =
        serializeRegeneratedId3v24UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}


/// Non-writable structural plans cannot regenerate UFID bytes.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            []
        );

    Id3v24MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v24UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// The UFID writer rejects canonical fields targeting another family.
unittest
{
    MetadataValue wrapped =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0x01]
        );

    auto field =
        MetadataField(
            MetadataKey("privateData"),
            wrapped
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "example.invalid"
            )
        ];

    auto serialized =
        serializeNewId3v24UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
