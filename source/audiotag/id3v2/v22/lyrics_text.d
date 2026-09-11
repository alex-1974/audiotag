/++
ID3v2.2 unsynchronised lyrics/text transcription decoding.

An `ULT` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one terminated content descriptor;
- lyrics or text transcription extending to the frame boundary.

The shared language/descriptor/text mechanics live in
`language_text_payload.d`. This module adds only the `ULT` frame identity and
lyrics-specific native representation.

"Unsynchronised" in the semantic frame name means that the lyrics contain no
timing information. It is unrelated to ID3 byte unsynchronisation.

Whole-tag byte unsynchronisation is reversed only during logical traversal and
text decoding. Raw spans preserve the exact physical source representation.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.lyrics_text;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.language_text_payload :
    decodeId3v22LanguageTextPayload;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding;


/++
Decoded ID3v2.2 `ULT` frame.

The three language bytes are preserved exactly as stored logically.

`rawLanguage`, `rawDescriptor` and `rawText` preserve the physical source
representation, including any whole-tag unsynchronisation stuffing.
+/
struct Id3v22LyricsTextFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding used by descriptor and lyrics/text.
    Id3v22TextEncoding encoding;

    /// Three-byte language field as stored logically.
    char[3] language;

    /// Physical language bytes as stored.
    ByteSpan rawLanguage;

    /// Decoded content descriptor.
    string descriptor;

    /// Decoded lyrics or text transcription.
    string text;

    /// Physical descriptor bytes excluding its terminator.
    ByteSpan rawDescriptor;

    /// Physical lyrics/text bytes extending to the frame boundary.
    ByteSpan rawText;

    /// Whether ID3v2.2 whole-tag byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ID3v2.2 unsynchronised lyrics/text (`ULT`) frame.

The payload has the form:

    Text encoding       $xx
    Language            $xx xx xx
    Content descriptor  <text according to encoding> $00 (00)
    Lyrics/text         <text according to encoding>

The content-descriptor terminator is mandatory.

The lyrics/text body occupies the remainder of the bounded frame payload and
may contain newline characters.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag byte unsynchronisation
        applies.

Returns:
    The decoded native lyrics/text frame or a structured parse error.
+/
ParseResult!Id3v22LyricsTextFrame
decodeId3v22LyricsTextFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "ULT"
    )
    {
        return
            ParseResult!Id3v22LyricsTextFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }


    auto payloadResult =
        decodeId3v22LanguageTextPayload(
            frame.data,
            tagUnsynchronised
        );

    if (
        payloadResult.hasError
    )
    {
        return
            ParseResult!Id3v22LyricsTextFrame
                .failure(
                    payloadResult.error
                );
    }

    const payload =
        payloadResult.value;


    return
        ParseResult!Id3v22LyricsTextFrame
            .success(
                Id3v22LyricsTextFrame(
                    frame.header.sourceOffset,
                    payload.encoding,
                    payload.language,
                    payload.rawLanguage,
                    payload.descriptor,
                    payload.text,
                    payload.rawDescriptor,
                    payload.rawText,
                    payload.effectiveUnsynchronisation
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.data_cursor :
        Id3v22DataCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


/// A Latin-1 ULT frame decodes language, descriptor and multiline text.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',

            /*
             * Encoding
             * + language
             * + "lyrics"
             * + terminator
             * + "line1\nline2".
             *
             * 1 + 3 + 6 + 1 + 11 = 22.
             */
            0x00, 0x00, 0x16,

            0x00,

            'e', 'n', 'g',

            'l', 'y', 'r', 'i', 'c', 's',
            0x00,

            'l', 'i', 'n', 'e', '1',
            0x0A,
            'l', 'i', 'n', 'e', '2'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasValue);

    const lyrics =
        result.value;

    assert(lyrics.sourceOffset == 100);

    assert(
        lyrics.encoding ==
        Id3v22TextEncoding.latin1
    );

    assert(lyrics.language[] == "eng");
    assert(lyrics.descriptor == "lyrics");
    assert(lyrics.text == "line1\nline2");

    assert(lyrics.rawLanguage.sourceOffset == 107);

    assert(
        lyrics.rawLanguage.data ==
        ['e', 'n', 'g']
    );

    assert(lyrics.rawDescriptor.sourceOffset == 110);

    assert(
        lyrics.rawDescriptor.data ==
        ['l', 'y', 'r', 'i', 'c', 's']
    );

    assert(lyrics.rawText.sourceOffset == 117);
    assert(lyrics.rawText.length == 11);

    assert(!lyrics.effectiveUnsynchronisation);
}


