/++
Complete serialization of canonical ordinary ID3v2.3 URL-link frames.

Supported native frame family:

    W***

excluding `WXXX`, which has a different native payload structure.

This module combines:

    canonical MetadataUrl
        -> canonical target / representability plan
        -> ISO-8859-1 URL-link payload
        -> fixed ID3v2.3 frame header
        -> complete native frame bytes

New frames use zero status and format flags.

Regenerated existing frames use the established ID3v2.3 mapped-frame
regeneration policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported.

ID3v2.3 has no frame-level unsynchronisation or Data Length Indicator.
Whole-tag unsynchronisation remains a later tag-serialization concern.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v23.url_link_frame_write;

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

import audiotag.id3v2.v23.url_link_write :
    serializeId3v23UrlLinkPayload;


/++
Serializes the ordinary URL-link payload contained in one canonical
field.

The caller must already have established that the field targets the
ordinary ID3v2.3 `urlLink` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalUrlLinkPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataUrl) url) =>
            serializeId3v23UrlLinkPayload(
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
Serializes one newly introduced canonical ordinary URL field as a
complete ID3v2.3 W*** frame.

The canonical planner is consulted first. Unsupported context, invalid
value shape and URLs that cannot be represented losslessly as
ISO-8859-1 therefore never reach physical output.

New frames deliberately use:

    statusFlags = 0
    formatFlags = 0

because there is no source-native frame whose structural properties
must be retained.

Params:
    field = Canonical ordinary URL field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23UrlLinkFrame(
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
            .urlLink
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
        serializeCanonicalUrlLinkPayload(
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

    /*
     * Canonical target definitions are static registry data.
     */
    assert(
        plan.target.frameId.length ==
        4
    );

    /*
     * Successful v2.3 URL payload serialization guarantees a non-zero
     * payload inside the complete uint frame-data domain.
     */
    assert(payload.value.length != 0);

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
Serializes modified canonical ordinary URL metadata as a regenerated
existing ID3v2.3 W*** frame.

The supplied structural regeneration plan controls preservation of
status flags and optional grouping identity.

Params:
    field = Replacement canonical ordinary URL field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23UrlLinkFrame(
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
     * Writable current v2.3 regeneration plans may contain only:
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
        Id3v23CanonicalTargetFamily
            .urlLink
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
        serializeCanonicalUrlLinkPayload(
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
        canonicalPlan.target.frameId.length ==
        4
    );

    assert(payload.value.length != 0);

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


    private MetadataField urlField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataUrl(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
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


/// A new ordinary URL field becomes a complete WCOM frame.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "https://example.test/"
        );

    auto serialized =
        serializeNewId3v23UrlLinkFrame(
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
        "WCOM"
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
        "https://example.test/".length
    );

    assert(
        envelope.value.data.data ==
        cast(const(ubyte)[])
            "https://example.test/"
    );
}


/// ISO-8859-1 URL scalars are emitted as their native single byte.
unittest
{
    const field =
        urlField(
            "artistUrl",
            "https://example.test/\u00E9"
        );

    auto serialized =
        serializeNewId3v23UrlLinkFrame(
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

    assert(
        envelope.value.header.id[] ==
        "WOAR"
    );

    assert(
        envelope.value.data.data[
            $ - 1
        ] ==
        0xE9
    );
}


/// Empty canonical URLs retain the codec's one-byte native representation.
unittest
{
    const field =
        urlField(
            "publisherUrl",
            ""
        );

    auto serialized =
        serializeNewId3v23UrlLinkFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'P', 'U', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x00
        ]
    );
}


/// Payloads rejected by the canonical planner never reach frame output.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "https://example.test/\u20AC"
        );

    auto serialized =
        serializeNewId3v23UrlLinkFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated URL frames retain the two alteration-status bits.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    const formatPlan =
        writableFormatPlan(
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23UrlLinkFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'W', 'C', 'O', 'M',
            0x00, 0x00, 0x00, 0x03,
            0xC0, 0x00,
            'a', 'b', 'c'
        ]
    );
}


/// Preserved grouping precedes the regenerated semantic URL payload.
unittest
{
    const field =
        urlField(
            "commercialUrl",
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
        serializeRegeneratedId3v23UrlLinkFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Frame data:
     *
     *   1 byte grouping
     *   3 bytes URL
     *
     * total = 4.
     */
    assert(
        serialized.value ==
        [
            'W', 'C', 'O', 'M',
            0x00, 0x00, 0x00, 0x04,
            0x40, 0x20,
            0x33,
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

    assert(envelope.value.header.size == 4);
    assert(envelope.value.header.hasGroupingIdentity);
}


/// Contradictory grouping flag state is rejected defensively.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x20,
            false,
            0
        );

    auto serialized =
        serializeRegeneratedId3v23UrlLinkFrame(
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


/// Unsupported writable-format flags are rejected defensively.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23UrlLinkFrame(
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


/// Non-writable regeneration plans cannot produce URL frame bytes.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    Id3v23MappedFrameRegenerationFormatPlan formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23UrlLinkFrame(
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
