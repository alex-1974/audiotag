/++
ID3v2.3 URL-link frame decoding.

This module decodes ordinary `W***` URL-link frames, excluding the
structurally different `WXXX` frame.

Ordinary URL-link frames contain no encoding marker. Their URL is an
ISO-8859-1 text string extending to the frame boundary.

If a string terminator occurs, following bytes are ignored semantically
but preserved as source provenance.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.

ID3v2.3 tag-level unsynchronisation is reversed while traversing the
bounded physical frame-data representation.
+/
module audiotag.id3v2.v23.url_link;

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
Semantic availability of an ordinary ID3v2.3 URL-link frame.
+/
enum Id3v23UrlLinkAvailability : ubyte
{
    /// URL was decoded successfully.
    decoded,

    /// Payload must be decompressed first.
    requiresDecompression,

    /// Payload must be decrypted first.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ordinary ID3v2.3 URL-link frame.

This represents `W***` frames except `WXXX`.

`rawUrl` contains the physical URL bytes excluding an optional
terminator while retaining whole-tag unsynchronisation stuffing.

`ignoredTrailingData` contains physical bytes after an encountered URL
terminator.
+/
struct Id3v23UrlLinkFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Native four-character frame identifier.
    char[4] id;

    /// Decoded ISO-8859-1 URL.
    string url;

    /// Physical bytes belonging to the URL, excluding a terminator.
    ByteSpan rawUrl;

    /// Physical bytes following a URL terminator, if present.
    ByteSpan ignoredTrailingData;

    /// Whether ID3v2.3 tag-level unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic URL-link decoding.

When `availability == decoded`, `link` contains the decoded frame.

Otherwise `rawPayload` preserves the still-transformed semantic payload
after structural frame-format additions have been removed.
+/
struct Id3v23UrlLinkOutcome
{
    /// Semantic availability.
    Id3v23UrlLinkAvailability availability;

    /// Decoded URL frame when available.
    Id3v23UrlLinkFrame link;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;


    /// Whether the URL is semantically available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23UrlLinkAvailability.decoded;
    }
}


/++
Decodes an ordinary ID3v2.3 URL-link frame.

The frame identifier must begin with `W` and must not be `WXXX`.

Ordinary URL-link frames contain exactly one ISO-8859-1 URL and no text
encoding marker.

A URL terminator is optional. If present, bytes following it are ignored
semantically as required by ID3v2.3, but remain preserved in
`ignoredTrailingData`.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 tag-level unsynchronisation
        applies.

Returns:
    Decoded or transformation-pending URL outcome, or a structured error
    for an incompatible frame.
+/
ParseResult!Id3v23UrlLinkOutcome
decodeId3v23UrlLinkFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[0] != 'W' ||
        frame.header.id[] == "WXXX"
    )
    {
        return
            ParseResult!Id3v23UrlLinkOutcome
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
            ParseResult!Id3v23UrlLinkOutcome
                .failure(
                    layoutResult.error
                );
    }

    const layout =
        layoutResult.value;


    /*
     * Compression and encryption transform the semantic payload.
     * frame_data.d has already consumed their structural prefixes.
     */
    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v23UrlLinkAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23UrlLinkAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23UrlLinkAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23UrlLinkAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23UrlLinkOutcome
                .success(
                    Id3v23UrlLinkOutcome(
                        availability,
                        Id3v23UrlLinkFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();

    ByteSpan rawUrl;
    ByteSpan ignoredTrailingData;


    /*
     * Search for the optional ISO-8859-1 terminator transactionally.
     */
    auto segmentResult =
        payload.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    if (
        segmentResult.hasValue
    )
    {
        rawUrl =
            segmentResult.value.raw;

        /*
         * The segment parser consumed the terminator. Everything
         * physically remaining is semantically ignored extension data.
         */
        ignoredTrailingData =
            payload.remainingRaw;
    }
    else
    {
        if (
            segmentResult.error.code !=
            ParseErrorCode.patternNotFound
        )
        {
            return
                ParseResult!Id3v23UrlLinkOutcome
                    .failure(
                        segmentResult.error
                    );
        }

        /*
         * No terminator is required. The enclosing frame boundary
         * defines the URL extent.
         *
         * The failed segment search was atomic.
         */
        rawUrl =
            payload.remainingRaw;

        ignoredTrailingData =
            rawUrl.subspan(
                rawUrl.length,
                0
            );
    }


    auto decoded =
        decodeId3v23TextSpan(
            rawUrl,
            Id3v23TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (
        decoded.hasError
    )
    {
        return
            ParseResult!Id3v23UrlLinkOutcome
                .failure(
                    decoded.error
                );
    }


    const link =
        Id3v23UrlLinkFrame(
            frame.header.sourceOffset,
            frame.header.id,
            decoded.value,
            rawUrl,
            ignoredTrailingData,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23UrlLinkOutcome
            .success(
                Id3v23UrlLinkOutcome(
                    Id3v23UrlLinkAvailability.decoded,
                    link,
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


/// A normal URL-link frame extends to the frame boundary.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(link.sourceOffset == 100);
    assert(link.id[] == "WOAR");
    assert(link.url == "example.com");

    assert(link.rawUrl.sourceOffset == 110);
    assert(link.rawUrl.length == 11);

    assert(
        link.rawUrl.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );

    assert(link.ignoredTrailingData.empty);

    assert(
        link.ignoredTrailingData.sourceOffset ==
        121
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(
        result.value.rawPayload.length ==
        11
    );

    assert(!link.effectiveUnsynchronisation);
}


/// A URL terminator causes subsequent bytes to be ignored.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'C', 'O', 'P',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            'u', 'r', 'l',
            0x00,

            'i', 'g', 'n', 'o', 'r'
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(link.url == "url");

    assert(
        link.rawUrl.data ==
        ['u', 'r', 'l']
    );

    assert(link.rawUrl.sourceOffset == 210);

    assert(
        link.ignoredTrailingData.data ==
        ['i', 'g', 'n', 'o', 'r']
    );

    assert(
        link.ignoredTrailingData.sourceOffset ==
        214
    );
}


/// Relative URLs are accepted.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'F',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00,

            '.', '.', '/', 'a', 'u', 'd', 'i', 'o',
            '.', 'x'
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);

    assert(
        result.value.link.url ==
        "../audio.x"
    );
}


/// ISO-8859-1 URL bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            'x',
            0xE9
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);

    assert(
        result.value.link.url ==
        "x\u00E9"
    );
}


/// A terminator may represent an empty URL.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'P', 'U', 'B',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x00
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.link.url.length ==
        0
    );

    assert(result.value.link.rawUrl.empty);

    assert(
        result.value.link.rawUrl.sourceOffset ==
        510
    );

    assert(
        result.value.link
            .ignoredTrailingData.empty
    );

    assert(
        result.value.link
            .ignoredTrailingData.sourceOffset ==
        511
    );
}


