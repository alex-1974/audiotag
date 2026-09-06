/++
Complete serialization of newly introduced canonical ID3v2.4 ordinary
text-information frames.

Supported canonical targets are currently:

- `title`  -> TIT2
- `artist` -> TPE1
- `album`  -> TALB

This module combines the already separated writer layers:

    canonical field
        -> canonical target / representability plan
        -> UTF-8 text-information payload
        -> fixed ID3v2.4 frame header
        -> complete native frame bytes

New frames use zero status and format flags. Preservation or deliberate
regeneration of structural flags from an existing native frame belongs
to the later existing-frame regeneration layer.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v24.text_information_frame_write;

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
    MetadataText,
    MetadataTextList;

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

import audiotag.id3v2.v24.text_information_write :
    serializeId3v24Utf8TextInformationPayload;


/++
Serializes the text-information payload contained in one canonical
field.

The caller must already have established that the field targets the
ordinary ID3v2.4 text-information family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalTextInformationPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text)
        {
            const(string)[] values =
                [text.value];

            return
                serializeId3v24Utf8TextInformationPayload(
                    values
                );
        },

        (const(MetadataTextList) list) =>
            serializeId3v24Utf8TextInformationPayload(
                list.values
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
Serializes one newly introduced canonical ordinary text-information
field as a complete ID3v2.4 frame.

The canonical planner is consulted first, so this function never
silently discards unsupported language, description, qualifier, value
shape or text-payload information.

New native frames deliberately use:

    statusFlags = 0
    formatFlags = 0

because there is no source-native frame whose structural flags need to
be preserved.

Params:
    field = Canonical `title`, `artist` or `album` field.

Returns:
    Complete owned frame bytes, including the ten-byte ID3v2.4 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24TextInformationFrame(
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
            .textInformation
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
        serializeCanonicalTextInformationPayload(
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
     * Canonical target definitions are static writer registry data.
     * A non-four-byte ID here is therefore a programmer/registry bug.
     */
    assert(
        plan.target.frameId.length ==
        4
    );

    /*
     * Successful text-payload serialization already guarantees the
     * ID3v2.4 28-bit frame-size limit.
     */
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
Serializes modified canonical ordinary text information as a regenerated
existing ID3v2.4 frame.

Unlike `serializeNewId3v24TextInformationFrame`, this function receives
an already validated structural regeneration plan derived from the
source-native frame.

The format plan controls:

- preserved tag/file alteration status flags;
- preserved grouping identity and logical grouping byte;
- recomputed Data Length Indicator presence;
- cleared frame-level unsynchronisation;
- rejection of unsupported compression/encryption/read-only cases.

The Data Length Indicator is recomputed from the new semantic payload
length. Optional grouping and DLI bytes themselves contribute to the
new frame-header size.

Params:
    field = Replacement canonical `title`, `artist` or `album`.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24TextInformationFrame(
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
     * A publicly supplied plan must still be structurally self-consistent.
     * The regeneration-policy producer currently emits only status bits
     * 0x40/0x20 and format bits grouping/DLI.
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
            .textInformation
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
        serializeCanonicalTextInformationPayload(
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

    enum size_t maximumFrameDataSize =
        0x0FFF_FFFF;

    size_t prefixLength;

    if (formatPlan.hasGroupingIdentity)
        ++prefixLength;

    if (formatPlan.hasDataLengthIndicator)
        prefixLength += 4;

    /*
     * Payload serialization already guarantees payload.length <= max.
     * Optional frame-format fields may nevertheless push the complete
     * frame-data size beyond the synchsafe header-size domain.
     */
    if (
        payload.value.length >
        maximumFrameDataSize - prefixLength
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

    /*
     * A successful text payload always contains at least its encoding
     * marker, so the resulting frame-data size is non-zero.
     */
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
         * Compression and encryption are rejected by the regeneration
         * policy. With those transformations absent, the DLI describes
         * the size of the regenerated semantic frame payload when the
         * frame-format flags are conceptually zero.
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
        MetadataKey,
        MetadataLanguage;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.frame_data :
        parseId3v24FrameDataLayout;


    import audiotag.id3v2.v24.regeneration_policy :
        Id3v24MappedFrameRegenerationStatus,
        planId3v24MappedFrameRegenerationFormat;

    import audiotag.id3v2.v24.text_encoding :
        Id3v24TextEncoding;

    import audiotag.id3v2.v24.text_information :
        decodeId3v24TextInformationFrame;


    private Id3v24MappedFrameRegenerationFormatPlan
    regenerationPlanFromSource(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto envelope =
            cursor.parseId3v24FrameEnvelope();

        assert(envelope.hasValue);
        assert(cursor.empty);

        auto planned =
            planId3v24MappedFrameRegenerationFormat(
                envelope.value
            );

        assert(planned.hasValue);

        return planned.value;
    }


    private MetadataField textField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataText(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField textListField(
        string key,
        string[] values
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataTextList(values);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }
}


/// Plain existing text frames regenerate with new semantic content.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x03,
            'O', 'l', 'd'
        ];

    const formatPlan =
        regenerationPlanFromSource(
            sourceBytes
        );

    const replacement =
        textField(
            "title",
            "New"
        );

    auto encoded =
        serializeRegeneratedId3v24TextInformationFrame(
            replacement,
            formatPlan
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                100
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "TIT2"
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.values ==
        ["New"]
    );
}


/// Tag/file preservation status bits survive text-frame regeneration.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x60, 0x00,

            0x03, 'X'
        ];

    const formatPlan =
        regenerationPlanFromSource(
            sourceBytes
        );

    const replacement =
        textField(
            "title",
            "Y"
        );

    auto encoded =
        serializeRegeneratedId3v24TextInformationFrame(
            replacement,
            formatPlan
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[]
            )
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
        0x00
    );
}


/// Grouping identity is physically retained before regenerated text.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x40,

            0x2A,
            0x03, 'X'
        ];

    const formatPlan =
        regenerationPlanFromSource(
            sourceBytes
        );

    const replacement =
        textField(
            "title",
            "New"
        );

    auto encoded =
        serializeRegeneratedId3v24TextInformationFrame(
            replacement,
            formatPlan
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                200
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    assert(
        envelope.value.header.formatFlags ==
        0x40
    );

    auto layout =
        envelope.value
            .parseId3v24FrameDataLayout();

    assert(layout.hasValue);
    assert(layout.value.hasGroupingIdentity);

    assert(
        layout.value.groupingIdentity ==
        0x2A
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["New"]
    );
}


