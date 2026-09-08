/++
Complete serialization of canonical ID3v2.3 language-qualified text
frames.

The shared canonical family covers:

- `comment` -> `COMM`;
- `lyrics` -> `USLT`.

A canonical language-text field consists of:

- one scalar `MetadataText` value;
- mandatory canonical language context;
- optional canonical description context.

The semantic payload is delegated to `language_text_write` and has the
ID3v2.3 form:

    <encoding marker>
    <three-byte language>
    <description>
    <mandatory description terminator>
    <text>

Description and text share one deterministic ID3v2.3 encoding:

- ISO-8859-1 when both strings are representable there;
- otherwise strict UCS-2 with BOM;
- otherwise serialization fails.

The language identifier remains exactly three ASCII bytes and is not
affected by the text encoding.

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
module audiotag.id3v2.v23.language_text_frame_write;

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

import audiotag.id3v2.v23.language_text_write :
    serializeId3v23LanguageTextPayload;

import audiotag.id3v2.v23.new_frame_plan :
    planId3v23CanonicalField;

import audiotag.id3v2.v23.regeneration_policy :
    Id3v23MappedFrameRegenerationFormatPlan;


/++
Serializes the semantic payload represented by one canonical
language-text field.

The canonical planner must already have established that the field
targets the ID3v2.3 `languageText` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalLanguageTextPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text) =>
            serializeId3v23LanguageTextPayload(
                field.language.tag,
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
Serializes one newly introduced canonical language-text field as a
complete ID3v2.3 `COMM` or `USLT` frame.

Canonical planning is consulted before physical serialization, so
missing language context, unsupported context, invalid value shape and
unrepresentable payloads cannot silently reach output.

New frames use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `comment` or `lyrics` field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.3 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v23LanguageTextFrame(
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
        Id3v23CanonicalTargetFamily.languageText
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
        serializeCanonicalLanguageTextPayload(
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
        plan.target.frameId == "COMM" ||
        plan.target.frameId == "USLT"
    );

    /*
     * Every successful v2.3 language-text payload contains at least:
     *
     * encoding marker 1
     * language        3
     * descriptor NUL  1
     */
    assert(payload.value.length >= 5);

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
Serializes modified canonical language-text metadata as a regenerated
existing ID3v2.3 `COMM` or `USLT` frame.

The structural regeneration plan controls preservation of alteration
flags and optional grouping identity.

Params:
    field = Replacement canonical `comment` or `lyrics` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v23LanguageTextFrame(
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
        Id3v23CanonicalTargetFamily.languageText
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
        serializeCanonicalLanguageTextPayload(
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
        canonicalPlan.target.frameId == "COMM" ||
        canonicalPlan.target.frameId == "USLT"
    );

    assert(payload.value.length >= 5);

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
        MetadataLanguage;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.regeneration_policy :
        Id3v23MappedFrameRegenerationStatus;


    private MetadataField
    languageTextField(
        string key,
        string language,
        string description,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataText(value);

        auto result =
            MetadataField(
                MetadataKey(key),
                wrapped
            );

        result.language =
            MetadataLanguage(language);

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


/// A canonical comment becomes a complete Latin-1 COMM frame.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "note",
            "hello\nworld"
        );

    auto serialized =
        serializeNewId3v23LanguageTextFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x14,
            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            'n', 'o', 't', 'e',
            0x00,
            'h', 'e', 'l', 'l', 'o',
            0x0A,
            'w', 'o', 'r', 'l', 'd'
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
        "COMM"
    );

    assert(
        envelope.value.header.size ==
        20
    );
}


/// Canonical lyrics select the USLT target of the same physical family.
unittest
{
    const field =
        languageTextField(
            "lyrics",
            "eng",
            "lyrics",
            "line1\nline2"
        );

    auto serialized =
        serializeNewId3v23LanguageTextFrame(
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
        "USLT"
    );

    assert(
        envelope.value.header.size ==
        22
    );

    assert(
        envelope.value.data.data ==
        [
            0x00,
            'e', 'n', 'g',
            'l', 'y', 'r', 'i', 'c', 's',
            0x00,
            'l', 'i', 'n', 'e', '1',
            0x0A,
            'l', 'i', 'n', 'e', '2'
        ]
    );
}


/// Empty description and text retain the minimal valid COMM payload.
unittest
{
    const field =
        languageTextField(
            "comment",
            "deu",
            "",
            ""
        );

    auto serialized =
        serializeNewId3v23LanguageTextFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x00,
            'd', 'e', 'u',
            0x00
        ]
    );
}


/// Wider BMP description and text use the deterministic UCS-2 payload.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "\u03A9",
            "\u0416"
        );

    auto serialized =
        serializeNewId3v23LanguageTextFrame(
            field
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00,

            0xFE, 0xFF,
            0x04, 0x16
        ]
    );
}


/// Missing mandatory language context never reaches physical output.
unittest
{
    MetadataValue wrapped =
        MetadataText("comment");

    const field =
        MetadataField(
            MetadataKey("comment"),
            wrapped
        );

    auto serialized =
        serializeNewId3v23LanguageTextFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Payload constraints diagnosed by planning prevent COMM output.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "note",
            "a\0b"
        );

    auto serialized =
        serializeNewId3v23LanguageTextFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated COMM frames preserve allowed alteration-status bits.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "note",
            "new"
        );

    const formatPlan =
        writableFormatPlan(
            0xC0
        );

    auto serialized =
        serializeRegeneratedId3v23LanguageTextFrame(
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
        "COMM"
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


/// Grouping identity precedes a regenerated USLT semantic payload.
unittest
{
    const field =
        languageTextField(
            "lyrics",
            "eng",
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
        serializeRegeneratedId3v23LanguageTextFrame(
            field,
            formatPlan
        );

    assert(serialized.hasValue);

    /*
     * Semantic language-text payload:
     *
     *   00 'e' 'n' 'g' 'k' 'e' 'y' 00 'a' 'b' 'c'
     *
     * = eleven bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + semantic payload 11 = 12.
     */
    assert(
        serialized.value ==
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0C,
            0x40, 0x20,

            0x33,

            0x00,
            'e', 'n', 'g',
            'k', 'e', 'y',
            0x00,
            'a', 'b', 'c'
        ]
    );
}


/// Contradictory grouping state is rejected defensively.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "note",
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
        serializeRegeneratedId3v23LanguageTextFrame(
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
        languageTextField(
            "comment",
            "eng",
            "note",
            "value"
        );

    const formatPlan =
        writableFormatPlan(
            0,
            0x80
        );

    auto serialized =
        serializeRegeneratedId3v23LanguageTextFrame(
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


/// Non-writable regeneration plans cannot produce language-text bytes.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "note",
            "value"
        );

    Id3v23MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v23MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v23LanguageTextFrame(
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


/// The language-text writer rejects fields targeting another family.
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
        serializeRegeneratedId3v23LanguageTextFrame(
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