/// An empty content descriptor is valid.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
            0x00, 0x00, 0x06,

            0x00,
            'd', 'e', 'u',
            0x00,
            0xE4
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasValue);

    const lyrics =
        result.value;

    assert(lyrics.language[] == "deu");
    assert(lyrics.descriptor.length == 0);
    assert(lyrics.text == "\u00E4");

    assert(lyrics.rawDescriptor.empty);
    assert(lyrics.rawDescriptor.sourceOffset == 210);

    assert(
        lyrics.rawText.data ==
        [0xE4]
    );
}


/// BOM-less UCS-2 descriptor and lyrics use the v2.2 big-endian default.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',

            /*
             * 1 encoding
             * + 3 language
             * + 2 descriptor
             * + 2 terminator
             * + 2 lyrics
             * = 10.
             */
            0x00, 0x00, 0x0A,

            0x01,
            'e', 'n', 'g',

            0x00, 0x41,
            0x00, 0x00,

            0x00, 0x42
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasValue);

    const lyrics =
        result.value;

    assert(
        lyrics.encoding ==
        Id3v22TextEncoding.utf16
    );

    assert(lyrics.language[] == "eng");
    assert(lyrics.descriptor == "A");
    assert(lyrics.text == "B");
}


/// Descriptor and lyrics may carry explicit independent byte-order marks.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',

            /*
             * 1 encoding
             * + 3 language
             * + 4 descriptor
             * + 2 terminator
             * + 4 lyrics
             * = 14.
             */
            0x00, 0x00, 0x0E,

            0x01,
            'e', 'n', 'g',

            /*
             * Descriptor "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Lyrics "B", big endian.
             */
            0xFE, 0xFF,
            0x00, 0x42
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.descriptor == "A");
    assert(result.value.text == "B");
}


/// A truncated language field propagates the lower structured error.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
            0x00, 0x00, 0x03,

            0x00,
            'e', 'n'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 509);
}


/// A missing content-descriptor terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
            0x00, 0x00, 0x07,

            0x00,
            'e', 'n', 'g',
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 610);
}


/// The ULT codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
            0x00, 0x00, 0x05,

            0x00,
            'e', 'n', 'g',
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// Undefined encoding markers remain structured errors.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
            0x00, 0x00, 0x05,

            0x02,
            'e', 'n', 'g',
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 806);
}


/// Whole-tag byte unsynchronisation retains exact physical provenance.
unittest
{
    /*
     * Logical frame data:
     *
     *   00
     *   e n g
     *   FF
     *   00
     *   FF
     *
     * Physical frame data:
     *
     *   00
     *   e n g
     *   FF 00
     *   00
     *   FF 00
     */
    const ubyte[] bytes =
        [
            'U', 'L', 'T',

            /*
             * Seven logical frame-data bytes.
             */
            0x00, 0x00, 0x07,

            0x00,
            'e', 'n', 'g',

            0xFF, 0x00,
            0x00,

            0xFF, 0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                900
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 7);

    auto result =
        frame.value
            .decodeId3v22LyricsTextFrame(
                true
            );

    assert(result.hasValue);

    const lyrics =
        result.value;

    assert(lyrics.effectiveUnsynchronisation);
    assert(lyrics.language[] == "eng");
    assert(lyrics.descriptor == "\u00FF");
    assert(lyrics.text == "\u00FF");

    assert(
        lyrics.rawDescriptor.data ==
        [0xFF, 0x00]
    );

    assert(
        lyrics.rawText.data ==
        [0xFF, 0x00]
    );
}
