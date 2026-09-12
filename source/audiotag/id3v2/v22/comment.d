/++
ID3v2.2 comment-frame decoding.

A `COM` frame contains:

- one text-encoding marker;
- one three-byte ISO-639-2 language field;
- one terminated short content description;
- the actual comment text extending to the frame boundary.

The shared language/descriptor/text mechanics live in
`language_text_payload.d`. This module adds only the `COM` frame identity and
comment-specific native representation.

Whole-tag unsynchronisation is reversed only during logical traversal and text
decoding. All raw spans preserve the exact physical source representation.

This module performs no canonical metadata mapping.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.comment;

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
Decoded ID3v2.2 `COM` frame.

The three language bytes are preserved as stored logically rather than
normalised or rejected.

`rawLanguage`, `rawDescription` and `rawText` preserve the physical source
representation, including any whole-tag unsynchronisation stuffing.
+/
struct Id3v22CommentFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding used by description and comment.
    Id3v22TextEncoding encoding;

    /// Three-byte language field as stored logically.
    char[3] language;

    /// Physical language bytes as stored.
    ByteSpan rawLanguage;

    /// Decoded short content description.
    string description;

    /// Decoded comment text.
    string text;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Physical comment bytes extending to the frame boundary.
    ByteSpan rawText;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ID3v2.2 comment (`COM`) frame.

The payload has the form:

    Text encoding             $xx
    Language                  $xx xx xx
    Short content description <text according to encoding> $00 (00)
    Actual text               <text according to encoding>

The description terminator is mandatory.

The actual comment occupies the remainder of the bounded frame payload and may
contain newline characters.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native comment frame or a structured parse error.
+/
ParseResult!Id3v22CommentFrame
decodeId3v22CommentFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "COM"
    )
    {
        return
            ParseResult!Id3v22CommentFrame
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
            ParseResult!Id3v22CommentFrame
                .failure(
                    payloadResult.error
                );
    }

    const payload =
        payloadResult.value;


    return
        ParseResult!Id3v22CommentFrame
            .success(
                Id3v22CommentFrame(
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


/// A Latin-1 COM frame decodes language, description and comment.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',

            /*
             * Encoding
             * + language
             * + "note"
             * + terminator
             * + "hello\nworld".
             *
             * 1 + 3 + 4 + 1 + 11 = 20.
             */
            0x00, 0x00, 0x14,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22CommentFrame();

    assert(result.hasValue);

    const comment =
        result.value;

    assert(comment.sourceOffset == 100);

    assert(
        comment.encoding ==
        Id3v22TextEncoding.latin1
    );

    assert(comment.language[] == "eng");
    assert(comment.description == "note");
    assert(comment.text == "hello\nworld");

    assert(comment.rawLanguage.sourceOffset == 107);

    assert(
        comment.rawLanguage.data ==
        ['e', 'n', 'g']
    );

    assert(comment.rawDescription.sourceOffset == 110);

    assert(
        comment.rawDescription.data ==
        ['n', 'o', 't', 'e']
    );

    assert(comment.rawText.sourceOffset == 115);
    assert(comment.rawText.length == 11);

    assert(!comment.effectiveUnsynchronisation);
}


/// An empty description is valid.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
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
            .decodeId3v22CommentFrame();

    assert(result.hasValue);

    const comment =
        result.value;

    assert(comment.language[] == "deu");
    assert(comment.description.length == 0);
    assert(comment.text == "\u00E4");

    assert(comment.rawDescription.empty);
    assert(comment.rawDescription.sourceOffset == 210);

    assert(
        comment.rawText.data ==
        [0xE4]
    );
}


/// BOM-less UCS-2 description and comment use the v2.2 big-endian default.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',

            /*
             * 1 encoding
             * + 3 language
             * + 2 description
             * + 2 terminator
             * + 2 comment
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
            .decodeId3v22CommentFrame();

    assert(result.hasValue);

    const comment =
        result.value;

    assert(
        comment.encoding ==
        Id3v22TextEncoding.utf16
    );

    assert(comment.language[] == "eng");
    assert(comment.description == "A");
    assert(comment.text == "B");
}


/// Description and comment may carry explicit independent byte-order marks.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',

            /*
             * 1 encoding
             * + 3 language
             * + 4 description
             * + 2 terminator
             * + 4 comment
             * = 14.
             */
            0x00, 0x00, 0x0E,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22CommentFrame();

    assert(result.hasValue);
    assert(result.value.description == "A");
    assert(result.value.text == "B");
}


/// A truncated language field propagates the lower structured error.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
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
            .decodeId3v22CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 509);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'O', 'M',
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
            .decodeId3v22CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 610);
}


/// The COM codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'L', 'T',
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
            .decodeId3v22CommentFrame();

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
            'C', 'O', 'M',
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
            .decodeId3v22CommentFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 806);
}


/// Whole-tag unsynchronisation retains exact physical provenance.
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
            'C', 'O', 'M',

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
            .decodeId3v22CommentFrame(
                true
            );

    assert(result.hasValue);

    const comment =
        result.value;

    assert(comment.effectiveUnsynchronisation);
    assert(comment.language[] == "eng");
    assert(comment.description == "\u00FF");
    assert(comment.text == "\u00FF");

    assert(
        comment.rawDescription.data ==
        [0xFF, 0x00]
    );

    assert(
        comment.rawText.data ==
        [0xFF, 0x00]
    );
}
