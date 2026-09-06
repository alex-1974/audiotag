/++
ID3v2.3 unique-file-identifier frame decoding.

A `UFID` frame contains:

- one non-empty, null-terminated ISO-8859-1 owner identifier;
- zero to 64 bytes of opaque identifier data.

The 64-byte limit applies to the logical identifier after ID3v2.3
whole-tag unsynchronisation has been removed. Physical identifier bytes
are preserved exactly as stored for provenance.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.
+/
module audiotag.id3v2.v23.unique_file_identifier;

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

import audiotag.id3v2.v23.text_decode :
    decodeId3v23TextSpan;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding;

import audiotag.id3v2.v23.text_segment :
    takeId3v23TerminatedTextSegment;


/++
Semantic availability of an ID3v2.3 unique-file-identifier frame.
+/
enum Id3v23UniqueFileIdentifierAvailability : ubyte
{
    decoded,
    requiresDecompression,
    requiresDecryption,
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.3 `UFID` frame.
+/
struct Id3v23UniqueFileIdentifierFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Decoded non-empty owner identifier.
    string ownerIdentifier;

    /// Physical owner bytes excluding the null terminator.
    ByteSpan rawOwnerIdentifier;

    /// Physical identifier bytes extending to the frame boundary.
    ByteSpan rawIdentifier;

    /// Identifier length after whole-tag unsynchronisation is removed.
    size_t logicalIdentifierLength;

    /// Whether ID3v2.3 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic UFID decoding.
+/
struct Id3v23UniqueFileIdentifierOutcome
{
    Id3v23UniqueFileIdentifierAvailability availability;
    Id3v23UniqueFileIdentifierFrame uniqueFileIdentifier;
    ByteSpan rawPayload;


    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23UniqueFileIdentifierAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 unique-file-identifier (`UFID`) frame.

The semantic payload consists of:

    Owner identifier    <ISO-8859-1 text> $00
    Identifier          <0..64 opaque logical bytes>

The owner identifier must be non-empty and terminated within the
bounded frame payload.

The identifier is opaque. Its physical representation is retained
unchanged, while its logical length is counted through the ID3v2.3 data
cursor so unsynchronisation stuffing does not count toward the 64-byte
limit.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    Decoded or transformation-pending UFID outcome, or a structured
    parsing/text error.
+/
ParseResult!Id3v23UniqueFileIdentifierOutcome
decodeId3v23UniqueFileIdentifierFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "UFID"
    )
    {
        return
            ParseResult!Id3v23UniqueFileIdentifierOutcome
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
            ParseResult!Id3v23UniqueFileIdentifierOutcome
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
        Id3v23UniqueFileIdentifierAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23UniqueFileIdentifierAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23UniqueFileIdentifierAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23UniqueFileIdentifierAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23UniqueFileIdentifierOutcome
                .success(
                    Id3v23UniqueFileIdentifierOutcome(
                        availability,
                        Id3v23UniqueFileIdentifierFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();


    /*
     * UFID owners are always ISO-8859-1 and must be null-terminated.
     */
    auto ownerResult =
        payload.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    if (
        ownerResult.hasError
    )
    {
        return
            ParseResult!Id3v23UniqueFileIdentifierOutcome
                .failure(
                    ownerResult.error
                );
    }

    const ownerSegment =
        ownerResult.value;


    auto owner =
        decodeId3v23TextSpan(
            ownerSegment.raw,
            Id3v23TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (
        owner.hasError
    )
    {
        return
            ParseResult!Id3v23UniqueFileIdentifierOutcome
                .failure(
                    owner.error
                );
    }


    /*
     * Unlike PRIV, a UFID owner must not be empty.
     */
    if (
        owner.value.length ==
        0
    )
    {
        return
            ParseResult!Id3v23UniqueFileIdentifierOutcome
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
     * Preserve the physical identifier bytes unchanged.
     */
    const rawIdentifier =
        payload.remainingRaw;


    /*
     * Count logical identifier bytes independently.
     *
     * This is essential for ID3v2.3 whole-tag unsynchronisation:
     * physical stuffing bytes must not count against UFID's 64-byte
     * identifier limit.
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
                ParseResult!Id3v23UniqueFileIdentifierOutcome
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
                ParseResult!Id3v23UniqueFileIdentifierOutcome
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


    const uniqueFileIdentifier =
        Id3v23UniqueFileIdentifierFrame(
            frame.header.sourceOffset,
            owner.value,
            ownerSegment.raw,
            rawIdentifier,
            logicalIdentifierLength,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23UniqueFileIdentifierOutcome
            .success(
                Id3v23UniqueFileIdentifierOutcome(
                    Id3v23UniqueFileIdentifierAvailability.decoded,
                    uniqueFileIdentifier,
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


/// A normal UFID frame preserves owner and opaque identifier bytes.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x11,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(
        identifier.sourceOffset ==
        100
    );

    assert(
        identifier.ownerIdentifier ==
        "example.org"
    );

    assert(
        identifier.rawOwnerIdentifier.sourceOffset ==
        110
    );

    assert(
        identifier.rawOwnerIdentifier.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'o', 'r', 'g'
        ]
    );

    assert(
        identifier.rawIdentifier.sourceOffset ==
        122
    );

    assert(
        identifier.rawIdentifier.data ==
        [0x01, 0x02, 0xFE, 0xFF, 0x10]
    );

    assert(
        identifier.logicalIdentifierLength ==
        5
    );

    assert(
        !identifier.effectiveUnsynchronisation
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        17
    );
}


/// An empty binary identifier is valid.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(
        identifier.ownerIdentifier ==
        "x"
    );

    assert(
        identifier.rawIdentifier.empty
    );

    assert(
        identifier.rawIdentifier.sourceOffset ==
        212
    );

    assert(
        identifier.logicalIdentifierLength ==
        0
    );
}


/// The owner identifier must not be empty.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(
        result.error.offset ==
        310
    );

    assert(
        result.error.requested ==
        1
    );

    assert(
        result.error.available ==
        0
    );
}


/// ISO-8859-1 owner bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);

    assert(
        result.value.uniqueFileIdentifier.ownerIdentifier ==
        "caf\u00E9"
    );
}


/// Exactly 64 logical identifier bytes are valid.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x42,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(
        identifier.logicalIdentifierLength ==
        64
    );

    assert(
        identifier.rawIdentifier.length ==
        64
    );
}


/// The 65th logical identifier byte is rejected exactly.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x43,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(
        result.error.offset ==
        676
    );

    assert(
        result.error.requested ==
        65
    );

    assert(
        result.error.available ==
        64
    );
}


/// The owner identifier must terminate within the frame.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

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
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The UFID codec rejects another frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

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
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(
        result.error.offset ==
        800
    );
}


/// Compressed UFID data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',

            /*
             * Four-byte decompressed-size prefix plus opaque payload.
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
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UniqueFileIdentifierAvailability
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


/// Encrypted UFID data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
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
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UniqueFileIdentifierAvailability
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


/// Combined UFID transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
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
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UniqueFileIdentifierAvailability
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


/// Grouping identity is removed before UFID semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',

            /*
             * Group symbol + owner "x" + NUL + one identifier byte.
             */
            0x00, 0x00, 0x00, 0x04,

            0x00, 0x20,

            0x7A,

            'x',
            0x00,
            0xAA
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
            .decodeId3v23UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(
        identifier.ownerIdentifier ==
        "x"
    );

    assert(
        identifier.rawIdentifier.data ==
        [0xAA]
    );

    assert(
        identifier.rawIdentifier.sourceOffset ==
        1213
    );

    assert(
        identifier.logicalIdentifierLength ==
        1
    );
}


/// The 64-byte limit applies after whole-tag unsynchronisation removal.
unittest
{
    /*
     * Logical identifier:
     *
     *   FF + 63 times 11
     *
     * = exactly 64 logical bytes.
     *
     * Physical identifier:
     *
     *   FF 00 + 63 times 11
     *
     * = 65 physical bytes.
     */
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',

            /*
             * owner "x" + NUL + 64 logical identifier bytes.
             */
            0x00, 0x00, 0x00, 0x42,

            0x00, 0x00,

            'x',
            0x00,

            0xFF, 0x00
        ];

    foreach (
        _;
        0 .. 63
    )
    {
        bytes ~= 0x11;
    }

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
            .decodeId3v23UniqueFileIdentifierFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(
        identifier.effectiveUnsynchronisation
    );

    assert(
        identifier.logicalIdentifierLength ==
        64
    );

    assert(
        identifier.rawIdentifier.length ==
        65
    );

    assert(
        identifier.rawIdentifier.sourceOffset ==
        1312
    );

    assert(
        identifier.rawIdentifier.data[0 .. 2] ==
        [0xFF, 0x00]
    );
}


/// A 65-byte logical identifier remains invalid with unsynchronisation.
unittest
{
    /*
     * Logical identifier:
     *
     *   FF + 64 times 11
     *
     * = 65 logical bytes.
     *
     * The first FF is physically stuffed, so the physical identifier
     * is 66 bytes long.
     */
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',

            0x00, 0x00, 0x00, 0x43,

            0x00, 0x00,

            'x',
            0x00,

            0xFF, 0x00
        ];

    foreach (
        _;
        0 .. 64
    )
    {
        bytes ~= 0x11;
    }

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
            .decodeId3v23UniqueFileIdentifierFrame(
                true
            );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    /*
     * Identifier starts physically at 1412:
     *
     * FF at 1412
     * stuffing at 1413
     * then 64 physical 11 bytes at 1414..1477.
     *
     * The final byte is therefore logical identifier byte 65.
     */
    assert(
        result.error.offset ==
        1477
    );

    assert(
        result.error.requested ==
        65
    );

    assert(
        result.error.available ==
        64
    );
}


/// Stuffing inside the owner does not become its terminator.
unittest
{
    /*
     * Logical frame data:
     *
     *   FF 00 AA
     *
     * owner = FF
     * terminator = 00
     * identifier = AA
     *
     * Physical representation:
     *
     *   FF 00 00 AA
     */
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',

            /*
             * Three logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x03,

            0x00, 0x00,

            0xFF, 0x00,
            0x00,
            0xAA
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1500
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23UniqueFileIdentifierFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(
        identifier.ownerIdentifier ==
        "\u00FF"
    );

    assert(
        identifier.rawOwnerIdentifier.sourceOffset ==
        1510
    );

    assert(
        identifier.rawOwnerIdentifier.data ==
        [0xFF, 0x00]
    );

    assert(
        identifier.rawIdentifier.sourceOffset ==
        1513
    );

    assert(
        identifier.rawIdentifier.data ==
        [0xAA]
    );

    assert(
        identifier.logicalIdentifierLength ==
        1
    );

    assert(
        identifier.effectiveUnsynchronisation
    );
}
