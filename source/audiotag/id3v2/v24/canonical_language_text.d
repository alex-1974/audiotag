/++
Canonical mapping for decoded ID3v2.4 language-qualified text frames.

This module currently maps:

- COMM -> comment
- USLT -> lyrics

The ID3 three-byte language field is preserved as the canonical language
tag without normalization. Language normalization is intentionally a
later mapping-policy concern.

The native description/descriptor is preserved in the canonical field's
description context.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation` rather than a parser error.
+/
module audiotag.id3v2.v24.canonical_language_text;

import std.sumtype :
    match;

import audiotag.id3v2.v24.canonical_mapping :
    Id3v24CanonicalMappingResult,
    Id3v24CanonicalMappingStatus;

import audiotag.id3v2.v24.comment :
    Id3v24CommentFrame,
    Id3v24CommentOutcome;

import audiotag.id3v2.v24.lyrics_text :
    Id3v24LyricsTextFrame,
    Id3v24LyricsTextOutcome;

import audiotag.id3v2.v24.native_frame :
    Id3v24NativeFrame;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey,
    MetadataLanguage;

import audiotag.metadata.provenance :
    MetadataConfidence,
    MetadataProvenance,
    MetadataSystem,
    NativeMetadataIdentifier;

import audiotag.metadata.registry :
    findMetadataFieldDefinition;

import audiotag.metadata.value :
    MetadataText,
    MetadataValue;


/++
Maps one decoded ID3v2.4 `COMM` frame to the canonical `comment` field.

The native three-byte language identifier and short description are
preserved as canonical field context.

Params:
    frame = Decoded native comment frame.
    sourceLength = Complete physical frame length when known. The
        default zero length represents point provenance only.

Returns:
    Canonical mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24CommentFrameToCanonical(
    Id3v24CommentFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return Id3v24CanonicalMappingResult.success(
        makeLanguageTextField(
            "comment",
            "COMM",
            frame.text,
            frame.language,
            frame.description,
            frame.sourceOffset,
            sourceLength
        )
    );
}


/++
Maps one decoded ID3v2.4 `USLT` frame to the canonical `lyrics` field.

The native three-byte language identifier and content descriptor are
preserved as canonical field context.

Params:
    frame = Decoded native unsynchronised-lyrics/text frame.
    sourceLength = Complete physical frame length when known. The
        default zero length represents point provenance only.

Returns:
    Canonical mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24LyricsTextFrameToCanonical(
    Id3v24LyricsTextFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return Id3v24CanonicalMappingResult.success(
        makeLanguageTextField(
            "lyrics",
            "USLT",
            frame.text,
            frame.language,
            frame.descriptor,
            frame.sourceOffset,
            sourceLength
        )
    );
}


/++
Maps one unified native ID3v2.4 frame through the language-qualified
text mapper.

Only `COMM` and `USLT` outcomes are handled by this module. Other native
frame families return `unsupportedFrame`.

Decoded `COMM` and `USLT` outcomes are mapped. Transformation-pending
outcomes return `requiresTransformation`.

Params:
    native = Unified native ID3v2.4 frame.

Returns:
    Canonical mapping result.
+/
Id3v24CanonicalMappingResult
mapId3v24NativeLanguageTextFrameToCanonical(
    Id3v24NativeFrame native
)
    @safe
{
    return native.content.match!(
        (Id3v24CommentOutcome outcome) =>
            outcome.decoded
                ? mapId3v24CommentFrameToCanonical(
                    outcome.comment,
                    native.sourceLength
                )
                : Id3v24CanonicalMappingResult
                    .transformationRequired(),

        (Id3v24LyricsTextOutcome outcome) =>
            outcome.decoded
                ? mapId3v24LyricsTextFrameToCanonical(
                    outcome.lyrics,
                    native.sourceLength
                )
                : Id3v24CanonicalMappingResult
                    .transformationRequired(),

        _ =>
            Id3v24CanonicalMappingResult.unsupported()
    );
}


/++
Constructs one canonical language-qualified text field.
+/
private MetadataField makeLanguageTextField(
    string canonicalKey,
    string nativeIdentifier,
    string value,
    const ref char[3] language,
    string description,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe
{
    auto languageTag =
        language[].idup;

    auto field =
        MetadataField(
            MetadataKey(canonicalKey),
            MetadataValue(
                MetadataText(value)
            ),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ],
            MetadataLanguage(languageTag),
            description
        );

    assertRegisteredShape(field);

    return field;
}


/++
Constructs exact canonical provenance for one mapped native frame.
+/
private MetadataProvenance makeProvenance(
    string nativeIdentifier,
    size_t sourceOffset,
    size_t sourceLength
)
    @safe pure nothrow @nogc
{
    return MetadataProvenance(
        NativeMetadataIdentifier(
            MetadataSystem.id3v2,
            nativeIdentifier
        ),
        sourceOffset,
        sourceLength,
        MetadataConfidence.exact
    );
}


/++
Checks the canonical mapper/registry contract as a programmer invariant.
+/
private void assertRegisteredShape(
    MetadataField field
)
    @safe
{
    auto definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);
    assert(
        definition.definition.accepts(
            field.value
        )
    );
}


/++
Constructs one decoded comment frame for mapping tests.
+/
private Id3v24CommentFrame testCommentFrame(
    string text,
    string description = "",
    string language = "eng",
    size_t sourceOffset = 100
)
    @safe
{
    assert(language.length == 3);

    Id3v24CommentFrame frame;

    frame.sourceOffset =
        sourceOffset;

    frame.language[] =
        language[];

    frame.description =
        description;

    frame.text =
        text;

    return frame;
}


/++
Constructs one decoded lyrics frame for mapping tests.
+/
private Id3v24LyricsTextFrame testLyricsFrame(
    string text,
    string descriptor = "",
    string language = "eng",
    size_t sourceOffset = 100
)
    @safe
{
    assert(language.length == 3);

    Id3v24LyricsTextFrame frame;

    frame.sourceOffset =
        sourceOffset;

    frame.language[] =
        language[];

    frame.descriptor =
        descriptor;

    frame.text =
        text;

    return frame;
}


/// COMM maps text, language and description without loss.
unittest
{
    auto result =
        mapId3v24CommentFrameToCanonical(
            testCommentFrame(
                "A comment",
                "short description",
                "deu",
                123
            )
        );

    assert(result.mapped);
    assert(
        result.field.key.name ==
        "comment"
    );

    assert(result.field.hasLanguage);
    assert(
        result.field.language.tag ==
        "deu"
    );

    assert(result.field.hasDescription);
    assert(
        result.field.description ==
        "short description"
    );

    assert(
        result.field.provenance.length ==
        1
    );

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "COMM"
    );

    assert(
        result.field.provenance[0]
            .sourceOffset ==
        123
    );

    assert(
        result.field.provenance[0]
            .sourceLength ==
        0
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "A comment",
            _ => false
        );

    assert(matches);
}


/// USLT maps lyrics text, language and descriptor without loss.
unittest
{
    auto result =
        mapId3v24LyricsTextFrameToCanonical(
            testLyricsFrame(
                "Lyrics body",
                "verse",
                "eng",
                321
            )
        );

    assert(result.mapped);
    assert(
        result.field.key.name ==
        "lyrics"
    );

    assert(result.field.hasLanguage);
    assert(
        result.field.language.tag ==
        "eng"
    );

    assert(result.field.hasDescription);
    assert(
        result.field.description ==
        "verse"
    );

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "USLT"
    );

    assert(
        result.field.provenance[0]
            .sourceOffset ==
        321
    );

    const matches =
        result.field.value.match!(
            (MetadataText text) =>
                text.value == "Lyrics body",
            _ => false
        );

    assert(matches);
}


/// Native COMM mapping records the complete physical frame extent.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',
            'd', 'e', 's', 'c', 0x00,
            'H', 'e', 'l', 'l', 'o'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeLanguageTextFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

    assert(
        mapped.field.key.name ==
        "comment"
    );

    assert(
        mapped.field.language.tag ==
        "eng"
    );

    assert(
        mapped.field.description ==
        "desc"
    );

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        700
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );
}


/// Native USLT mapping records the complete physical frame extent.
unittest
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        decodeId3v24NativeFrame;

    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x10,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',
            'v', 'e', 'r', 's', 'e', 0x00,
            'L', 'y', 'r', 'i', 'c', 's'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto envelope =
        cursor.parseId3v24FrameEnvelope();

    assert(envelope.hasValue);

    auto native =
        decodeId3v24NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v24NativeLanguageTextFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);

    assert(
        mapped.field.key.name ==
        "lyrics"
    );

    assert(
        mapped.field.language.tag ==
        "eng"
    );

    assert(
        mapped.field.description ==
        "verse"
    );

    assert(
        mapped.field.provenance[0]
            .sourceOffset ==
        900
    );

    assert(
        mapped.field.provenance[0]
            .sourceLength ==
        bytes.length
    );
}


/// Transformation-pending COMM remains valid native metadata.
unittest
{
    import audiotag.id3v2.v24.comment :
        Id3v24CommentAvailability;

    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent;

    Id3v24CommentOutcome outcome;

    outcome.availability =
        Id3v24CommentAvailability
            .requiresDecompression;

    Id3v24NativeFrameContent content =
        outcome;

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeLanguageTextFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families are unsupported by this mapper.
unittest
{
    import audiotag.id3v2.v24.frame :
        Id3v24FrameEnvelope;

    import audiotag.id3v2.v24.native_frame :
        Id3v24NativeFrameContent,
        Id3v24UnknownFrame;

    Id3v24NativeFrameContent content =
        Id3v24UnknownFrame();

    auto native =
        Id3v24NativeFrame(
            Id3v24FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v24NativeLanguageTextFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );
}
