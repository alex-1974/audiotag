/++
ID3v2.3 unsynchronised lyrics/text transcription decoding.

A `USLT` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one terminated content descriptor;
- lyrics or text transcription extending to the frame boundary.

The descriptor and text use the selected text encoding.

"Unsynchronised" in the frame name refers to the absence of timing
information. It is unrelated to ID3 byte unsynchronisation.

For ID3v2.3 encoding `$01`, each non-empty Unicode string carries its
own byte-order mark. Descriptor and text may therefore use different
byte orders.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.
+/
module audiotag.id3v2.v23.lyrics_text;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_data :
    parseId3v23FrameDataLayout;

import audiotag.id3v2.v23.language_text_payload :
    decodeId3v23LanguageTextPayload;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding;


/++
Semantic availability of an ID3v2.3 unsynchronised lyrics/text frame.
+/
enum Id3v23LyricsTextAvailability : ubyte
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
Decoded ID3v2.3 `USLT` frame.
+/
struct Id3v23LyricsTextFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding used by descriptor and lyrics/text.
    Id3v23TextEncoding encoding;

    /// Three-byte ISO-639-2 language field as stored logically.
    char[3] language;

    /// Physical language bytes including any unsynchronisation stuffing.
    ByteSpan rawLanguage;

    /// Decoded content descriptor.
    string descriptor;

    /// Decoded lyrics or text transcription.
    string text;

    /// Physical descriptor bytes, excluding its terminator.
    ByteSpan rawDescriptor;

    /// Physical lyrics/text bytes extending to the frame boundary.
    ByteSpan rawText;

    /// Whether ID3v2.3 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `USLT` decoding.
+/
struct Id3v23LyricsTextOutcome
{
    /// Semantic availability.
    Id3v23LyricsTextAvailability availability;

    /// Decoded frame when available.
    Id3v23LyricsTextFrame lyrics;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;


    /// Whether semantic lyrics/text data is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23LyricsTextAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 unsynchronised lyrics/text (`USLT`) frame.

The three language bytes are preserved exactly as stored logically.

The content descriptor must be terminated according to the selected
encoding.

The lyrics/text body occupies the remainder of the bounded semantic
payload.

For encoding `$01`, each non-empty Unicode string carries its own BOM.
The descriptor and text may therefore use different byte orders.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    Decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v23LyricsTextOutcome
decodeId3v23LyricsTextFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "USLT"
    )
    {
        return
            ParseResult!Id3v23LyricsTextOutcome
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }


    auto layoutResult =
        frame.parseId3v23FrameDataLayout(
            tagUnsynchronised
        );

    if (
        layoutResult.hasError
    )
    {
        return
            ParseResult!Id3v23LyricsTextOutcome
                .failure(
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
        Id3v23LyricsTextAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23LyricsTextAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23LyricsTextAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23LyricsTextAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23LyricsTextOutcome
                .success(
                    Id3v23LyricsTextOutcome(
                        availability,
                        Id3v23LyricsTextFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payloadResult =
        decodeId3v23LanguageTextPayload(
            layout.rawPayload,
            layout.effectiveUnsynchronisation
        );

    if (
        payloadResult.hasError
    )
    {
        return
            ParseResult!Id3v23LyricsTextOutcome
                .failure(
                    payloadResult.error
                );
    }

    const payload =
        payloadResult.value;


    const lyrics =
        Id3v23LyricsTextFrame(
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


    return
        ParseResult!Id3v23LyricsTextOutcome
            .success(
                Id3v23LyricsTextOutcome(
                    Id3v23LyricsTextAvailability.decoded,
                    lyrics,
                    layout.rawPayload
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;
}


/// A Latin-1 USLT frame decodes language, descriptor and multiline text.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',

            /*
             * Encoding
             * + language
             * + "lyrics"
             * + terminator
             * + "line1\nline2".
             */
            0x00, 0x00, 0x00, 0x16,

            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const lyrics =
        result.value.lyrics;

    assert(lyrics.sourceOffset == 100);

    assert(
        lyrics.encoding ==
        Id3v23TextEncoding.latin1
    );

    assert(lyrics.language[] == "eng");
    assert(lyrics.descriptor == "lyrics");
    assert(lyrics.text == "line1\nline2");

    assert(
        lyrics.rawLanguage.sourceOffset ==
        111
    );

    assert(
        lyrics.rawLanguage.data ==
        ['e', 'n', 'g']
    );

    assert(
        lyrics.rawDescriptor.sourceOffset ==
        114
    );

    assert(
        lyrics.rawDescriptor.data ==
        ['l', 'y', 'r', 'i', 'c', 's']
    );

    assert(
        lyrics.rawText.sourceOffset ==
        121
    );

    assert(
        lyrics.rawText.length ==
        11
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        22
    );
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
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.lyrics.language[] ==
        "deu"
    );

    assert(
        result.value.lyrics.descriptor.length ==
        0
    );

    assert(
        result.value.lyrics.text ==
        "\u00E4"
    );
}


/// Unicode descriptor and lyrics may both use little-endian UCS-2.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            /*
             * Descriptor "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Lyrics "B", little endian.
             */
            0xFF, 0xFE,
            0x42, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.lyrics.descriptor ==
        "A"
    );

    assert(
        result.value.lyrics.text ==
        "B"
    );
}


/// ID3v2.3 USLT strings may use different Unicode byte orders.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.lyrics.descriptor ==
        "A"
    );

    assert(
        result.value.lyrics.text ==
        "B"
    );
}


