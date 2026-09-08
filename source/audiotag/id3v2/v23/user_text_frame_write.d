/++
Complete serialization of canonical ID3v2.3 user-defined text (`TXXX`)
frames.

A canonical `userText` field consists of:

- one scalar `MetadataText` value;
- optional canonical description context.

The semantic ID3v2.3 payload is delegated to `user_text_write` and uses
one common deterministic text encoding for description and value:

    <encoding marker>
    <description>
    <mandatory description terminator>
    <value>

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
module audiotag.id3v2.v23.user_text_frame_write;

import std.sumtype :
    match;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.metadata.field :
    MetadataField;

import audiotag.metadata.value :
    MetadataText;

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

import audiotag.id3v2.v23.user_text_write :
    serializeId3v23UserTextPayload;


/++
Serializes the TXXX payload represented by one canonical `userText`
field.

The canonical planner must already have established that this field
targets the ID3v2.3 `userText` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalUserTextPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text) =>
            serializeId3v23UserTextPayload(
                field.description,
                text.value
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
Serializes one newly introduced canonical `userText` field as a complete
ID3v2.3 `TXXX` frame.

The canonical planner is consulted first, so unsupported context,
invalid value shape and unrepresentable TXXX payloads never silently
reach physical output.

New frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `userText` field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23UserTextFrame(
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
        Id3v23CanonicalTargetFamily.userText
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
        serializeCanonicalUserTextPayload(
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
        "TXXX"
    );

    /*
     * Every successful v2.3 TXXX payload contains at least the encoding
     * marker and the mandatory description terminator.
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
Serializes modified canonical `userText` metadata as a regenerated
existing ID3v2.3 `TXXX` frame.

The structural regeneration plan controls preservation of alteration
flags and optional grouping identity.

Params:
    field = Replacement canonical `userText` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23UserTextFrame(
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
        Id3v23CanonicalTargetFamily.userText
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
        serializeCanonicalUserTextPayload(
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
        "TXXX"
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
    userTextField(
        string description,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataText(value);

        auto result =
            MetadataField(
                MetadataKey("userText"),
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


/// A canonical user-text field becomes a complete Latin-1 TXXX frame.
unittest
{
    const field =
        userTextField(
            "key",
            "value"
        );

    auto serialized =
        serializeNewId3v23UserTextFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'v', 'a', 'l', 'u', 'e'
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
        "TXXX"
    );

    assert(
        envelope.value.header.size ==
        10
    );
}


/// Empty description and value retain the mandatory TXXX separator.
unittest
{
    const field =
        userTextField(
            "",
            ""
        );

    auto serialized =
        serializeNewId3v23UserTextFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 0x00
        ]
    );
}


/// Wider BMP text uses the deterministic ID3v2.3 UCS-2 representation.
unittest
{
    const field =
        userTextField(
            "\u03A9",
            "\u0416"
        );

    auto serialized =
        serializeNewId3v23UserTextFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x01,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00,

            0xFE, 0xFF,
            0x04, 0x16
        ]
    );
}


/// Payload constraints diagnosed by canonical planning prevent frame output.
unittest
{
    const field =
        userTextField(
            "key",
            "a\0b"
        );

    auto serialized =
        serializeNewId3v23UserTextFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated TXXX frames preserve allowed alteration-status bits.
unittest
{
    const field =
        userTextField(
            "key",
            "new"
        );

    const formatPlan =
        writableFormatPlan(
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23UserTextFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x08,
            0xC0, 0x00,

            0x00,
            'k', 'e', 'y',
            0x00,
            'n', 'e', 'w'
        ]
    );
}


/// Grouping identity precedes the regenerated TXXX semantic payload.
unittest
{
    const field =
        userTextField(
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
        serializeRegeneratedId3v23UserTextFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Semantic payload:
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
            'T', 'X', 'X', 'X',
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
        userTextField(
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
        serializeRegeneratedId3v23UserTextFrame(
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
        userTextField(
            "key",
            "value"
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23UserTextFrame(
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


/// Non-writable regeneration plans cannot produce modified TXXX bytes.
unittest
{
    const field =
        userTextField(
            "key",
            "value"
        );

    Id3v23MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23UserTextFrame(
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


/// The TXXX writer rejects canonical fields targeting another family.
unittest
{
    MetadataValue wrapped =
        MetadataText("Title");

    const field =
        MetadataField(
            MetadataKey("title"),
            wrapped
        );

    const formatPlan =
        writableFormatPlan();

    auto serialized =
        serializeRegeneratedId3v23UserTextFrame(
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
