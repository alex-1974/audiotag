/++
Complete serialization of canonical ID3v2.3 private (`PRIV`) frames.

Canonical PRIV metadata consists of:

- one `MetadataBinary` value;
- exactly one `owner` qualifier;
- no canonical media type, language or description.

The semantic payload is delegated to `private_write`:

    <owner as ISO-8859-1> $00 <opaque private data>

The owner terminator is mandatory. An empty owner is valid. Private data
may contain arbitrary bytes, including zero bytes, and may itself be
empty.

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
module audiotag.id3v2.v23.private_frame_write;

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

import audiotag.id3v2.v23.private_write :
    serializeId3v23PrivatePayload;

import audiotag.id3v2.v23.regeneration_policy :
    Id3v23MappedFrameRegenerationFormatPlan;


/++
Serializes the semantic PRIV payload represented by one canonical field.

The public frame writers still consult canonical planning. This helper
also validates the expected canonical shape defensively.
+/
private SerializationResult!(ubyte[])
serializeCanonicalPrivatePayload(
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
             * PRIV has no native media-type field.
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
                serializeId3v23PrivatePayload(
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
Serializes one newly introduced canonical private-data field as a
complete ID3v2.3 `PRIV` frame.

Canonical planning is consulted first, so invalid owner context,
unrepresentable owner text, unsupported media types and invalid value
shapes cannot silently reach physical output.

New frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `privateData` field.

Returns:
    Complete owned PRIV frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23PrivateFrame(
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
        Id3v23CanonicalTargetFamily.privateData
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
        serializeCanonicalPrivatePayload(
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
        "PRIV"
    );

    /*
     * Every valid PRIV payload contains at least the mandatory owner
     * terminator.
     */
    assert(payload.value.length >= 1);

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
Serializes modified canonical private data as a regenerated existing
ID3v2.3 `PRIV` frame.

The structural regeneration plan controls preservation of alteration
flags and optional grouping identity.

Params:
    field = Replacement canonical `privateData` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native PRIV frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23PrivateFrame(
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
     *
     * Read-only, compression and encryption never reach regenerated
     * physical output.
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
        Id3v23CanonicalTargetFamily.privateData
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
        serializeCanonicalPrivatePayload(
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
        "PRIV"
    );

    assert(payload.value.length >= 1);

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
    privateField(
        string owner,
        const(ubyte)[] data
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataBinary.copyFrom(
                data
            );

        auto result =
            MetadataField(
                MetadataKey("privateData"),
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


/// Canonical private data becomes one complete PRIV frame.
unittest
{
    const field =
        privateField(
            "example.com",
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x02,
                cast(ubyte) 0xFE,
                cast(ubyte) 0xFF
            ]
        );

    auto serialized =
        serializeNewId3v23PrivateFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x10,
            0x00, 0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm',
            0x00,

            0x01,
            0x02,
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
        "PRIV"
    );

    assert(envelope.value.header.size == 16);
    assert(envelope.value.header.statusFlags == 0);
    assert(envelope.value.header.formatFlags == 0);
}


/// Empty owner and data retain the mandatory PRIV owner terminator.
unittest
{
    const field =
        privateField(
            "",
            []
        );

    auto serialized =
        serializeNewId3v23PrivateFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x00
        ]
    );
}


/// Latin-1 owner identifiers retain their native byte representation.
unittest
{
    const field =
        privateField(
            "caf\u00E9",
            []
        );

    auto serialized =
        serializeNewId3v23PrivateFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            'c', 'a', 'f',
            0xE9,
            0x00
        ]
    );
}


/// Opaque private data preserves zero and unsynchronisation-like bytes.
unittest
{
    const field =
        privateField(
            "x",
            [
                cast(ubyte) 0x00,
                cast(ubyte) 0xFF,
                cast(ubyte) 0xE0,
                cast(ubyte) 0x00
            ]
        );

    auto serialized =
        serializeNewId3v23PrivateFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[
            10 ..
            $
        ] ==
        [
            'x',
            0x00,
            0x00,
            0xFF,
            0xE0,
            0x00
        ]
    );
}


/// Owner constraints diagnosed by canonical planning prevent frame output.
unittest
{
    const field =
        privateField(
            "owner/\u20AC",
            []
        );

    auto serialized =
        serializeNewId3v23PrivateFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated PRIV frames preserve allowed alteration-status bits.
unittest
{
    const field =
        privateField(
            "owner",
            [cast(ubyte) 0xAA]
        );

    const formatPlan =
        writableFormatPlan(
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23PrivateFrame(
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
        "PRIV"
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


/// Grouping identity precedes the regenerated PRIV semantic payload.
unittest
{
    const field =
        privateField(
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
        serializeRegeneratedId3v23PrivateFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Semantic PRIV payload:
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
            'P', 'R', 'I', 'V',
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
        privateField(
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
        serializeRegeneratedId3v23PrivateFrame(
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
        privateField(
            "owner",
            []
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23PrivateFrame(
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


/// Non-writable structural plans cannot regenerate PRIV bytes.
unittest
{
    const field =
        privateField(
            "owner",
            []
        );

    Id3v23MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23PrivateFrame(
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


/// The PRIV writer rejects canonical fields targeting UFID.
unittest
{
    MetadataValue wrapped =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0x01]
        );

    auto field =
        MetadataField(
            MetadataKey("uniqueFileIdentifier"),
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
        serializeNewId3v23PrivateFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
