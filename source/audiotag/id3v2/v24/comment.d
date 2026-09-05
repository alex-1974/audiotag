/++
ID3v2.4 comment-frame decoding.

A `COMM` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one terminated short content description;
- the actual comment text extending to the frame boundary.

The description and comment use the selected text encoding. Newline
characters are permitted in the actual comment text.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.comment;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_data :
    parseId3v24FrameDataLayout;

import audiotag.id3v2.v24.language_text_payload :
    decodeId3v24LanguageTextPayload;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding;


/++
Semantic availability of a comment frame.
+/
enum Id3v24CommentAvailability : ubyte
{
    /// Description and comment were decoded successfully.
    decoded,

    /// Payload must be decompressed first.
    requiresDecompression,

    /// Payload must be decrypted first.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.4 `COMM` frame.
+/
struct Id3v24CommentFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding used by description and comment.
    Id3v24TextEncoding encoding;

    /// Three-byte ISO-639-2 language field as stored in the frame.
    char[3] language;

    /// Physical language bytes, including any unsynchronisation stuffing.
    ByteSpan rawLanguage;

    /// Decoded short content description.
    string description;

    /// Decoded comment text.
    string text;

    /// Physical description bytes, excluding its terminator.
    ByteSpan rawDescription;

    /// Physical comment bytes extending to the frame boundary.
    ByteSpan rawText;

    /// Whether unsynchronisation was effective for this frame.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `COMM` decoding.
+/
struct Id3v24CommentOutcome
{
    /// Semantic availability.
    Id3v24CommentAvailability availability;

    /// Decoded frame when available.
    Id3v24CommentFrame comment;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;

    /// Whether semantic comment data is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24CommentAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 comment (`COMM`) frame.

The three-byte language field is preserved as stored rather than
strictly normalised or rejected. The short content description must
be terminated according to the selected encoding. The actual comment
occupies the remainder of the bounded frame payload.

For encoding `$01`, non-empty strings in the same frame must use the
same UTF-16 byte order.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level unsynchronisation applies.

Returns:
    Decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v24CommentOutcome
decodeId3v24CommentFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "COMM")
    {
        return ParseResult!Id3v24CommentOutcome.failure(
            ParseError(
                ParseErrorCode.invalidSignature,
                frame.header.sourceOffset
            )
        );
    }

    auto layoutResult =
        frame.parseId3v24FrameDataLayout(
            tagUnsynchronised
        );

    if (layoutResult.hasError)
    {
        return ParseResult!Id3v24CommentOutcome.failure(
            layoutResult.error
        );
    }

    const layout =
        layoutResult.value;

    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v24CommentAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24CommentAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24CommentAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24CommentAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24CommentOutcome.success(
            Id3v24CommentOutcome(
                availability,
                Id3v24CommentFrame.init,
                layout.rawPayload
            )
        );
    }

    auto payloadResult =
        decodeId3v24LanguageTextPayload(
            layout.rawPayload,
            layout.effectiveUnsynchronisation
        );

    if (payloadResult.hasError)
    {
        return ParseResult!Id3v24CommentOutcome.failure(
            payloadResult.error
        );
    }

    const payload =
        payloadResult.value;

    auto comment =
        Id3v24CommentFrame(
            frame.header.sourceOffset,
            payload.encoding,
            payload.language,
            payload.rawLanguage,
            payload.descriptor,
            payload.text,
            payload.rawDescriptor,
            payload.rawText,
            payload.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24CommentOutcome.success(
        Id3v24CommentOutcome(
            Id3v24CommentAvailability.decoded,
            comment,
            layout.rawPayload
        )
    );
}




import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A UTF-8 COMM frame decodes language, description and comment.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x14,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',
            'n', 'o', 't', 'e',
            0x00,
            'h', 'e', 'l', 'l', 'o',
            0x0A,
            'w', 'o', 'r', 'l', 'd'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const comment =
        result.value.comment;

    assert(comment.sourceOffset == 100);
    assert(comment.encoding == Id3v24TextEncoding.utf8);

    assert(comment.language[] == "eng");
    assert(comment.description == "note");
    assert(comment.text == "hello\nworld");

    assert(comment.rawLanguage.sourceOffset == 111);
    assert(comment.rawLanguage.data == ['e', 'n', 'g']);

    assert(comment.rawDescription.sourceOffset == 114);
    assert(comment.rawDescription.data == ['n', 'o', 't', 'e']);

    assert(comment.rawText.sourceOffset == 119);
    assert(comment.rawText.length == 11);
}


/// An empty description is valid.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x00,
            'd', 'e', 'u',
            0x00,
            0xE4
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.comment.language[] == "deu");
    assert(result.value.comment.description.length == 0);
    assert(result.value.comment.text == "\u00E4");
}


/// UTF-16 description and comment may use little-endian encoding.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            // Description "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // Comment "B", little endian.
            0xFF, 0xFE,
            0x42, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.comment.description == "A");
    assert(result.value.comment.text == "B");
}


/// UTF-16 strings in one COMM frame must share byte order.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            // Description "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // Comment "B", big endian.
            0xFE, 0xFF,
            0x00, 0x42
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 420);
}


/// A truncated three-byte language field is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x03,
            'e', 'n'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 513);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The COMM codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x03
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 700));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// Compressed COMM data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            // Required DLI.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24CommentAvailability.requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Frame-level unsynchronisation applies to comment text.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x02,

            0x00,
            'e', 'n', 'g',

            'x',
            0x00,

            'y',
            0xFF, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 900));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.comment.language[] == "eng");
    assert(result.value.comment.description == "x");
    assert(result.value.comment.text == "y\u00FF");

    assert(
        result.value.comment.effectiveUnsynchronisation
    );

    // Physical provenance retains the stuffing byte.
    assert(
        result.value.comment.rawText.data ==
        ['y', 0xFF, 0x00]
    );
}
