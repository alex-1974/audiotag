/++
Complete serialization of canonical ID3v2.3 attached-picture (`APIC`)
frames.

Canonical artwork consists of:

- one `MetadataPicture`;
- exactly one `pictureRole` field qualifier;
- either embedded `MetadataBinary` picture data with a MIME type or a
  linked `MetadataUrl`;
- the human-readable APIC description stored in
  `MetadataPicture.description`.

The semantic APIC payload is delegated to `attached_picture_write`.

Embedded pictures use the native ID3v2.3 form:

    <encoding>
    <MIME as ISO-8859-1> $00
    <picture type>
    <description>
    <description terminator>
    <binary image data>

Linked pictures use the reserved MIME spelling `"-->"` and place the
ISO-8859-1 URL at the payload boundary.

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
module audiotag.id3v2.v23.attached_picture_frame_write;

import std.sumtype :
    match;

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

import audiotag.id3v2.v23.attached_picture_write :
    serializeId3v23EmbeddedPicturePayload,
    serializeId3v23LinkedPicturePayload;

import audiotag.id3v2.v23.canonical_target :
    Id3v23CanonicalTargetFamily;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader;

import audiotag.id3v2.v23.frame_header_write :
    serializeId3v23FrameHeader;

import audiotag.id3v2.v23.new_frame_plan :
    planId3v23CanonicalField;

import audiotag.id3v2.v23.picture_role :
    findId3v23PictureRole;

import audiotag.id3v2.v23.regeneration_policy :
    Id3v23MappedFrameRegenerationFormatPlan;


/++
Serializes the semantic APIC payload represented by one canonical
artwork field.

Canonical planning must already have established that the field targets
the `attachedPicture` family. This helper additionally validates the
role and value shape defensively.
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
        findId3v23PictureRole(
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
                    serializeId3v23EmbeddedPicturePayload(
                        binary.mediaType,
                        role.definition.pictureType,
                        picture.description,
                        binary.data
                    ),

                (const(MetadataUrl) url) =>
                    serializeId3v23LinkedPicturePayload(
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
ID3v2.3 `APIC` frame.

Canonical planning is consulted first, so missing or unknown
`pictureRole` context and unrepresentable embedded or linked picture
payloads cannot reach physical output.

New frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `artwork` field.

Returns:
    Complete owned APIC frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23AttachedPictureFrame(
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
        Id3v23CanonicalTargetFamily.attachedPicture
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
     * MIME terminator
     * picture type
     * description terminator
     *
     * The v2.3 payload codec permits an empty embedded MIME value.
     */
    assert(payload.value.length >= 4);

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
Serializes modified canonical artwork as a regenerated existing
ID3v2.3 `APIC` frame.

The structural regeneration plan controls preservation of alteration
flags and optional grouping identity.

Params:
    field = Replacement canonical `artwork` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native APIC frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23AttachedPictureFrame(
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
        Id3v23CanonicalTargetFamily.attachedPicture
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

    assert(payload.value.length >= 4);

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
        MetadataPictureSource,
        MetadataText,
        MetadataValue;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.regeneration_policy :
        Id3v23MappedFrameRegenerationStatus;


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
        serializeNewId3v23AttachedPictureFrame(
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
        cursor.parseId3v23FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "APIC"
    );

    assert(envelope.value.header.statusFlags == 0);
    assert(envelope.value.header.formatFlags == 0);
    assert(envelope.value.header.size == 21);

    assert(
        envelope.value.data.data ==
        [
            0x00,

            'i', 'm', 'a', 'g', 'e', '/',
            'j', 'p', 'e', 'g',
            0x00,

            0x03,

            'F', 'r', 'o', 'n', 't',
            0x00,

            0xFF,
            0xD8
        ]
    );
}


/// Linked canonical artwork uses the reserved native MIME marker.
unittest
{
    const field =
        linkedPictureField(
            "backCover",
            "Cover",
            "http://x"
        );

    auto serialized =
        serializeNewId3v23AttachedPictureFrame(
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
        envelope.value.header.id[] ==
        "APIC"
    );

    assert(
        envelope.value.data.data ==
        [
            0x00,

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


/// A wider BMP description selects strict ID3v2.3 UCS-2.
unittest
{
    const field =
        embeddedPictureField(
            "frontCover",
            "\u03A9",
            "image/png",
            [cast(ubyte) 0x89]
        );

    auto serialized =
        serializeNewId3v23AttachedPictureFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[
            10 ..
            $
        ] ==
        [
            0x01,

            'i', 'm', 'a', 'g', 'e', '/',
            'p', 'n', 'g',
            0x00,

            0x03,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00,

            0x89
        ]
    );
}


/// Empty embedded MIME, description and image data remain representable.
unittest
{
    const field =
        embeddedPictureField(
            "other",
            "",
            "",
            []
        );

    auto serialized =
        serializeNewId3v23AttachedPictureFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
            0x00,
            0x00,
            0x00
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
        serializeNewId3v23AttachedPictureFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Unknown picture roles cannot reach physical APIC output.
unittest
{
    const field =
        embeddedPictureField(
            "futurePictureRole",
            "",
            "image/jpeg",
            []
        );

    auto serialized =
        serializeNewId3v23AttachedPictureFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated APIC preserves allowed alteration-status bits.
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
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23AttachedPictureFrame(
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
        "APIC"
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


/// Grouping identity precedes the regenerated APIC semantic payload.
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
            0x40,
            0x20,
            true,
            0x33
        );

    auto serialized =
        serializeRegeneratedId3v23AttachedPictureFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Semantic APIC payload:
     *
     *   00
     *   "image/jpeg" 00
     *   03
     *   'x' 00
     *   AA
     *
     * = 16 bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + semantic payload 16 = 17.
     */
    assert(
        serialized.value ==
        [
            'A', 'P', 'I', 'C',
            0x00, 0x00, 0x00, 0x11,
            0x40, 0x20,

            0x33,

            0x00,

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
            0x20,
            false,
            0
        );

    auto serialized =
        serializeRegeneratedId3v23AttachedPictureFrame(
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


/// Unsupported writable-format bits cannot leak into regenerated APIC.
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
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23AttachedPictureFrame(
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

    Id3v23MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23AttachedPictureFrame(
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
        serializeNewId3v23AttachedPictureFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
