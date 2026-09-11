/++
ID3v2.2 unique-file-identifier frame decoding.

A `UFI` frame contains:

- one non-empty, null-terminated ISO-8859-1 owner identifier;
- zero to 64 bytes of opaque identifier data.

The 64-byte limit applies to the logical identifier after ID3v2.2 whole-tag
unsynchronisation has been removed. Physical identifier bytes are preserved
exactly as stored for provenance.

This module preserves native v2.2 semantics and performs no canonical mapping.
+/
module audiotag.id3v2.v22.unique_file_identifier;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.text_decode :
    decodeId3v22TextSpan;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;


/++
Decoded ID3v2.2 `UFI` frame.

`rawOwnerIdentifier` excludes the required null terminator while retaining
physical whole-tag-unsynchronisation stuffing.

`rawIdentifier` contains the opaque physical identifier bytes extending to the
bounded frame-data end.
+/
struct Id3v22UniqueFileIdentifierFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Decoded non-empty owner identifier.
    string ownerIdentifier;

    /// Physical owner bytes excluding the null terminator.
    ByteSpan rawOwnerIdentifier;

    /// Physical identifier bytes extending to the frame boundary.
    ByteSpan rawIdentifier;

    /// Identifier length after whole-tag unsynchronisation is removed.
    size_t logicalIdentifierLength;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ID3v2.2 unique-file-identifier (`UFI`) frame.

The payload consists of:

    Owner identifier    <ISO-8859-1 text> $00
    Identifier          <0..64 opaque logical bytes>

The owner identifier must be non-empty and terminated within the bounded frame
payload.

The identifier is opaque. Its physical representation is retained unchanged,
while its logical length is counted through `Id3v22DataCursor` so
unsynchronisation stuffing does not count toward the 64-byte limit.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native `UFI` frame or a structured parsing/text error.
+/
ParseResult!Id3v22UniqueFileIdentifierFrame
decodeId3v22UniqueFileIdentifierFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "UFI"
    )
    {
        return
            ParseResult!Id3v22UniqueFileIdentifierFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }


    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );


    /*
     * UFI owners are always ISO-8859-1 and must be null-terminated.
     */
    auto ownerResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (
        ownerResult.hasError
    )
    {
        return
            ParseResult!Id3v22UniqueFileIdentifierFrame
                .failure(
                    ownerResult.error
                );
    }

    const ownerSegment =
        ownerResult.value;


    auto owner =
        decodeId3v22TextSpan(
            ownerSegment.raw,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (
        owner.hasError
    )
    {
        return
            ParseResult!Id3v22UniqueFileIdentifierFrame
                .failure(
                    owner.error
                );
    }


    /*
     * The v2.2 specification says a zero byte directly after the frame size
     * invalidates/voids the frame. Model that as a non-empty owner
     * requirement in strict decoding.
     */
    if (
        owner.value.length ==
        0
    )
    {
        return
            ParseResult!Id3v22UniqueFileIdentifierFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        ownerSegment.terminatorSourceOffset,
                        1,
                        0
                    )
                );
    }


    /*
     * Preserve the physical identifier bytes exactly.
     */
    const rawIdentifier =
        payload.remainingRaw;


    /*
     * Count logical identifier bytes independently. Physical unsync stuffing
     * must not count against the 64-byte UFI limit.
     */
    auto identifierCursor =
        payload;

    size_t logicalIdentifierLength;

    while (
        !identifierCursor.empty
    )
    {
        auto byteResult =
            identifierCursor.takeByte();

        if (
            byteResult.hasError
        )
        {
            return
                ParseResult!Id3v22UniqueFileIdentifierFrame
                    .failure(
                        byteResult.error
                    );
        }

        ++logicalIdentifierLength;

        if (
            logicalIdentifierLength >
            64
        )
        {
            return
                ParseResult!Id3v22UniqueFileIdentifierFrame
                    .failure(
                        ParseError(
                            ParseErrorCode.invalidLength,
                            byteResult.value.sourceOffset,
                            logicalIdentifierLength,
                            64
                        )
                    );
        }
    }


    return
        ParseResult!Id3v22UniqueFileIdentifierFrame
            .success(
                Id3v22UniqueFileIdentifierFrame(
                    frame.header.sourceOffset,
                    owner.value,
                    ownerSegment.raw,
                    rawIdentifier,
                    logicalIdentifierLength,
                    tagUnsynchronised
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


/// A normal UFI frame preserves owner and opaque identifier bytes.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x11,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'o', 'r', 'g',
            0x00,

            0x01, 0x02, 0xFE, 0xFF, 0x10
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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasValue);

    const identifier =
        result.value;

    assert(identifier.sourceOffset == 100);
    assert(identifier.ownerIdentifier == "example.org");

    assert(identifier.rawOwnerIdentifier.sourceOffset == 106);

    assert(
        identifier.rawOwnerIdentifier.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'o', 'r', 'g'
        ]
    );

    assert(identifier.rawIdentifier.sourceOffset == 118);

    assert(
        identifier.rawIdentifier.data ==
        [0x01, 0x02, 0xFE, 0xFF, 0x10]
    );

    assert(identifier.logicalIdentifierLength == 5);
    assert(!identifier.effectiveUnsynchronisation);
}


