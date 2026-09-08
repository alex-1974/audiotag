/++
Complete serialization of canonical ID3v2.3 unique-file-identifier
(`UFID`) frames.

Canonical UFID metadata consists of:

- one `MetadataBinary` identifier value;
- exactly one non-empty `owner` qualifier;
- no canonical media type, language or description.

The semantic payload is delegated to
`unique_file_identifier_write`:

    <non-empty owner as ISO-8859-1> $00
    <zero to 64 opaque identifier bytes>

Identifier bytes may contain arbitrary values including zero bytes.

New frames use zero status and format flags.

Regenerated existing frames use the established mapped-frame
regeneration policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported.

ID3v2.3 has no frame-level unsynchronisation or Data Length Indicator.
Whole-tag unsynchronisation remains a later tag-writing concern.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v23.unique_file_identifier_frame_write;

import std.sumtype :
    match;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataBinary;

import audiotag.id3v2.v23.canonical_target :
    Id3v23CanonicalTargetFamily;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader;

import audiotag.id3v2.v23.frame_header_write :
    serializeId3v23FrameHeader;

import audiotag.id3v2.v23.new_frame_plan :
    planId3v23CanonicalField;

import audiotag.id3v2.v23.regeneration_policy :
    Id3v23MappedFrameRegenerationFormatPlan;

import audiotag.id3v2.v23.unique_file_identifier_write :
    serializeId3v23UniqueFileIdentifierPayload;


/++
Serializes the semantic UFID payload represented by one canonical
field.

The public frame writers consult canonical planning first. This helper
also validates the expected canonical field shape defensively.
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
                serializeId3v23UniqueFileIdentifierPayload(
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
as a complete ID3v2.3 `UFID` frame.

Canonical planning is consulted first, so invalid owner context,
unsupported media types and identifier lengths outside the native
0..64-byte range cannot silently reach physical output.

New frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `uniqueFileIdentifier` field.

Returns:
    Complete owned UFID frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23UniqueFileIdentifierFrame(
    ref const(MetadataField) field
)
    @safe
{
    const plan =
        planId3v23CanonicalField(
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
        Id3v23CanonicalTargetFamily
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
        uint.max
    );

    Id3v23FrameHeader header;

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
regenerated existing ID3v2.3 `UFID` frame.

The structural regeneration plan controls preservation of alteration
flags and optional grouping identity.

Params:
    field = Replacement canonical `uniqueFileIdentifier` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native UFID frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23UniqueFileIdentifierFrame(
    ref const(MetadataField) field,
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
                        cast(ulong) formatPlan.status
                    )
                );
    }

    /*
     * Writable v2.3 regeneration plans may contain only:
     *
     * status: tag/file alteration bits 0x80/0x40
     * format: grouping identity bit 0x20
     */
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

    const groupingFlag =
        (
            formatPlan.formatFlags &
            0x20
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

    const canonicalPlan =
        planId3v23CanonicalField(
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
        Id3v23CanonicalTargetFamily
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
        uint.max;

    const size_t prefixLength =
        formatPlan.hasGroupingIdentity
        ? 1
        : 0;

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

    Id3v23FrameHeader header;

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

    if (formatPlan.hasGroupingIdentity)
    {
        output[position++] =
            formatPlan.groupingIdentity;
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

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.regeneration_policy :
        Id3v23MappedFrameRegenerationStatus;


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


    private Id3v23MappedFrameRegenerationFormatPlan
    writableFormatPlan(
        ubyte statusFlags = 0,
        ubyte formatFlags = 0,
        bool hasGroupingIdentity = false,
        ubyte groupingIdentity = 0
    )
        @safe pure nothrow @nogc
    {
        Id3v23MappedFrameRegenerationFormatPlan result;

        result.status =
            Id3v23MappedFrameRegenerationStatus.ready;

        result.statusFlags =
            statusFlags;

        result.formatFlags =
            formatFlags;

        result.hasGroupingIdentity =
            hasGroupingIdentity;

        result.groupingIdentity =
            groupingIdentity;

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
        serializeNewId3v23UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x10,
            0x00, 0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm',
            0x00,

            0x11,
            0x22,
            0xFE,
            0xFF
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(
                serialized.value[],
                100
            )
        );

    auto envelope =
        cursor.parseId3v23FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "UFID"
    );

    assert(envelope.value.header.size == 16);
    assert(envelope.value.header.statusFlags == 0);
    assert(envelope.value.header.formatFlags == 0);
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
        serializeNewId3v23UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            'o', 'w', 'n', 'e', 'r',
            0x00
        ]
    );
}


/// Exactly 64 logical identifier bytes remain representable.
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
        serializeNewId3v23UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v23FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.size ==
        70
    );

    assert(
        envelope.value.data.data[
            6 ..
            $
        ] ==
        identifier[]
    );
}


/// A 65-byte identifier is rejected before physical frame output.
unittest
{
    ubyte[65] identifier;

    const field =
        uniqueFileIdentifierField(
            "owner",
            identifier[]
        );

    auto serialized =
        serializeNewId3v23UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Empty owner context is invalid for UFID.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "",
            []
        );

    auto serialized =
        serializeNewId3v23UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated UFID frames preserve allowed alteration-status bits.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            [cast(ubyte) 0xAA]
        );

    const formatPlan =
        writableFormatPlan(
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v23FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "UFID"
    );

    assert(
        envelope.value.header.statusFlags ==
        0xC0
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );
}


/// Grouping identity precedes the regenerated UFID semantic payload.
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
            0x40,
            0x20,
            true,
            0x33
        );

    auto serialized =
        serializeRegeneratedId3v23UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Semantic UFID payload:
     *
     *   "owner" 00 AA 00
     *
     * = 8 bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + payload 8 = 9.
     */
    assert(
        serialized.value ==
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x09,
            0x40, 0x20,

            0x33,

            'o', 'w', 'n', 'e', 'r',
            0x00,
            0xAA,
            0x00
        ]
    );
}


/// Contradictory grouping state is rejected defensively.
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
            0x20,
            false,
            0
        );

    auto serialized =
        serializeRegeneratedId3v23UniqueFileIdentifierFrame(
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


/// Unsupported writable-format bits cannot leak into regenerated output.
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
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23UniqueFileIdentifierFrame(
            field,
            formatPlan
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .invalidFlags
    );

    assert(serialized.error.index == 9);
}


/// Non-writable structural plans cannot regenerate UFID bytes.
unittest
{
    const field =
        uniqueFileIdentifierField(
            "owner",
            []
        );

    Id3v23MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23UniqueFileIdentifierFrame(
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


/// The UFID writer rejects canonical fields targeting PRIV.
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
        serializeNewId3v23UniqueFileIdentifierFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
