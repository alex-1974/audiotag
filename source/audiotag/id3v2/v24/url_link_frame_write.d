/++
Complete serialization of canonical ordinary ID3v2.4 URL-link frames.

Supported native frame family:

    W***

excluding `WXXX`, which has a different native payload structure.

This module combines:

    canonical MetadataUrl
        -> canonical target / representability plan
        -> ISO-8859-1 URL-link payload
        -> fixed ID3v2.4 frame header
        -> complete native frame bytes

New frames use zero status and format flags.

Regenerated existing frames use the already established mapped-frame
regeneration policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected by the policy;
- grouping identity is preserved;
- compression and encryption remain unsupported;
- frame-level unsynchronisation is cleared;
- DLI presence is preserved and its value recomputed from the new
  semantic URL payload.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v24.url_link_frame_write;

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

import audiotag.id3v2.v24.url_link_write :
    serializeId3v24UrlLinkPayload;


/++
Serializes the ordinary URL-link payload contained in one canonical
field.

The caller must already have established that the field targets the
ordinary ID3v2.4 `urlLink` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalUrlLinkPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataUrl) url) =>
            serializeId3v24UrlLinkPayload(
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
complete ID3v2.4 W*** frame.

The canonical planner is consulted first. Consequently unsupported
context, invalid value shape and URLs that cannot be represented
losslessly as ISO-8859-1 never reach physical output.

New native frames deliberately use:

    statusFlags = 0
    formatFlags = 0

because there is no source-native frame whose structural properties must
be retained.

Params:
    field = Canonical ordinary URL field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.4 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24UrlLinkFrame(
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
     * Successful URL payload serialization guarantees a non-zero payload
     * and the ID3v2.4 28-bit frame-data size limit.
     */
    assert(payload.value.length != 0);

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
Serializes modified canonical ordinary URL metadata as a regenerated
existing ID3v2.4 W*** frame.

The supplied structural regeneration plan controls preservation of
status flags and grouping identity and whether a recomputed DLI must be
emitted.

The DLI describes the new semantic URL payload length. Grouping and DLI
bytes themselves contribute to the resulting frame-header size but not
to the DLI value.

Params:
    field = Replacement canonical ordinary URL field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24UrlLinkFrame(
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
     * Publicly supplied structural plans are validated defensively.
     *
     * Current regeneration policy permits only:
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
        Id3v24CanonicalTargetFamily
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
        /*
         * Compression and encryption are absent in every writable current
         * regeneration plan. Therefore the DLI is simply the new logical
         * semantic URL payload length.
         */
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


/// A new ordinary URL field becomes a complete WCOM frame.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "https://example.test/"
        );

    auto serialized =
        serializeNewId3v24UrlLinkFrame(
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
        serializeNewId3v24UrlLinkFrame(
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


/// Empty canonical URLs use the codec's one-byte native representation.
unittest
{
    const field =
        urlField(
            "publisherUrl",
            ""
        );

    auto serialized =
        serializeNewId3v24UrlLinkFrame(
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
        envelope.value.header.id[] ==
        "WPUB"
    );

    assert(envelope.value.header.size == 1);

    assert(
        envelope.value.data.data ==
        [0x00]
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
        serializeNewId3v24UrlLinkFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Plain regenerated URL frames retain allowed alteration status bits.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    const formatPlan =
        writableFormatPlan(
            0x60
        );

    auto serialized =
        serializeRegeneratedId3v24UrlLinkFrame(
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
        envelope.value.header.id[] ==
        "WCOM"
    );

    assert(
        envelope.value.header.statusFlags ==
        0x60
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    assert(
        envelope.value.data.data ==
        cast(const(ubyte)[]) "abc"
    );
}


/// Grouping precedes a recomputed DLI and the URL semantic payload.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    const formatPlan =
        writableFormatPlan(
            0x20,
            0x41,
            true,
            0x33,
            true
        );

    auto serialized =
        serializeRegeneratedId3v24UrlLinkFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Frame data:
     *
     *   1 byte grouping
     *   4 bytes DLI
     *   3 bytes URL
     *
     * total = 8.
     */
    assert(
        serialized.value[4 .. 8] ==
        [0x00, 0x00, 0x00, 0x08]
    );

    assert(serialized.value[8] == 0x20);
    assert(serialized.value[9] == 0x41);

    assert(serialized.value[10] == 0x33);

    assert(
        serialized.value[11 .. 15] ==
        [0x00, 0x00, 0x00, 0x03]
    );

    assert(
        serialized.value[15 .. $] ==
        cast(const(ubyte)[]) "abc"
    );

    auto cursor =
        ByteCursor(
            ByteSpan(serialized.value[])
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(envelope.value.header.size == 8);
    assert(envelope.value.header.hasGroupingIdentity);
    assert(envelope.value.header.hasDataLengthIndicator);
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
            0x40,
            false,
            0,
            false
        );

    auto serialized =
        serializeRegeneratedId3v24UrlLinkFrame(
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


/// Non-writable regeneration plans cannot produce URL frame bytes.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "abc"
        );

    Id3v24MappedFrameRegenerationFormatPlan formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v24UrlLinkFrame(
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
