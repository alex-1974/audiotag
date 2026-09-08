/++
Complete serialization of canonical ID3v2.3 user-defined URL (`WXXX`)
frames.

A canonical `userUrl` field consists of:

- one scalar `MetadataUrl`;
- optional canonical description context.

The semantic payload is delegated to `user_url_write` and has the
ID3v2.3 form:

    <description encoding marker>
    <description>
    <mandatory description terminator>
    <URL as ISO-8859-1>

The encoding marker applies only to the description. The URL is always
ISO-8859-1 and receives no optional trailing terminator.

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
module audiotag.id3v2.v23.user_url_frame_write;

import std.sumtype :
    match;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataUrl;

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

import audiotag.id3v2.v23.user_url_write :
    serializeId3v23UserUrlPayload;


/++
Serializes the WXXX payload represented by one canonical `userUrl`
field.

The canonical planner must already have established that this field
targets the ID3v2.3 `userUrl` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalUserUrlPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataUrl) url) =>
            serializeId3v23UserUrlPayload(
                field.description,
                url.value
            ),

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
Serializes one newly introduced canonical `userUrl` field as a complete
ID3v2.3 `WXXX` frame.

Canonical planning is consulted first, so unsupported context, invalid
value shape and unrepresentable WXXX payloads cannot silently reach
physical output.

New frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `userUrl` field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23UserUrlFrame(
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
        Id3v23CanonicalTargetFamily.userUrl
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
        serializeCanonicalUserUrlPayload(
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
        plan.target.frameId.length ==
        4
    );

    assert(
        plan.target.frameId ==
        "WXXX"
    );

    /*
     * Every valid WXXX payload contains at least the description
     * encoding marker and mandatory description terminator.
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
Serializes modified canonical `userUrl` metadata as a regenerated
existing ID3v2.3 `WXXX` frame.

The structural regeneration plan controls preservation of alteration
flags and optional grouping identity.

Params:
    field = Replacement canonical `userUrl` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23UserUrlFrame(
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
        Id3v23CanonicalTargetFamily.userUrl
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
        serializeCanonicalUserUrlPayload(
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
        "WXXX"
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
        MetadataKey;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.regeneration_policy :
        Id3v23MappedFrameRegenerationStatus;


    private MetadataField
    userUrlField(
        string description,
        string url
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataUrl(url);

        auto result =
            MetadataField(
                MetadataKey("userUrl"),
                wrapped
            );

        result.description =
            description;

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


/// A canonical user URL becomes a complete Latin-1 WXXX frame.
unittest
{
    const field =
        userUrlField(
            "home",
            "example.com"
        );

    auto serialized =
        serializeNewId3v23UserUrlFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x11,
            0x00, 0x00,

            0x00,
            'h', 'o', 'm', 'e',
            0x00,
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
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
        "WXXX"
    );

    assert(
        envelope.value.header.size ==
        17
    );
}


/// Empty description and URL retain the minimal valid WXXX payload.
unittest
{
    const field =
        userUrlField(
            "",
            ""
        );

    auto serialized =
        serializeNewId3v23UserUrlFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            0x00
        ]
    );
}


/// Wider BMP description uses UCS-2 while the URL remains Latin-1.
unittest
{
    const field =
        userUrlField(
            "\u03A9",
            "x\u00E9"
        );

    auto serialized =
        serializeNewId3v23UserUrlFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x01,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00,

            'x',
            0xE9
        ]
    );
}


/// An empty WXXX URL adds no ordinary-W*** empty-value byte.
unittest
{
    const field =
        userUrlField(
            "home",
            ""
        );

    auto serialized =
        serializeNewId3v23UserUrlFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'h', 'o', 'm', 'e',
            0x00
        ]
    );
}


/// URL constraints diagnosed by canonical planning prevent frame output.
unittest
{
    const field =
        userUrlField(
            "homepage",
            "https://example.test/\u20AC"
        );

    auto serialized =
        serializeNewId3v23UserUrlFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated WXXX frames preserve allowed alteration-status bits.
unittest
{
    const field =
        userUrlField(
            "key",
            "new"
        );

    const formatPlan =
        writableFormatPlan(
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23UserUrlFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0xC0, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'n', 'e', 'w'
        ]
    );
}


/// Grouping identity precedes the regenerated WXXX semantic payload.
unittest
{
    const field =
        userUrlField(
            "key",
            "abc"
        );

    const formatPlan =
        writableFormatPlan(
            0x40,
            0x20,
            true,
            0x33
        );

    auto serialized =
        serializeRegeneratedId3v23UserUrlFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Semantic WXXX payload:
     *
     *   00 'k' 'e' 'y' 00 'a' 'b' 'c'
     *
     * = 8 bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + semantic payload 8 = 9.
     */
    assert(
        serialized.value ==
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x09,
            0x40, 0x20,

            0x33,

            0x00,
            'k', 'e', 'y',
            0x00,
            'a', 'b', 'c'
        ]
    );

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v23FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(envelope.value.header.size == 9);
    assert(envelope.value.header.hasGroupingIdentity);
}


/// Contradictory grouping state is rejected defensively.
unittest
{
    const field =
        userUrlField(
            "key",
            "value"
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x20,
            false,
            0
        );

    auto serialized =
        serializeRegeneratedId3v23UserUrlFrame(
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
        userUrlField(
            "key",
            "value"
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23UserUrlFrame(
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


/// Non-writable regeneration plans cannot produce modified WXXX bytes.
unittest
{
    const field =
        userUrlField(
            "key",
            "value"
        );

    Id3v23MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23UserUrlFrame(
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


/// The WXXX writer rejects canonical fields targeting ordinary URL frames.
unittest
{
    MetadataValue wrapped =
        MetadataUrl(
            "https://example.test/"
        );

    const field =
        MetadataField(
            MetadataKey("commercialUrl"),
            wrapped
        );

    const formatPlan =
        writableFormatPlan();

    auto serialized =
        serializeRegeneratedId3v23UserUrlFrame(
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
