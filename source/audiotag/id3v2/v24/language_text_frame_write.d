/++
Complete serialization of canonical ID3v2.4 language-text frames.

The shared canonical family currently covers:

- `comment` -> `COMM`;
- `lyrics` -> `USLT`.

A canonical language-text field consists of:

- one scalar `MetadataText` value;
- mandatory canonical language context;
- optional canonical field description context.

The physical payload is produced deterministically as UTF-8:

    $03 <3-byte language> <description UTF-8> $00 <text UTF-8>

New frames use zero status and format flags.

Regenerated existing frames use the established mapped-frame
regeneration policy:

- tag/file alteration status flags are preserved;
- read-only frames are rejected;
- grouping identity is preserved;
- compression and encryption remain unsupported;
- frame-level unsynchronisation is cleared;
- DLI presence is preserved and its value recomputed from the new
  semantic language-text payload.

No tag header, padding or container update is performed here.
+/
module audiotag.id3v2.v24.language_text_frame_write;

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
    MetadataText;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetFamily;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;

import audiotag.id3v2.v24.frame_header_write :
    serializeId3v24FrameHeader;

import audiotag.id3v2.v24.language_text_write :
    serializeId3v24Utf8LanguageTextPayload;

import audiotag.id3v2.v24.new_frame_plan :
    planId3v24CanonicalField;

import audiotag.id3v2.v24.regeneration_policy :
    Id3v24MappedFrameRegenerationFormatPlan;


/++
Serializes the payload represented by one canonical language-text
field.

The canonical planner must already have established that this field
targets the `languageText` family.
+/
private SerializationResult!(ubyte[])
serializeCanonicalLanguageTextPayload(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text) =>
            serializeId3v24Utf8LanguageTextPayload(
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
complete ID3v2.4 `COMM` or `USLT` frame.

The canonical planner is consulted first, so unsupported context,
invalid value shape and unrepresentable payloads cannot silently reach
physical output.

New frames deliberately use:

    statusFlags = 0
    formatFlags = 0

Params:
    field = Canonical `comment` or `lyrics` field.

Returns:
    Complete owned frame bytes including the ten-byte ID3v2.4 frame
    header, or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeNewId3v24LanguageTextFrame(
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
        Id3v24CanonicalTargetFamily.languageText
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
     * Every successful language-text payload contains at least:
     *
     * encoding marker 1
     * language        3
     * descriptor NUL  1
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
Serializes modified canonical language-text metadata as a regenerated
existing ID3v2.4 `COMM` or `USLT` frame.

The structural regeneration plan controls preservation of alteration
flags, grouping identity and DLI presence.

The Data Length Indicator describes the regenerated semantic
language-text payload length. Grouping and DLI bytes contribute to the
physical frame-data size but are not included in the DLI value.

Params:
    field = Replacement canonical `comment` or `lyrics` field.
    formatPlan = Structural regeneration plan derived from the original
        mapped native frame.

Returns:
    Complete regenerated native frame bytes or a structured
    serialization failure.
+/
SerializationResult!(ubyte[])
serializeRegeneratedId3v24LanguageTextFrame(
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
        Id3v24CanonicalTargetFamily.languageText
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
        MetadataLanguage;

    import audiotag.metadata.value :
        MetadataValue;

    import audiotag.id3v2.v24.comment :
        decodeId3v24CommentFrame;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.lyrics_text :
        decodeId3v24LyricsTextFrame;

    import audiotag.id3v2.v24.regeneration_policy :
        Id3v24MappedFrameRegenerationStatus;


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


/// A canonical comment field becomes a complete COMM frame.
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
        serializeNewId3v24LanguageTextFrame(
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
        "COMM"
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
        envelope.value.decodeId3v24CommentFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.comment.language[] ==
        "eng"
    );

    assert(
        decoded.value.comment.description ==
        "note"
    );

    assert(
        decoded.value.comment.text ==
        "hello\nworld"
    );
}


/// A canonical lyrics field becomes a complete USLT frame.
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
        serializeNewId3v24LanguageTextFrame(
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
        "USLT"
    );

    auto decoded =
        envelope.value.decodeId3v24LyricsTextFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.lyrics.language[] ==
        "eng"
    );

    assert(
        decoded.value.lyrics.descriptor ==
        "lyrics"
    );

    assert(
        decoded.value.lyrics.text ==
        "line1\nline2"
    );
}


