/++
ID3v2.3 private-frame decoding.

A `PRIV` frame contains:

- one null-terminated ISO-8859-1 owner identifier;
- private binary data extending to the frame boundary.

The private binary payload is preserved exactly as physically stored.
ID3v2.3 whole-tag unsynchronisation is retained separately so callers
can later obtain the logical byte stream without losing provenance.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.
+/
module audiotag.id3v2.v23.private_frame;

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
Semantic availability of an ID3v2.3 private frame.
+/
enum Id3v23PrivateAvailability : ubyte
{
    decoded,
    requiresDecompression,
    requiresDecryption,
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.3 `PRIV` frame.
+/
struct Id3v23PrivateFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Decoded ISO-8859-1 owner identifier.
    string ownerIdentifier;

    /// Physical owner bytes excluding the null terminator.
    ByteSpan rawOwnerIdentifier;

    /// Physical private data extending to the frame boundary.
    ByteSpan rawPrivateData;

    /// Whether ID3v2.3 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `PRIV` decoding.
+/
struct Id3v23PrivateOutcome
{
    Id3v23PrivateAvailability availability;
    Id3v23PrivateFrame privateFrame;
    ByteSpan rawPayload;


    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23PrivateAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 private (`PRIV`) frame.

The semantic payload consists of:

    Owner identifier    <ISO-8859-1 text> $00
    Private data        <binary data>

The owner identifier must be terminated inside the bounded frame
payload.

All bytes after that terminator belong to private data and remain opaque
to this codec.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending result instead of a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    Decoded or transformation-pending PRIV outcome, or a structured
    parsing/text error.
+/
ParseResult!Id3v23PrivateOutcome
decodeId3v23PrivateFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "PRIV"
    )
    {
        return
            ParseResult!Id3v23PrivateOutcome
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
            ParseResult!Id3v23PrivateOutcome
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
        Id3v23PrivateAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23PrivateAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23PrivateAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23PrivateAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23PrivateOutcome
                .success(
                    Id3v23PrivateOutcome(
                        availability,
                        Id3v23PrivateFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();


    /*
     * PRIV owner identifiers are always ISO-8859-1 and require a
     * one-byte string terminator.
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
            ParseResult!Id3v23PrivateOutcome
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
            ParseResult!Id3v23PrivateOutcome
                .failure(
                    owner.error
                );
    }


    /*
     * Do not interpret or eagerly de-unsynchronise private data.
     * Preserve its physical representation exactly.
     */
    const rawPrivateData =
        payload.remainingRaw;


    const privateFrame =
        Id3v23PrivateFrame(
            frame.header.sourceOffset,
            owner.value,
            ownerSegment.raw,
            rawPrivateData,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23PrivateOutcome
            .success(
                Id3v23PrivateOutcome(
                    Id3v23PrivateAvailability.decoded,
                    privateFrame,
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


/// A normal PRIV frame preserves owner and binary data.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x10,
            0x00, 0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm',
            0x00,

            0x01, 0x02, 0xFE, 0xFF
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
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const privateFrame =
        result.value.privateFrame;

    assert(privateFrame.sourceOffset == 100);

    assert(
        privateFrame.ownerIdentifier ==
        "example.com"
    );

    assert(
        privateFrame.rawOwnerIdentifier.sourceOffset ==
        110
    );

    assert(
        privateFrame.rawOwnerIdentifier.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );

    assert(
        privateFrame.rawPrivateData.sourceOffset ==
        122
    );

    assert(
        privateFrame.rawPrivateData.data ==
        [0x01, 0x02, 0xFE, 0xFF]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        16
    );

    assert(
        !privateFrame.effectiveUnsynchronisation
    );
}


/// Empty private data is valid.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
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
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.privateFrame.ownerIdentifier ==
        "x"
    );

    assert(
        result.value.privateFrame.rawPrivateData.empty
    );

    assert(
        result.value.privateFrame.rawPrivateData.sourceOffset ==
        212
    );
}


/// An empty owner identifier is valid.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
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
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.privateFrame.ownerIdentifier.length ==
        0
    );

    assert(
        result.value.privateFrame.rawOwnerIdentifier.empty
    );

    assert(
        result.value.privateFrame.rawPrivateData.data ==
        [0xAA]
    );
}


/// ISO-8859-1 owner bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
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
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);

    assert(
        result.value.privateFrame.ownerIdentifier ==
        "caf\u00E9"
    );
}


/// The owner identifier must be terminated inside the frame.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            'a', 'b', 'c'
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
            .decodeId3v23PrivateFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The PRIV codec rejects another frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x00
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
            .decodeId3v23PrivateFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(
        result.error.offset ==
        600
    );
}


/// Compressed private data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',

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
                700
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23PrivateAvailability
            .requiresDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        714
    );
}


/// Encrypted private data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x40,

            0x23,
            0xAA
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
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23PrivateAvailability
            .requiresDecryption
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        811
    );
}


/// Combined private-data transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
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
                900
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23PrivateAvailability
            .requiresDecryptionAndDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        915
    );
}


/// Grouping identity is removed before PRIV semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',

            /*
             * Group symbol + owner "x" + NUL + one private byte.
             */
            0x00, 0x00, 0x00, 0x04,

            0x00, 0x20,

            /*
             * Group symbol.
             */
            0x7A,

            'x',
            0x00,
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
            .decodeId3v23PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.privateFrame.ownerIdentifier ==
        "x"
    );

    assert(
        result.value.privateFrame.rawPrivateData.data ==
        [0xAA]
    );

    assert(
        result.value.privateFrame.rawPrivateData.sourceOffset ==
        1013
    );
}


/// Whole-tag unsynchronisation preserves physical private-data bytes.
unittest
{
    /*
     * Logical frame data:
     *
     *   x 00 FF E0 FF
     *
     * Five logical bytes.
     *
     * Physical frame data:
     *
     *   x 00 FF 00 E0 FF
     *
     * The stuffing byte after the first FF is physical provenance and
     * must not contribute to the frame-header size.
     */
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            'x',
            0x00,

            0xFF, 0x00,
            0xE0,
            0xFF
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23PrivateFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const privateFrame =
        result.value.privateFrame;

    assert(
        privateFrame.ownerIdentifier ==
        "x"
    );

    assert(
        privateFrame.effectiveUnsynchronisation
    );

    assert(
        privateFrame.rawPrivateData.data ==
        [
            0xFF, 0x00,
            0xE0,
            0xFF
        ]
    );

    assert(
        privateFrame.rawPrivateData.sourceOffset ==
        1112
    );
}


/// Stuffing inside the owner does not become its terminator.
unittest
{
    /*
     * Logical owner:
     *
     *   FF
     *
     * followed by its logical terminator and one private byte:
     *
     *   FF 00 AA
     *
     * Physical representation:
     *
     *   FF 00 00 AA
     *
     * The first zero is unsynchronisation stuffing, the second is the
     * actual owner terminator.
     */
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',

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
                1200
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23PrivateFrame(
                true
            );

    assert(result.hasValue);

    const privateFrame =
        result.value.privateFrame;

    assert(
        privateFrame.ownerIdentifier ==
        "\u00FF"
    );

    /*
     * Physical owner provenance includes its stuffing byte but excludes
     * the actual logical terminator.
     */
    assert(
        privateFrame.rawOwnerIdentifier.data ==
        [
            0xFF, 0x00
        ]
    );

    assert(
        privateFrame.rawPrivateData.data ==
        [0xAA]
    );
}
