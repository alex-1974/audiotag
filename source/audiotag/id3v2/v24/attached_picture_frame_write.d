/++
Complete serialization of canonical ID3v2.4 attached-picture (`APIC`)
frames.

Canonical artwork consists of:

- one `MetadataPicture`;
- exactly one `pictureRole` field qualifier;
- either embedded `MetadataBinary` picture data with a MIME type or a
  linked `MetadataUrl`;
- the human-readable APIC description stored in
  `MetadataPicture.description`.

The semantic APIC payload is delegated to `attached_picture_write`.

New frames use zero status and format flags.

Regenerated existing frames use the established mapped-frame
regeneration policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported;
- frame-level unsynchronisation is cleared;
- DLI presence is preserved and its value recomputed from the new
  semantic APIC payload.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v24.attached_picture_frame_write;

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
    MetadataBinary,
    MetadataPicture,
    MetadataUrl;

import audiotag.id3v2.v24.attached_picture_write :
    serializeId3v24Utf8EmbeddedPicturePayload,
    serializeId3v24Utf8LinkedPicturePayload;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;

import audiotag.id3v2.v24.frame_header_write :
    serializeId3v24FrameHeader;

import audiotag.id3v2.v24.new_frame_plan :
    planId3v24CanonicalField;

import audiotag.id3v2.v24.picture_role :
    findId3v24PictureRole;

import audiotag.id3v2.v24.regeneration_policy :
    Id3v24MappedFrameRegenerationFormatPlan;


/++
Serializes the APIC semantic payload represented by one canonical
artwork field.