/// An empty binary identifier is valid.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x02,

            'x',
            0x00
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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasValue);

    const identifier =
        result.value;

    assert(identifier.ownerIdentifier == "x");
    assert(identifier.rawIdentifier.empty);
    assert(identifier.rawIdentifier.sourceOffset == 208);
    assert(identifier.logicalIdentifierLength == 0);
}


/// The owner identifier must not be empty.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x02,

            0x00,
            0xAA
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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 306);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);
}


/// ISO-8859-1 owner bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x05,

            'c', 'a', 'f',
            0xE9,
            0x00
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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.ownerIdentifier == "caf\u00E9");
}


/// Exactly 64 logical identifier bytes are valid.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x42,

            'x',
            0x00
        ];

    foreach (
        i;
        0 .. 64
    )
    {
        bytes ~=
            cast(ubyte) i;
    }

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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasValue);

    assert(result.value.logicalIdentifierLength == 64);
    assert(result.value.rawIdentifier.length == 64);
}


/// The 65th logical identifier byte is rejected exactly.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x43,

            'x',
            0x00
        ];

    foreach (
        i;
        0 .. 65
    )
    {
        bytes ~=
            cast(ubyte) i;
    }

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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 672);
    assert(result.error.requested == 65);
    assert(result.error.available == 64);
}


/// The owner identifier must terminate within the frame.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I',
            0x00, 0x00, 0x03,

            'a', 'b', 'c'
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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 706);
}


/// The UFI codec rejects a different frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'T', '2',
            0x00, 0x00, 0x01,

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
            .decodeId3v22UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 800);
}


/// Whole-tag unsynchronisation preserves physical identifier bytes.
unittest
{
    /*
     * Logical payload:
     *
     *   x 00
     *   FF E1
     *
     * Physical payload:
     *
     *   x 00
     *   FF 00 E1
     */
    const ubyte[] bytes =
        [
            'U', 'F', 'I',

            /*
             * Four logical frame-data bytes.
             */
            0x00, 0x00, 0x04,

            'x',
            0x00,

            0xFF, 0x00,
            0xE1
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
    assert(frame.value.header.size == 4);
    assert(frame.value.data.length == 5);

    auto result =
        frame.value
            .decodeId3v22UniqueFileIdentifierFrame(
                true
            );

    assert(result.hasValue);

    const identifier =
        result.value;

    assert(identifier.effectiveUnsynchronisation);
    assert(identifier.ownerIdentifier == "x");
    assert(identifier.logicalIdentifierLength == 2);

    assert(
        identifier.rawIdentifier.data ==
        [0xFF, 0x00, 0xE1]
    );
}


/// Unsynchronisation stuffing inside the owner remains provenance, not data.
unittest
{
    /*
     * Logical owner:
     *
     *   x FF 00
     *
     * Physical owner + terminator:
     *
     *   x FF 00 00
     *
     * The first zero after FF is stuffing. The second is the real owner
     * terminator.
     */
    const ubyte[] bytes =
        [
            'U', 'F', 'I',

            /*
             * Three logical frame-data bytes:
             * x, FF, terminator.
             */
            0x00, 0x00, 0x03,

            'x',
            0xFF, 0x00,
            0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UniqueFileIdentifierFrame(
                true
            );

    assert(result.hasValue);

    assert(
        result.value.ownerIdentifier ==
        "x\u00FF"
    );

    assert(
        result.value.rawOwnerIdentifier.data ==
        [
            'x',
            0xFF, 0x00
        ]
    );

    assert(result.value.rawIdentifier.empty);
    assert(result.value.logicalIdentifierLength == 0);
}