/// WXXX is deliberately excluded from the ordinary URL codec.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            'x'
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 600);
}


/// A non-URL frame is rejected.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            'A'
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// Compressed URL data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',

            /*
             * Decompressed-size prefix + opaque payload.
             */
            0x00, 0x00, 0x00, 0x05,

            /*
             * Compression.
             */
            0x00, 0x80,

            /*
             * Decompressed size = 1.
             */
            0x00, 0x00, 0x00, 0x01,

            /*
             * Opaque compressed URL.
             */
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UrlLinkAvailability
            .requiresDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        814
    );
}


/// Encrypted URL data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',

            /*
             * Encryption method + ciphertext.
             */
            0x00, 0x00, 0x00, 0x02,

            /*
             * Encryption.
             */
            0x00, 0x40,

            /*
             * Method.
             */
            0x23,

            /*
             * Opaque ciphertext.
             */
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UrlLinkAvailability
            .requiresDecryption
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        911
    );
}


/// Combined URL transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',

            /*
             * Decompressed size + encryption method + payload.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * Compression + encryption.
             */
            0x00, 0xC0,

            0x00, 0x00, 0x00, 0x01,
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UrlLinkAvailability
            .requiresDecryptionAndDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1015
    );
}


/// Grouping identity is removed before URL decoding.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',

            /*
             * Group symbol + URL.
             */
            0x00, 0x00, 0x00, 0x04,

            /*
             * Grouping identity.
             */
            0x00, 0x20,

            /*
             * Group symbol.
             */
            0x7A,

            'u', 'r', 'l'
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
            .decodeId3v23UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.link.url ==
        "url"
    );

    assert(
        result.value.link.rawUrl.sourceOffset ==
        1111
    );
}


/// Whole-tag unsynchronisation is reversed before URL decoding.
unittest
{
    /*
     * Logical frame data:
     *
     *   x FF E1
     *
     * Physical frame data:
     *
     *   x FF 00 E1
     */
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',

            /*
             * Three logical URL bytes.
             */
            0x00, 0x00, 0x00, 0x03,

            0x00, 0x00,

            'x',
            0xFF, 0x00,
            0xE1
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
            .decodeId3v23UrlLinkFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(
        link.url ==
        "x\u00FF\u00E1"
    );

    assert(link.effectiveUnsynchronisation);

    /*
     * Physical provenance retains the stuffing byte.
     */
    assert(
        link.rawUrl.data ==
        [
            'x',
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        link.rawUrl.sourceOffset ==
        1210
    );
}


/// Stuffing immediately before a URL terminator is not the terminator.
unittest
{
    /*
     * Logical URL:
     *
     *   FF 00
     *
     * Physical representation:
     *
     *   FF 00 00
     *
     * First zero is unsynchronisation stuffing; second is the URL
     * terminator.
     */
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',

            /*
             * Two logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x00,

            0xFF, 0x00,
            0x00
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
            .decodeId3v23UrlLinkFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(
        link.url ==
        "\u00FF"
    );

    assert(
        link.rawUrl.data ==
        [
            0xFF, 0x00
        ]
    );

    assert(link.rawUrl.length == 2);

    assert(
        link.ignoredTrailingData.empty
    );

    assert(
        link.ignoredTrailingData.sourceOffset ==
        1313
    );
}


/// Trailing data after a logical terminator remains physical provenance.
unittest
{
    /*
     * Logical frame data:
     *
     *   u 00 FF
     *
     * The final FF is semantically ignored.
     *
     * Because the tag is unsynchronised, that ignored FF may itself
     * carry a physical stuffing zero.
     */
    const ubyte[] bytes =
        [
            'W', 'C', 'O', 'P',

            /*
             * Three logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x03,

            0x00, 0x00,

            'u',
            0x00,

            0xFF, 0x00
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
            .decodeId3v23UrlLinkFrame(
                true
            );

    assert(result.hasValue);

    const link =
        result.value.link;

    assert(link.url == "u");

    assert(
        link.ignoredTrailingData.data ==
        [
            0xFF, 0x00
        ]
    );

    assert(
        link.ignoredTrailingData.sourceOffset ==
        1412
    );
}