The canonical planner must already have established that the field
targets the `attachedPicture` family. This helper nevertheless rejects
an invalid role/value shape defensively.
+/
private SerializationResult!(ubyte[])
serializeCanonicalAttachedPicturePayload(
    ref const(MetadataField) field
)
    @safe
{
    if (
        field.qualifiers.length != 1 ||
        field.qualifiers[0].name != "pictureRole"
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

    const role =
        findId3v24PictureRole(
            field.qualifiers[0].value
        );

    if (!role.found)
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
        (const(MetadataPicture) picture)
        {
            return picture.source.match!(
                (const(MetadataBinary) binary) =>
                    serializeId3v24Utf8EmbeddedPicturePayload(
                        binary.mediaType,
                        role.definition.pictureType,
                        picture.description,
                        binary.data
                    ),

                (const(MetadataUrl) url) =>
                    serializeId3v24Utf8LinkedPicturePayload(
                        role.definition.pictureType,
                        picture.description,
                        url.value
                    )
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
Serializes one newly introduced canonical artwork field as a complete
ID3v2.4 `APIC` frame.

The canonical planner is consulted first, so missing or unknown
`pictureRole` context and unrepresentable picture payloads cannot reach
physical output.

New native frames deliberately use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `artwork` field.

Returns:
    Complete owned APIC frame bytes including the ten-byte ID3v2.4
    frame header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24AttachedPictureFrame(
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
        Id3v24CanonicalTargetFamily.attachedPicture
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
        serializeCanonicalAttachedPicturePayload(
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
        "APIC"
    );

    /*
     * Every valid APIC semantic payload contains at least:
     *
     * encoding marker
     * MIME data
     * MIME terminator
     * picture type
     * description terminator
     */
    assert(payload.value.length >= 5);

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
Serializes modified canonical artwork as a regenerated existing
ID3v2.4 `APIC` frame.

The Data Length Indicator describes only the regenerated semantic APIC
payload. Grouping and DLI bytes contribute to the physical frame-data
size but are not included in the DLI value.

Params:
    field = Replacement canonical `artwork` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated APIC frame bytes or a structured serialization
    failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24AttachedPictureFrame(
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
     * Writable current regeneration plans may retain only:
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
        Id3v24CanonicalTargetFamily.attachedPicture
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
        serializeCanonicalAttachedPicturePayload(
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
        "APIC"
    );

    assert(payload.value.length >= 5);

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
        MetadataPictureSource,
        MetadataText,
        MetadataValue;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.regeneration_policy :
        Id3v24MappedFrameRegenerationStatus;


    private MetadataField
    embeddedPictureField(
        string role,
        string description,
        string mimeType,
        const(ubyte)[] data
    )
        @safe
    {
        MetadataPictureSource source =
            MetadataBinary.copyFrom(
                data,
                mimeType
            );

        MetadataValue wrapped =
            MetadataPicture(
                description,
                source
            );

        auto result =
            MetadataField(
                MetadataKey("artwork"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "pictureRole",
                    role
                )
            ];

        return result;
    }


    private MetadataField
    linkedPictureField(
        string role,
        string description,
        string url
    )
        @safe
    {
        MetadataPictureSource source =
            MetadataUrl(url);

        MetadataValue wrapped =
            MetadataPicture(
                description,
                source
            );

        auto result =
            MetadataField(
                MetadataKey("artwork"),
                wrapped
            );

        result.qualifiers =
            [
                MetadataQualifier(
                    "pictureRole",
                    role
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


/// Embedded canonical artwork becomes one complete APIC frame.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "Front",
            "image/jpeg",
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8
            ]
        );

    auto serialized =
        serializeNewId3v24AttachedPictureFrame(
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
        "APIC"
    );

    assert(
        envelope.value.header.statusFlags ==
        0
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    /*
     * $03
     * "image/jpeg" $00
     * frontCover = $03
     * "Front" $00
     * FF D8
     *
     * = 21 semantic bytes.
     */
    assert(
        envelope.value.header.size ==
        21
    );

    assert(
        envelope.value.data.data ==
        [
            0x03,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF, 0xD8
        ]
    );
}


/// Linked canonical artwork becomes an APIC frame using MIME "-->".
unittest
{
    const field =
        linkedPictureField(
            "backCover",
            "Cover",
            "http://x"
        );

    auto serialized =
        serializeNewId3v24AttachedPictureFrame(
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
        envelope.value.header.id[] ==
        "APIC"
    );

    /*
     * $03 "-->" $00 backCover($04)
     * "Cover" $00 "http://x"
     */
    assert(
        envelope.value.data.data ==
        [
            0x03,
            '-', '-', '>',
            0x00,
            0x04,
            'C', 'o', 'v', 'e', 'r',
            0x00,
            'h', 't', 't', 'p', ':', '/',
            '/', 'x'
        ]
    );
}


/// Canonical APIC payload failures cannot reach complete frame output.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "Front\0cover",
            "image/jpeg",
            [cast(ubyte) 0xFF]
        );

    auto serialized =
        serializeNewId3v24AttachedPictureFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated APIC retains allowed alteration-status bits.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "Front",
            "image/jpeg",
            [cast(ubyte) 0xAA]
        );

    const formatPlan =
        writableFormatPlan(
            0x60
        );

    auto serialized =
        serializeRegeneratedId3v24AttachedPictureFrame(
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
        "APIC"
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


/// Grouping and DLI precede a regenerated APIC semantic payload.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "x",
            "image/jpeg",
            [cast(ubyte) 0xAA]
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
        serializeRegeneratedId3v24AttachedPictureFrame(
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
     * Semantic APIC payload:
     *
     *   03
     *   "image/jpeg" 00
     *   03
     *   'x' 00
     *   AA
     *
     * = 16 bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + DLI 4 + semantic payload 16 = 21.
     */
    assert(
        envelope.value.header.size ==
        21
    );

    assert(
        envelope.value.header.formatFlags ==
        0x41
    );

    assert(
        envelope.value.data.data ==
        [
            0x33,

            0x00, 0x00, 0x00, 0x10,

            0x03,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'x',
            0x00,

            0xAA
        ]
    );
}


/// Contradictory APIC grouping information is rejected defensively.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "",
            "image/jpeg",
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
        serializeRegeneratedId3v24AttachedPictureFrame(
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


/// Non-writable structural plans cannot produce regenerated APIC bytes.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "",
            "image/jpeg",
            []
        );

    Id3v24MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v24AttachedPictureFrame(
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


/// The APIC writer rejects canonical fields targeting another family.
unittest
{
    MetadataValue wrapped =
        MetadataText("Title");

    const field =
        MetadataField(
            MetadataKey("title"),
            wrapped
        );

    auto serialized =
        serializeNewId3v24AttachedPictureFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
