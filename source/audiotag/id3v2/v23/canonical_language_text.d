/++
Canonical mapping for decoded ID3v2.3 language-qualified text frames.

This module currently maps:

- COMM -> comment
- USLT -> lyrics

The ID3 three-byte language field is preserved as the canonical language
tag without normalization. Language normalization is intentionally a
later mapping-policy concern.

The native description/descriptor is preserved in the canonical field's
description context.

ID3v2.3-specific Unicode decoding, including independent byte-order
marks for descriptor and text strings, is completed by the native codec
before this mapping layer is reached.

Transformation-pending native outcomes remain valid metadata and return
`requiresTransformation` rather than a parser error.
+/
module audiotag.id3v2.v23.canonical_language_text;

import std.sumtype :
    match;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult,
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.comment :
    Id3v23CommentFrame,
    Id3v23CommentOutcome;

import audiotag.id3v2.v23.lyrics_text :
    Id3v23LyricsTextFrame,
    Id3v23LyricsTextOutcome;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

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
Maps one decoded ID3v2.3 `COMM` frame to the canonical `comment` field.

The native three-byte language identifier and short description are
preserved as canonical field context.

Params:
    frame = Decoded native comment frame.
    sourceLength = Complete physical frame length when known. The
        default zero length represents point provenance only.

