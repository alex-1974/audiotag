/++
Canonical mapping for decoded ID3v2.2 language-qualified text frames.

This module maps:

- COM -> comment
- ULT -> lyrics

The three native language bytes are preserved as the canonical language tag
without normalization. Native description/descriptor text is retained as
canonical field description context.

ID3v2.2 character decoding and whole-tag unsynchronisation are completed by
the native codecs before this mapping layer is reached.

ID3v2.2 has no per-frame compression/encryption state, so decoded semantics
map directly without a transformation-availability outcome.
+/
module audiotag.id3v2.v22.canonical_language_text;

import std.sumtype :
    match;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.comment :
    Id3v22CommentFrame;

import audiotag.id3v2.v22.lyrics_text :
    Id3v22LyricsTextFrame;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

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
Maps one decoded ID3v2.2 `COM` frame to canonical `comment`.

The native language and short description are preserved as field context.
+/
Id3v22CanonicalMappingResult
mapId3v22CommentFrameToCanonical(
    Id3v22CommentFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return
        Id3v22CanonicalMappingResult
            .success(
                makeLanguageTextField(
                    "comment",
                    "COM",
                    frame.text,
                    frame.language,
                    frame.description,
                    frame.sourceOffset,
                    sourceLength
                )
            );
}


/++
Maps one decoded ID3v2.2 `ULT` frame to canonical `lyrics`.

The native language and content descriptor are preserved as field context.
+/
Id3v22CanonicalMappingResult
mapId3v22LyricsTextFrameToCanonical(
    Id3v22LyricsTextFrame frame,
    size_t sourceLength = 0
)
    @safe
{
    return
        Id3v22CanonicalMappingResult
            .success(
                makeLanguageTextField(
                    "lyrics",
                    "ULT",
                    frame.text,
                    frame.language,
                    frame.descriptor,
                    frame.sourceOffset,
                    sourceLength
                )
            );
}


/++
Maps one unified native ID3v2.2 frame through the language-qualified text
mapper.

Only `COM` and `ULT` alternatives are handled. Other native frame families
remain valid native metadata and return `unsupportedFrame`.

The complete native frame supplies the exact physical frame extent for
canonical provenance.
+/
Id3v22CanonicalMappingResult
mapId3v22NativeLanguageTextFrameToCanonical(
    Id3v22NativeFrame native
)
    @safe
{
    return
        native.content.match!(
            (Id3v22CommentFrame frame) =>
                mapId3v22CommentFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            (Id3v22LyricsTextFrame frame) =>
                mapId3v22LyricsTextFrameToCanonical(
                    frame,
                    native.sourceLength
                ),

            _ =>
                Id3v22CanonicalMappingResult
                    .unsupported()
        );
}


/++
Constructs one canonical language-qualified text field.
+/
private MetadataField
makeLanguageTextField(
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
Constructs exact provenance for one mapped native frame.
+/
private MetadataProvenance
makeProvenance(
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
private void
assertRegisteredShape(
    MetadataField field
)
    @safe
{
    const definition =
        findMetadataFieldDefinition(
            field.key
        );

    assert(definition.found);

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

    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope,
        parseId3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame,
        decodeId3v22NativeFrame;


    private Id3v22CommentFrame
    testCommentFrame(
        string text,
        string description = "",
        string language = "eng",
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(language.length == 3);

        Id3v22CommentFrame frame;

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


    private Id3v22LyricsTextFrame
    testLyricsFrame(
        string text,
        string descriptor = "",
        string language = "eng",
        size_t sourceOffset = 100
    )
        @safe
    {
        assert(language.length == 3);

        Id3v22LyricsTextFrame frame;

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


/// COM maps text, language and description without loss.
unittest
{
    auto result =
        mapId3v22CommentFrameToCanonical(
            testCommentFrame(
                "A comment",
                "short description",
                "deu",
                123
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "comment");
    assert(result.field.hasLanguage);
    assert(result.field.language.tag == "deu");
    assert(result.field.hasDescription);
    assert(
        result.field.description ==
        "short description"
    );

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "COM"
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

    assert(matches);
}


/// ULT maps lyrics text, language and descriptor without loss.
unittest
{
    auto result =
        mapId3v22LyricsTextFrameToCanonical(
            testLyricsFrame(
                "Lyrics body",
                "verse",
                "eng",
                321
            )
        );

    assert(result.mapped);
    assert(result.field.key.name == "lyrics");
    assert(result.field.hasLanguage);
    assert(result.field.language.tag == "eng");
    assert(result.field.hasDescription);
    assert(result.field.description == "verse");

    assert(
        result.field.provenance[0]
            .native.identifier ==
        "ULT"
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

    assert(matches);
}


/// Native language bytes are preserved without normalization.
unittest
{
    auto result =
        mapId3v22CommentFrameToCanonical(
            testCommentFrame(
                "text",
                "",
                "ENG"
            )
        );

    assert(result.mapped);
    assert(result.field.language.tag == "ENG");
}


/// Empty descriptions remain unspecified canonical description context.
unittest
{
    auto comment =
        mapId3v22CommentFrameToCanonical(
            testCommentFrame(
                "comment"
            )
        );

    assert(comment.mapped);
    assert(!comment.field.hasDescription);

    auto lyrics =
        mapId3v22LyricsTextFrameToCanonical(
            testLyricsFrame(
                "lyrics"
            )
        );

    assert(lyrics.mapped);
    assert(!lyrics.field.hasDescription);
}


/// Native COM mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',

            /*
             * Encoding
             * + language
             * + "desc"
             * + terminator
             * + "Hello".
             */
            0x00, 0x00, 0x0E,

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
        cursor.parseId3v22FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v22NativeLanguageTextFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);
    assert(mapped.field.key.name == "comment");
    assert(mapped.field.language.tag == "eng");
    assert(mapped.field.description == "desc");

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


/// Native ULT mapping records the complete physical frame extent.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',

            /*
             * Encoding
             * + language
             * + "verse"
             * + terminator
             * + "Lyrics".
             */
            0x00, 0x00, 0x10,

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
        cursor.parseId3v22FrameEnvelope();

    assert(envelope.hasValue);
    assert(cursor.empty);

    auto native =
        decodeId3v22NativeFrame(
            envelope.value
        );

    assert(native.hasValue);

    auto mapped =
        mapId3v22NativeLanguageTextFrameToCanonical(
            native.value
        );

    assert(mapped.mapped);
    assert(mapped.field.key.name == "lyrics");
    assert(mapped.field.language.tag == "eng");
    assert(mapped.field.description == "verse");

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


/// Other native frame families remain unsupported.
unittest
{
    Id3v22NativeFrameContent content =
        Id3v22UnknownFrame();

    auto native =
        Id3v22NativeFrame(
            Id3v22FrameEnvelope.init,
            content
        );

    auto result =
        mapId3v22NativeLanguageTextFrameToCanonical(
            native
        );

    assert(!result.mapped);

    assert(
        result.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );
}
