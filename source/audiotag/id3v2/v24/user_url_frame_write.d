/++
Complete serialization of canonical ID3v2.4 user-defined URL (`WXXX`)
frames.

A canonical `userUrl` field consists of:

- one scalar `MetadataUrl`;
- optional canonical field description context.

The physical payload is produced deterministically as:

    $03 <description UTF-8> $00 <URL ISO-8859-1>

The URL receives no optional trailing terminator.

New frames use zero status and format flags.

Regenerated existing frames use the established mapped-frame
regeneration policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported;
- frame-level unsynchronisation is cleared;
- DLI presence is preserved and its value recomputed from the new
  semantic WXXX payload.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v24.user_url_frame_write;

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
    MetadataUrl;

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

import audiotag.id3v2.v24.user_url_write :
    serializeId3v24Utf8UserUrlPayload;


/++
Serializes the WXXX payload represented by one canonical `userUrl`
field.

The caller must already have established that the field targets the
`userUrl` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalUserUrlPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataUrl) url) =>
            serializeId3v24Utf8UserUrlPayload(
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
ID3v2.4 `WXXX` frame.

The canonical planner is consulted first, so unsupported context,
invalid value shape and unrepresentable WXXX payloads never reach
physical output.

New native frames deliberately use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `userUrl` field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.4 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24UserUrlFrame(
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
        Id3v24CanonicalTargetFamily.userUrl
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
     * Every valid WXXX payload contains at least encoding marker and
     * mandatory description terminator.
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
Serializes modified canonical `userUrl` metadata as a regenerated
existing ID3v2.4 `WXXX` frame.

The structural regeneration plan controls preservation of alteration
flags, grouping identity and DLI presence.

The Data Length Indicator describes the regenerated semantic WXXX
payload length. Grouping and DLI bytes contribute to the physical
frame-data size but are not included in the DLI value.

Params:
    field = Replacement canonical `userUrl` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24UserUrlFrame(
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
        Id3v24CanonicalTargetFamily.userUrl
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
        MetadataKey;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.regeneration_policy :
        Id3v24MappedFrameRegenerationStatus;

    import audiotag.id3v2.v24.user_url :
        decodeId3v24UserUrlFrame;


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


/// A canonical user URL becomes a complete WXXX frame.
unittest
{
    const field =
        userUrlField(
            "homepage",
            "https://example.test/"
        );

    auto serialized =
        serializeNewId3v24UserUrlFrame(
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
        "WXXX"
    );

    assert(
        envelope.value.header.statusFlags ==
        0
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    auto decoded =
        envelope.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description ==
        "homepage"
    );

    assert(
        decoded.value.link.url ==
        "https://example.test/"
    );
}


/// Empty description and URL remain a valid minimal WXXX frame.
unittest
{
    const field =
        userUrlField(
            "",
            ""
        );

    auto serialized =
        serializeNewId3v24UserUrlFrame(
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

    assert(
        envelope.value.header.size ==
        2
    );

    assert(
        envelope.value.data.data ==
        [0x03, 0x00]
    );

    auto decoded =
        envelope.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description.length ==
        0
    );

    assert(
        decoded.value.link.url.length ==
        0
    );
}


/// Description remains UTF-8 while URL uses native ISO-8859-1.
unittest
{
    const field =
        userUrlField(
            "Größe",
            "https://example.test/\u00E9"
        );

    auto serialized =
        serializeNewId3v24UserUrlFrame(
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

    assert(
        envelope.value.data.data[
            $ - 1
        ] ==
        0xE9
    );

    auto decoded =
        envelope.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description ==
        "Größe"
    );

    assert(
        decoded.value.link.url ==
        "https://example.test/\u00E9"
    );
}


/// URLs rejected by canonical planning never reach WXXX output.
unittest
{
    const field =
        userUrlField(
            "homepage",
            "https://example.test/\u20AC"
        );

    auto serialized =
        serializeNewId3v24UserUrlFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated WXXX frames retain allowed alteration status bits.
unittest
{
    const field =
        userUrlField(
            "homepage",
            "new"
        );

    const formatPlan =
        writableFormatPlan(
            0x60
        );

    auto serialized =
        serializeRegeneratedId3v24UserUrlFrame(
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

    assert(
        envelope.value.header.statusFlags ==
        0x60
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    auto decoded =
        envelope.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description ==
        "homepage"
    );

    assert(
        decoded.value.link.url ==
        "new"
    );
}


/// Grouping and DLI precede the regenerated WXXX semantic payload.
unittest
{
    const field =
        userUrlField(
            "key",
            "abc"
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
        serializeRegeneratedId3v24UserUrlFrame(
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
     * Semantic WXXX payload:
     *
     *   03 'k' 'e' 'y' 00 'a' 'b' 'c'
     *
     * = eight bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + DLI 4 + semantic payload 8 = 13.
     */
    assert(envelope.value.header.size == 13);

    assert(
        envelope.value.header.formatFlags ==
        0x41
    );

    assert(
        envelope.value.data.data ==
        [
            0x33,
            0x00, 0x00, 0x00, 0x08,
            0x03,
            'k', 'e', 'y',
            0x00,
            'a', 'b', 'c'
        ]
    );

    auto decoded =
        envelope.value.decodeId3v24UserUrlFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.link.description ==
        "key"
    );

    assert(
        decoded.value.link.url ==
        "abc"
    );
}


/// Contradictory grouping information is rejected defensively.
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
            0x40,
            false,
            0,
            false
        );

    auto serialized =
        serializeRegeneratedId3v24UserUrlFrame(
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


/// Non-writable regeneration plans cannot produce modified WXXX bytes.
unittest
{
    const field =
        userUrlField(
            "key",
            "value"
        );

    Id3v24MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v24UserUrlFrame(
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


/// The WXXX writer rejects canonical fields targeting another URL family.
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
        serializeRegeneratedId3v24UserUrlFrame(
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