Returns:
    Canonical mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23CommentFrameToCanonical(
    Id3v23CommentFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return
        Id3v23CanonicalMappingResult
            .success(
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
Maps one decoded ID3v2.3 `USLT` frame to the canonical `lyrics` field.

The native three-byte language identifier and content descriptor are
preserved as canonical field context.

Params:
    frame = Decoded native unsynchronised-lyrics/text frame.
    sourceLength = Complete physical frame length when known. The
        default zero length represents point provenance only.

Returns:
    Canonical mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23LyricsTextFrameToCanonical(
    Id3v23LyricsTextFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return
        Id3v23CanonicalMappingResult
            .success(
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
Maps one unified native ID3v2.3 frame through the language-qualified
text mapper.

Only `COMM` and `USLT` outcomes are handled by this module. Other native
frame families return `unsupportedFrame`.

Decoded `COMM` and `USLT` outcomes are mapped. Transformation-pending
outcomes return `requiresTransformation`.

Params:
    native = Unified native ID3v2.3 frame.

Returns:
    Canonical mapping result.
+/
Id3v23CanonicalMappingResult
mapId3v23NativeLanguageTextFrameToCanonical(
    Id3v23NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v23CommentOutcome outcome) =>
                outcome.decoded
                    ? mapId3v23CommentFrameToCanonical(
                        outcome.comment,
                        native.sourceLength
                    )
                    : Id3v23CanonicalMappingResult
                        .transformationRequired(),

            (Id3v23LyricsTextOutcome outcome) =>
                outcome.decoded
                    ? mapId3v23LyricsTextFrameToCanonical(
                        outcome.lyrics,
                        native.sourceLength
                    )
                    : Id3v23CanonicalMappingResult
                        .transformationRequired(),

            _ =>
                Id3v23CanonicalMappingResult
                    .unsupported()
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
            MetadataKey(
                canonicalKey
            ),
            MetadataValue(
                MetadataText(
                    value
                )
            ),
            [
                makeProvenance(
                    nativeIdentifier,
                    sourceOffset,
                    sourceLength
                )
            ],
            MetadataLanguage(
                languageTag
            ),
            description
        );


    assertRegisteredShape(
        field
    );


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
    return
        MetadataProvenance(
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


    assert(
        definition.found
    );


    assert(
        definition.definition
            .accepts(
                field.value
            )
    );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.comment :
        Id3v23CommentAvailability;

    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope,
        parseId3v23FrameEnvelope;

    import audiotag.id3v2.v23.lyrics_text :
        Id3v23LyricsTextAvailability;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame,
        decodeId3v23NativeFrame;


    /++
    Constructs one decoded comment frame for mapping tests.
    +/
    private Id3v23CommentFrame testCommentFrame(
        string text,
        string description = "",
        string language = "eng",
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(
            language.length ==
            3
        );


        Id3v23CommentFrame frame;


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
    private Id3v23LyricsTextFrame testLyricsFrame(
        string text,
        string descriptor = "",
        string language = "eng",
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(
            language.length ==
            3
        );


        Id3v23LyricsTextFrame frame;


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
}


/// COMM maps text, language and description without loss.
unittest
{
    auto result =
        mapId3v23CommentFrameToCanonical(
            testCommentFrame(
                "A comment",
                "short description",
                "deu",
                123
            )
        );


    assert(
        result.mapped
    );


    assert(
        result.field.key.name ==
        "comment"
    );


    assert(
        result.field.hasLanguage
    );


    assert(
        result.field.language.tag ==
        "deu"
    );


    assert(
        result.field.hasDescription
    );


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
                text.value ==
                "A comment",

            _ =>
                false
        );


    assert(
        matches
    );
}


/// USLT maps lyrics text, language and descriptor without loss.
unittest
{
    auto result =
        mapId3v23LyricsTextFrameToCanonical(
            testLyricsFrame(
                "Lyrics body",
                "verse",
                "eng",
                321
            )
        );


    assert(
        result.mapped
    );


    assert(
        result.field.key.name ==
        "lyrics"
    );


    assert(
        result.field.hasLanguage
    );


    assert(
        result.field.language.tag ==
        "eng"
    );


    assert(
        result.field.hasDescription
    );


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
                text.value ==
                "Lyrics body",

            _ =>
                false
        );


    assert(
        matches
    );
}


/// Three native language bytes are preserved without normalization.
unittest
{
    auto result =
        mapId3v23CommentFrameToCanonical(
            testCommentFrame(
                "text",
                "",
                "ENG"
            )
        );


    assert(
        result.mapped
    );


    assert(
        result.field.language.tag ==
        "ENG"
    );
}


/// Empty descriptions remain unspecified canonical description context.
unittest
{
    auto comment =
        mapId3v23CommentFrameToCanonical(
            testCommentFrame(
                "comment"
            )
        );


    assert(
        comment.mapped
    );


    assert(
        !comment.field.hasDescription
    );


    auto lyrics =
        mapId3v23LyricsTextFrameToCanonical(
            testLyricsFrame(
                "lyrics"
            )
        );


    assert(
        lyrics.mapped
    );


    assert(
        !lyrics.field.hasDescription
    );
}


/// Native COMM mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',

            /*
             * Latin-1 encoding
             * + language
             * + "desc"
             * + terminator
             * + "Hello".
             */
            0x00, 0x00, 0x00, 0x0E,

            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            'd', 'e', 's', 'c',
            0x00,
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
        cursor.parseId3v23FrameEnvelope();


    assert(
        envelope.hasValue
    );


    assert(
        cursor.empty
    );


    auto native =
        decodeId3v23NativeFrame(
            envelope.value
        );


    assert(
        native.hasValue
    );


    auto mapped =
        mapId3v23NativeLanguageTextFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


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


    assert(
        mapped.field.value.match!(
            (MetadataText text) =>
                text.value ==
                "Hello",

            _ =>
                false
        )
    );
}


/// Native USLT mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',

            /*
             * Latin-1 encoding
             * + language
             * + "verse"
             * + terminator
             * + "Lyrics".
             */
            0x00, 0x00, 0x00, 0x10,

            0x00, 0x00,

            0x00,
            'e', 'n', 'g',
            'v', 'e', 'r', 's', 'e',
            0x00,
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
        cursor.parseId3v23FrameEnvelope();


    assert(
        envelope.hasValue
    );


    assert(
        cursor.empty
    );


    auto native =
        decodeId3v23NativeFrame(
            envelope.value
        );


    assert(
        native.hasValue
    );


    auto mapped =
        mapId3v23NativeLanguageTextFrameToCanonical(
            native.value
        );


    assert(
        mapped.mapped
    );


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


    assert(
        mapped.field.value.match!(
            (MetadataText text) =>
                text.value ==
                "Lyrics",

            _ =>
                false
        )
    );
}


/// Transformation-pending COMM remains valid native metadata.
unittest
{
    Id3v23CommentOutcome outcome;


    outcome.availability =
        Id3v23CommentAvailability
            .requiresDecompression;


    Id3v23NativeFrameContent content =
        outcome;


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativeLanguageTextFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v23CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Transformation-pending USLT remains valid native metadata.
unittest
{
    Id3v23LyricsTextOutcome outcome;


    outcome.availability =
        Id3v23LyricsTextAvailability
            .requiresDecryption;


    Id3v23NativeFrameContent content =
        outcome;


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativeLanguageTextFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v23CanonicalMappingStatus
            .requiresTransformation
    );
}


/// Other native frame families are unsupported by this mapper.
unittest
{
    Id3v23NativeFrameContent content =
        Id3v23UnknownFrame();


    auto native =
        Id3v23NativeFrame(
            Id3v23FrameEnvelope.init,
            content
        );


    auto result =
        mapId3v23NativeLanguageTextFrameToCanonical(
            native
        );


    assert(
        !result.mapped
    );


    assert(
        result.status ==
        Id3v23CanonicalMappingStatus
            .unsupportedFrame
    );
}
