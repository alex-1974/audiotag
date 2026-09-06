/++
Complete serialization of canonical ID3v2.4 private (`PRIV`) frames.

Canonical PRIV metadata consists of:

- one `MetadataBinary` value;
- exactly one `owner` qualifier;
- no canonical media type, language or description.

The semantic payload is delegated to `private_write`.

New frames use zero status and format flags.

Regenerated existing frames follow the common mapped-frame policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported;
- frame-level unsynchronisation is removed;
- DLI presence is preserved and its value is recomputed from the new
  semantic PRIV payload.
+/
module audiotag.id3v2.v24.private_frame_write;

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

import audiotag.id3v2.v24.private_write :
    serializeId3v24PrivatePayload;

import audiotag.id3v2.v24.regeneration_policy :
    Id3v24MappedFrameRegenerationFormatPlan;


/++
Serializes the semantic PRIV payload represented by one canonical
field.

The canonical planner is still consulted by the public frame writers.
This helper additionally validates the expected shape defensively.
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
                serializeId3v24PrivatePayload(
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
complete ID3v2.4 `PRIV` frame.

New native frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `privateData` field.

Returns:
    Complete owned PRIV frame bytes including the ten-byte frame header,
    or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24PrivateFrame(
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
        Id3v24CanonicalTargetFamily.privateData
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
Serializes modified canonical private data as a regenerated existing
ID3v2.4 `PRIV` frame.

The DLI, when retained, describes the regenerated semantic PRIV payload
only. Grouping and DLI prefix bytes contribute to physical frame size
but not to the DLI value.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24PrivateFrame(
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

    /*
     * Writable regeneration plans may retain only:
     *
     * status: tag/file alteration bits 0x40/0x20
     * format: grouping 0x40 and DLI 0x01
     */
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
        Id3v24CanonicalTargetFamily.privateData
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

    import audiotag.id3v2.v24.private_frame :
        decodeId3v24PrivateFrame;

    import audiotag.id3v2.v24.regeneration_policy :
        Id3v24MappedFrameRegenerationStatus;


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
        serializeNewId3v24PrivateFrame(
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
        "PRIV"
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
        envelope.value.decodeId3v24PrivateFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.privateFrame.ownerIdentifier ==
        "example.com"
    );

    assert(
        decoded.value.privateFrame.rawPrivateData.data ==
        [
            0x01,
            0x02,
            0xFE,
            0xFF
        ]
    );
}


/// Empty owner and data still produce the mandatory PRIV owner terminator.
unittest
{
    const field =
        privateField(
            "",
            []
        );

    auto serialized =
        serializeNewId3v24PrivateFrame(
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
        1
    );

    assert(
        envelope.value.data.data ==
        [0x00]
    );

    auto decoded =
        envelope.value.decodeId3v24PrivateFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.privateFrame.ownerIdentifier.length ==
        0
    );

    assert(
        decoded.value.privateFrame.rawPrivateData.length ==
        0
    );
}


/// Regenerated PRIV retains allowed alteration-status flags.
unittest
{
    const field =
        privateField(
            "owner",
            [cast(ubyte) 0xAA]
        );

    const formatPlan =
        writableFormatPlan(
            0x60
        );

    auto serialized =
        serializeRegeneratedId3v24PrivateFrame(
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
        "PRIV"
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


/// Grouping and DLI precede the regenerated PRIV semantic payload.
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
            0,
            0x41,
            true,
            0x33,
            true
        );

    auto serialized =
        serializeRegeneratedId3v24PrivateFrame(
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
     * Semantic payload:
     *
     *   "owner" 00 AA 00
     *
     * = 8 bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + DLI 4 + payload 8 = 13.
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
        envelope.value.decodeId3v24PrivateFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.privateFrame.ownerIdentifier ==
        "owner"
    );

    assert(
        decoded.value.privateFrame.rawPrivateData.data ==
        [0xAA, 0x00]
    );
}


/// Contradictory grouping information is rejected defensively.
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
            0x40,
            false,
            0,
            false
        );

    auto serialized =
        serializeRegeneratedId3v24PrivateFrame(
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


/// Non-writable structural plans cannot regenerate PRIV bytes.
unittest
{
    const field =
        privateField(
            "owner",
            []
        );

    Id3v24MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v24PrivateFrame(
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


/// The PRIV writer rejects canonical fields targeting another family.
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
        serializeNewId3v24PrivateFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