/// Empty description and text retain a valid minimal COMM payload.
unittest
{
    const field =
        languageTextField(
            "comment",
            "eng",
            "",
            ""
        );

    auto serialized =
        serializeNewId3v24LanguageTextFrame(
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
        5
    );

    assert(
        envelope.value.data.data ==
        [
            0x03,
            'e', 'n', 'g',
            0x00
        ]
    );

    auto decoded =
        envelope.value.decodeId3v24CommentFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.comment.description.length ==
        0
    );

    assert(
        decoded.value.comment.text.length ==
        0
    );
}


/// UTF-8 language-text content survives complete serialization.
unittest
{
    const field =
        languageTextField(
            "comment",
            "deu",
            "Größe",
            "Grüße"
        );

    auto serialized =
        serializeNewId3v24LanguageTextFrame(
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

    auto decoded =
        envelope.value.decodeId3v24CommentFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.comment.language[] ==
        "deu"
    );

    assert(
        decoded.value.comment.description ==
        "Größe"
    );

    assert(
        decoded.value.comment.text ==
        "Grüße"
    );
}


/// Payloads rejected by canonical planning never reach frame output.
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
        serializeNewId3v24LanguageTextFrame(
            field
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Regenerated COMM frames preserve allowed alteration status bits.
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
            0x60
        );

    auto serialized =
        serializeRegeneratedId3v24LanguageTextFrame(
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
        "COMM"
    );

    assert(
        envelope.value.header.statusFlags ==
        0x60
    );

    assert(
        envelope.value.header.formatFlags ==
        0
    );

    auto decoded =
        envelope.value.decodeId3v24CommentFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.comment.text ==
        "new"
    );
}


/// Grouping and DLI precede a regenerated USLT semantic payload.
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
            0,
            0x41,
            true,
            0x33,
            true
        );

    auto serialized =
        serializeRegeneratedId3v24LanguageTextFrame(
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
     * Semantic language-text payload:
     *
     *   03 'e' 'n' 'g' 'k' 'e' 'y' 00 'a' 'b' 'c'
     *
     * = eleven bytes.
     *
     * Physical frame data:
     *
     *   grouping 1 + DLI 4 + semantic payload 11 = 16.
     */
    assert(envelope.value.header.size == 16);

    assert(
        envelope.value.header.formatFlags ==
        0x41
    );

    assert(
        envelope.value.data.data ==
        [
            0x33,
            0x00, 0x00, 0x00, 0x0B,
            0x03,
            'e', 'n', 'g',
            'k', 'e', 'y',
            0x00,
            'a', 'b', 'c'
        ]
    );

    auto decoded =
        envelope.value.decodeId3v24LyricsTextFrame();

    assert(decoded.hasValue);
    assert(decoded.value.decoded);

    assert(
        decoded.value.lyrics.language[] ==
        "eng"
    );

    assert(
        decoded.value.lyrics.descriptor ==
        "key"
    );

    assert(
        decoded.value.lyrics.text ==
        "abc"
    );
}


/// Contradictory grouping information is rejected defensively.
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
            0x40,
            false,
            0,
            false
        );

    auto serialized =
        serializeRegeneratedId3v24LanguageTextFrame(
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

    Id3v24MappedFrameRegenerationFormatPlan
        formatPlan;

    formatPlan.status =
        Id3v24MappedFrameRegenerationStatus
            .readOnly;

    auto serialized =
        serializeRegeneratedId3v24LanguageTextFrame(
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
        serializeRegeneratedId3v24LanguageTextFrame(
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
