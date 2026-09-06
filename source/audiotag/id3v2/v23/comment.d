/++
ID3v2.3 comment-frame decoding.

A `COMM` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one terminated short content description;
- the actual comment text extending to the frame boundary.

The description and comment use the selected text encoding.

ID3v2.3 Unicode strings carry their own byte-order marks. Description
and comment are therefore decoded independently and may use different
byte orders.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.
+/
module audiotag.id3v2.v23.comment;

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
Semantic availability of an ID3v2.3 comment frame.
+/
enum Id3v23CommentAvailability : ubyte
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
Decoded ID3v2.3 `COMM` frame.
+/
struct Id3v23CommentFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding used by description and comment.
    Id3v23TextEncoding encoding;

    /// Three-byte ISO-639-2 language field as stored logically.
    char[3] language;

    /// Physical language bytes including any unsynchronisation stuffing.
    ByteSpan rawLanguage;

    /// Decoded short content description.
    string description;

    /// Decoded comment text.
    string text;

    /// Physical description bytes, excluding its terminator.
    ByteSpan rawDescription;

    /// Physical comment bytes extending to the frame boundary.
    ByteSpan rawText;

    /// Whether ID3v2.3 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `COMM` decoding.
+/
struct Id3v23CommentOutcome
{
    /// Semantic availability.
    Id3v23CommentAvailability availability;

    /// Decoded frame when available.
    Id3v23CommentFrame comment;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;


    /// Whether semantic comment data is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23CommentAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 comment (`COMM`) frame.

The three-byte language field is preserved as stored rather than
strictly normalised or rejected.

The short content description must be terminated according to the
selected encoding.

The actual comment occupies the remainder of the bounded semantic
payload.

For encoding `$01`, each non-empty Unicode string carries its own BOM.
The description and comment may therefore use different byte orders.

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
ParseResult!Id3v23CommentOutcome
decodeId3v23CommentFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "COMM"
    )
    {
        return
            ParseResult!Id3v23CommentOutcome
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
            ParseResult!Id3v23CommentOutcome
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
        Id3v23CommentAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23CommentAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23CommentAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23CommentAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23CommentOutcome
                .success(
                    Id3v23CommentOutcome(
                        availability,
                        Id3v23CommentFrame.init,
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
            ParseResult!Id3v23CommentOutcome
                .failure(
                    payloadResult.error
                );
    }

    const payload =
        payloadResult.value;


    const comment =
        Id3v23CommentFrame(
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
        ParseResult!Id3v23CommentOutcome
            .success(
                Id3v23CommentOutcome(
                    Id3v23CommentAvailability.decoded,
                    comment,
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


/// A Latin-1 COMM frame decodes language, description and comment.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',

            /*
             * Encoding
             * + language
             * + "note"
             * + terminator
             * + "hello\nworld".
             */
            0x00, 0x00, 0x00, 0x14,

            0x00, 0x00,

            0x00,

            'e', 'n', 'g',

            'n', 'o', 't', 'e',
            0x00,

            'h', 'e', 'l', 'l', 'o',
            0x0A,
            'w', 'o', 'r', 'l', 'd'
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const comment =
        result.value.comment;

    assert(comment.sourceOffset == 100);

    assert(
        comment.encoding ==
        Id3v23TextEncoding.latin1
    );

    assert(comment.language[] == "eng");
    assert(comment.description == "note");
    assert(comment.text == "hello\nworld");

    assert(
        comment.rawLanguage.sourceOffset ==
        111
    );

    assert(
        comment.rawLanguage.data ==
        ['e', 'n', 'g']
    );

    assert(
        comment.rawDescription.sourceOffset ==
        114
    );

    assert(
        comment.rawDescription.data ==
        ['n', 'o', 't', 'e']
    );

    assert(
        comment.rawText.sourceOffset ==
        119
    );

    assert(
        comment.rawText.length ==
        11
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        20
    );
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.comment.language[] ==
        "deu"
    );

    assert(
        result.value.comment.description.length ==
        0
    );

    assert(
        result.value.comment.text ==
        "\u00E4"
    );
}


/// Unicode description and comment may both use little-endian UCS-2.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            /*
             * Description "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Comment "B", little endian.
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.comment.description ==
        "A"
    );

    assert(
        result.value.comment.text ==
        "B"
    );
}


/// ID3v2.3 COMM strings may use different Unicode byte orders.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
            0x00, 0x00, 0x00, 0x0E,
            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            /*
             * Description "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Comment "B", big endian.
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.comment.description ==
        "A"
    );

    assert(
        result.value.comment.text ==
        "B"
    );
}


/// A truncated three-byte language field is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
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
            .decodeId3v23CommentFrame();

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
            .decodeId3v23CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 614);
}


/// The COMM codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'S', 'L', 'T',
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
            .decodeId3v23CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// ID3v2.4-only encoding markers remain invalid in COMM.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
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
            .decodeId3v23CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 810);
}


/// Compressed COMM data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',

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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23CommentAvailability
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


/// Encrypted COMM data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23CommentAvailability
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


/// Combined COMM transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23CommentAvailability
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


/// Grouping identity is removed before COMM semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',

            /*
             * Group symbol + ordinary COMM semantic payload.
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
            .decodeId3v23CommentFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.comment.language[] ==
        "eng"
    );

    assert(
        result.value.comment.description.length ==
        0
    );

    assert(
        result.value.comment.text ==
        "A"
    );

    assert(
        result.value.comment.rawLanguage.sourceOffset ==
        1212
    );
}


/// Whole-tag unsynchronisation applies across COMM payload fields.
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
            'C', 'O', 'M', 'M',

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
            .decodeId3v23CommentFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const comment =
        result.value.comment;

    assert(
        comment.language[0] ==
        'e'
    );

    assert(
        cast(ubyte) comment.language[1] ==
        0xFF
    );

    assert(
        comment.language[2] ==
        'g'
    );

    assert(
        comment.description ==
        "d\u00FF"
    );

    assert(
        comment.text ==
        "t\u00FF\u00E1"
    );

    assert(comment.effectiveUnsynchronisation);

    assert(
        comment.rawLanguage.data ==
        [
            'e',
            0xFF, 0x00,
            'g'
        ]
    );

    assert(
        comment.rawDescription.data ==
        [
            'd',
            0xFF, 0x00
        ]
    );

    assert(
        comment.rawText.data ==
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
     * Description uses little endian, comment uses big endian.
     */
    const ubyte[] bytes =
        [
            'C', 'O', 'M', 'M',

            /*
             * Fourteen logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x0E,

            0x00, 0x00,

            0x01,
            'e', 'n', 'g',

            /*
             * Little-endian description BOM with stuffing.
             */
            0xFF, 0x00,
            0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Big-endian comment BOM; final FF is followed by logical 00.
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
            .decodeId3v23CommentFrame(
                true
            );

    assert(result.hasValue);

    assert(
        result.value.comment.description ==
        "A"
    );

    assert(
        result.value.comment.text ==
        "B"
    );
}