/// A truncated three-byte language field is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 614);
}


/// The USLT codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// ID3v2.4-only encoding markers remain invalid in USLT.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            0x03,
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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 810);
}


/// Compressed USLT data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',

            /*
             * Decompressed-size prefix + opaque semantic payload.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x80,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23LyricsTextAvailability
            .requiresDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        914
    );
}


/// Encrypted USLT data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x40,

            0x23,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23LyricsTextAvailability
            .requiresDecryption
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1011
    );
}


/// Combined USLT transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
            0x00, 0x00, 0x00, 0x06,

            0x00, 0xC0,

            0x00, 0x00, 0x00, 0x01,
            0x23,
            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1100
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23LyricsTextAvailability
            .requiresDecryptionAndDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1115
    );
}


/// Grouping identity is removed before USLT semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',

            /*
             * Group symbol + ordinary USLT semantic payload.
             */
            0x00, 0x00, 0x00, 0x07,

            0x00, 0x20,

            0x7A,

            0x00,
            'e', 'n', 'g',
            0x00,
            'A'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1200
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.lyrics.language[] ==
        "eng"
    );

    assert(
        result.value.lyrics.descriptor.length ==
        0
    );

    assert(
        result.value.lyrics.text ==
        "A"
    );

    assert(
        result.value.lyrics.rawLanguage.sourceOffset ==
        1212
    );
}


/// Whole-tag unsynchronisation applies across USLT payload fields.
unittest
{
    /*
     * Logical semantic payload:
     *
     *   00
     *   e FF g
     *   d FF
     *   00
     *   t FF E1
     *
     * Physical semantic payload:
     *
     *   00
     *   e FF 00 g
     *   d FF 00 00
     *   t FF 00 E1
     */
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',

            /*
             * Ten logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00,

            0x00,

            'e',
            0xFF, 0x00,
            'g',

            'd',
            0xFF, 0x00,
            0x00,

            't',
            0xFF, 0x00,
            0xE1
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1300
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const lyrics =
        result.value.lyrics;

    assert(
        lyrics.language[0] ==
        'e'
    );

    assert(
        cast(ubyte) lyrics.language[1] ==
        0xFF
    );

    assert(
        lyrics.language[2] ==
        'g'
    );

    assert(
        lyrics.descriptor ==
        "d\u00FF"
    );

    assert(
        lyrics.text ==
        "t\u00FF\u00E1"
    );

    assert(lyrics.effectiveUnsynchronisation);

    assert(
        lyrics.rawLanguage.data ==
        [
            'e',
            0xFF, 0x00,
            'g'
        ]
    );

    assert(
        lyrics.rawDescriptor.data ==
        [
            'd',
            0xFF, 0x00
        ]
    );

    assert(
        lyrics.rawText.data ==
        [
            't',
            0xFF, 0x00,
            0xE1
        ]
    );
}


/// Unsynchronisation inside independent Unicode BOMs remains valid.
unittest
{
    /*
     * Descriptor uses little endian, text uses big endian.
     */
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',

            /*
             * Fourteen logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x0E,

            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            /*
             * Little-endian descriptor BOM with stuffing.
             */
            0xFF, 0x00,
            0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Big-endian text BOM; final FF is followed by logical 00.
             */
            0xFE,
            0xFF, 0x00,
            0x00, 0x42
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1400
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23LyricsTextFrame(
                true
            );

    assert(result.hasValue);

    assert(
        result.value.lyrics.descriptor ==
        "A"
    );

    assert(
        result.value.lyrics.text ==
        "B"
    );
}