/// DLI presence is preserved and its value is recomputed for new text.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x01,

            // Old semantic payload length = 2.
            0x00, 0x00, 0x00, 0x02,

            0x03, 'X'
        ];

    const formatPlan =
        regenerationPlanFromSource(
            sourceBytes
        );

    const replacement =
        textField(
            "title",
            "Long"
        );

    auto encoded =
        serializeRegeneratedId3v24TextInformationFrame(
            replacement,
            formatPlan
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                300
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    /*
     * New frame data:
     *   four-byte DLI + UTF-8 marker + "Long"
     * = 4 + 5 = 9 bytes.
     */
    assert(
        envelope.value.header.size ==
        9
    );

    assert(
        envelope.value.header.formatFlags ==
        0x01
    );

    auto layout =
        envelope.value
            .parseId3v24FrameDataLayout();

    assert(layout.hasValue);
    assert(layout.value.hasDataLengthIndicator);

    // New semantic payload = marker + "Long" = 5 bytes.
    assert(
        layout.value.dataLengthIndicator ==
        5
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["Long"]
    );
}


/// Grouping precedes a recomputed DLI in regenerated frame data.
unittest
{
    const ubyte[] sourceBytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x41,

            0x33,

            // Old semantic payload length = 2.
            0x00, 0x00, 0x00, 0x02,

            0x03, 'X'
        ];

    const formatPlan =
        regenerationPlanFromSource(
            sourceBytes
        );

    const replacement =
        textListField(
            "artist",
            ["A", "B"]
        );

    auto encoded =
        serializeRegeneratedId3v24TextInformationFrame(
            replacement,
            formatPlan
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                400
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    assert(
        envelope.value.header.formatFlags ==
        0x41
    );

    auto layout =
        envelope.value
            .parseId3v24FrameDataLayout();

    assert(layout.hasValue);

    assert(layout.value.hasGroupingIdentity);
    assert(layout.value.groupingIdentity == 0x33);

    assert(layout.value.hasDataLengthIndicator);

    /*
     * UTF-8 marker + "A" + separator + "B"
     * = 4 semantic bytes.
     */
    assert(
        layout.value.dataLengthIndicator ==
        4
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);

    assert(
        decoded.value.text.values ==
        ["A", "B"]
    );
}


/// Non-writable structural plans cannot reach regenerated byte output.
unittest
{
    Id3v24MappedFrameRegenerationFormatPlan formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .compressionUnsupported;

    const replacement =
        textField(
            "title",
            "New"
        );

    auto encoded =
        serializeRegeneratedId3v24TextInformationFrame(
            replacement,
            formatPlan
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// A canonical title becomes one exact UTF-8 TIT2 frame.
unittest
{
    const field =
        textField(
            "title",
            "Title"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'T', 'i', 't', 'l', 'e'
        ]
    );
}


/// An ordered canonical artist list becomes one null-separated TPE1.
unittest
{
    const field =
        textListField(
            "artist",
            [
                "Artist A",
                "Artist B"
            ]
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                100
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "TPE1"
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
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.encoding ==
        Id3v24TextEncoding.utf8
    );

    assert(
        decoded.value.text.values.length ==
        2
    );

    assert(
        decoded.value.text.values[0] ==
        "Artist A"
    );

    assert(
        decoded.value.text.values[1] ==
        "Artist B"
    );
}


/// Album Unicode survives complete write then strict read.
unittest
{
    const field =
        textField(
            "album",
            "Grüße"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                500
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    assert(
        envelope.value.header.id[] ==
        "TALB"
    );

    auto decoded =
        envelope.value
            .decodeId3v24TextInformationFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.text.values.length ==
        1
    );

    assert(
        decoded.value.text.values[0] ==
        "Grüße"
    );
}


/// Parser provenance comes from the newly serialized byte location.
unittest
{
    const field =
        textField(
            "title",
            "X"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasValue);

    auto cursor =
        ByteCursor(
            ByteSpan(
                encoded.value[],
                1234
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    assert(
        envelope.value.header.sourceOffset ==
        1234
    );

    assert(
        envelope.value.data.sourceOffset ==
        1244
    );
}


/// Canonical context unsupported by TIT2 is rejected before byte output.
unittest
{
    auto field =
        textField(
            "title",
            "Title"
        );

    field.description =
        "not-representable-in-TIT2";

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded NUL remains rejected through the complete frame API.
unittest
{
    const field =
        textField(
            "title",
            "A\0B"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Empty artist lists never become ambiguous or empty native TPE1 frames.
unittest
{
    const field =
        textListField(
            "artist",
            []
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Other canonical serializer families cannot enter this writer.
unittest
{
    auto field =
        textField(
            "comment",
            "Comment"
        );

    field.language =
        MetadataLanguage(
            "eng"
        );

    auto encoded =
        serializeNewId3v24TextInformationFrame(
            field
        );

    assert(encoded.hasError);

    assert(
        encoded.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
