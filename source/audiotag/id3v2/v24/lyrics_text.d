/++
ID3v2.4 unsynchronised lyrics/text transcription decoding.

A `USLT` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one termina:contentReference[oaicite:0]{index=0}- lyrics or text transcription extending to the frame boundary.

The descriptor and text use the selected text encoding. Newline
characters are permitted in the lyrics/text body.

"Unsynchronised" in the frame name refers to the absence of timing
information; it is independent of ID3 byte unsynchronisation.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.lyrics_text;

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
Semantic availability of an unsynchronised lyrics/text frame.
+/
enum Id3v24LyricsTextAvailability : ubyte
{
    /// Descriptor and text were decoded successfully.
    decoded,

    /// Payload must be decompressed first.
    requiresDecompression,

    /// Payload must be decrypted first.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.4 `USLT` frame.
+/
struct Id3v24LyricsTextFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding used by descriptor and lyrics/text.
    Id3v24TextEncoding encoding;

    /// Three-byte ISO-639-2 language field as stored.
    char[3] language;

    /// Physical language bytes as stored.
    ByteSpan rawLanguage;

    /// Decoded content descriptor.
    string descriptor;

    /// Decoded lyrics or text transcription.
    string text;

    /// Physical descriptor bytes, excluding its terminator.
    ByteSpan rawDescriptor;

    /// Physical lyrics/text bytes extending to the frame boundary.
    ByteSpan rawText;

    /// Whether ID3 byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `USLT` decoding.
+/
struct Id3v24LyricsTextOutcome
{
    /// Semantic availability.
    Id3v24LyricsTextAvailability availability;

    /// Decoded frame when available.
    Id3v24LyricsTextFrame lyrics;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;

    /// Whether semantic text is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24LyricsTextAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 unsynchronised lyrics/text (`USLT`) frame.

The three language bytes are preserved exactly as stored. The content
descriptor must be terminated according to the selected encoding.
The lyrics/text body occupies the remainder of the bounded frame
payload.

For encoding `$01`, non-empty strings in the same frame must use the
same UTF-16 byte order.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level byte unsynchronisation applies.

Returns:
    Decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v24LyricsTextOutcome
decodeId3v24LyricsTextFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "USLT")
    {
        return ParseResult!Id3v24LyricsTextOutcome.failure(
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
        return ParseResult!Id3v24LyricsTextOutcome.failure(
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
        Id3v24LyricsTextAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24LyricsTextAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24LyricsTextAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24LyricsTextAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24LyricsTextOutcome.success(
            Id3v24LyricsTextOutcome(
                availability,
                Id3v24LyricsTextFrame.init,
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
        return ParseResult!Id3v24LyricsTextOutcome.failure(
            payloadResult.error
        );
    }

    const payload =
        payloadResult.value;

    auto lyrics =
        Id3v24LyricsTextFrame(
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

    return ParseResult!Id3v24LyricsTextOutcome.success(
        Id3v24LyricsTextOutcome(
            Id3v24LyricsTextAvailability.decoded,
            lyrics,
            layout.rawPayload
        )
    );
}




import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A UTF-8 USLT frame decodes language, descriptor and multiline text.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x16,
            0x00, 0x00,

            0x03,
            'e', 'n', 'g',

            'l', 'y', 'r', 'i', 'c', 's',
            0x00,

            'l', 'i', 'n', 'e', '1',
            0x0A,
            'l', 'i', 'n', 'e', '2'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const lyrics =
        result.value.lyrics;

    assert(lyrics.sourceOffset == 100);
    assert(lyrics.encoding == Id3v24TextEncoding.utf8);

    assert(lyrics.language[] == "eng");
    assert(lyrics.descriptor == "lyrics");
    assert(lyrics.text == "line1\nline2");

    assert(lyrics.rawLanguage.sourceOffset == 111);
    assert(lyrics.rawLanguage.data == ['e', 'n', 'g']);

    assert(lyrics.rawDescriptor.sourceOffset == 114);
    assert(lyrics.rawDescriptor.length == 6);

    assert(lyrics.rawText.sourceOffset == 121);
    assert(lyrics.rawText.length == 11);
}


/// An empty descriptor is valid.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
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
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.lyrics.language[] == "deu");
    assert(result.value.lyrics.descriptor.length == 0);
    assert(result.value.lyrics.text == "\u00E4");
}


/// UTF-16 descriptor and lyrics may use little-endian encoding.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            // Descriptor "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // Lyrics "B", little endian.
            0xFF, 0xFE,
            0x42, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.lyrics.descriptor == "A");
    assert(result.value.lyrics.text == "B");
}


/// UTF-16 strings in one USLT frame must share byte order.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            // Descriptor "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // Lyrics "B", big endian.
            0xFE, 0xFF,
            0x00, 0x42
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24LyricsTextFrame();

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
            'U', 'S', 'L', 'T',
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
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 513);
}


/// A missing content-descriptor terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
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
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The USLT codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
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
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// Compressed USLT data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
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
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24LyricsTextAvailability.requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Frame-level byte unsynchronisation applies to lyrics/text.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
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
        frame.value.decodeId3v24LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.lyrics.language[] == "eng");
    assert(result.value.lyrics.descriptor == "x");
    assert(result.value.lyrics.text == "y\u00FF");

    assert(
        result.value.lyrics.effectiveUnsynchronisation
    );

    // Physical provenance retains the stuffing byte.
    assert(
        result.value.lyrics.rawText.data ==
        ['y', 0xFF, 0x00]
    );
}
