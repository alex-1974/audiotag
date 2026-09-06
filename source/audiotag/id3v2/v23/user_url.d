/++
ID3v2.3 user-defined URL-link frame decoding.

A `WXXX` frame contains:

- one text-encoding marker;
- one terminated description using that encoding;
- one URL encoded as ISO-8859-1.

The encoding marker applies only to the description. The URL is always
ISO-8859-1 regardless of the selected description encoding.

A URL terminator is optional. If present, following bytes are ignored
semantically but preserved as provenance.

Compressed or encrypted frames remain structurally valid but cannot yet
be semantically decoded.

ID3v2.3 tag-level unsynchronisation is reversed while traversing the
bounded physical frame-data representation.
+/
module audiotag.id3v2.v23.user_url;

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
    Id3v23TextEncoding,
    parseId3v23TextEncoding;

import audiotag.id3v2.v23.text_segment :
    takeId3v23TerminatedTextSegment;


/++
Semantic availability of an ID3v2.3 user-defined URL-link frame.
+/
enum Id3v23UserUrlAvailability : ubyte
{
    /// Description and URL were decoded successfully.
    decoded,

    /// Payload must be decompressed first.
    requiresDecompression,

    /// Payload must be decrypted first.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.3 `WXXX` frame.

`rawDescription` excludes the mandatory description terminator while
retaining physical tag-level unsynchronisation stuffing.

`rawUrl` excludes an optional URL terminator.

`ignoredTrailingData` preserves all physical bytes after an encountered
URL terminator.
+/
struct Id3v23UserUrlFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by the description.
    Id3v23TextEncoding descriptionEncoding;

    /// Decoded user-defined description.
    string description;

    /// Decoded ISO-8859-1 URL.
    string url;

    /// Physical description bytes, excluding its terminator.
    ByteSpan rawDescription;

    /// Physical URL bytes, excluding a terminator if present.
    ByteSpan rawUrl;

    /// Physical bytes following a URL terminator, if present.
    ByteSpan ignoredTrailingData;

    /// Whether ID3v2.3 tag-level unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `WXXX` decoding.

When `availability == decoded`, `link` contains the decoded frame.

Otherwise `rawPayload` preserves the still-transformed semantic payload
after structural frame-format additions have been removed.
+/
struct Id3v23UserUrlOutcome
{
    /// Semantic availability.
    Id3v23UserUrlAvailability availability;

    /// Decoded frame when available.
    Id3v23UserUrlFrame link;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;


    /// Whether semantic data is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v23UserUrlAvailability.decoded;
    }
}


/++
Decodes an ID3v2.3 user-defined URL-link (`WXXX`) frame.

The semantic payload consists of:

    Text encoding    $xx
    Description      <text according to encoding> $00 (00)
    URL              <ISO-8859-1 text>

The description terminator is mandatory.

The URL always uses ISO-8859-1 and is independent of the description
encoding.

A URL terminator is optional. If present, all following bytes are
ignored semantically but preserved in `ignoredTrailingData`.

Compression, encryption and grouping additions are handled by the lower
frame-data structural layer.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.3 frame.
    tagUnsynchronised = Whether ID3v2.3 tag-level unsynchronisation
        applies.

Returns:
    Decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v23UserUrlOutcome
decodeId3v23UserUrlFrame(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "WXXX"
    )
    {
        return
            ParseResult!Id3v23UserUrlOutcome
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
            ParseResult!Id3v23UserUrlOutcome
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
        Id3v23UserUrlAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v23UserUrlAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (
            frame.header.compressed
        )
        {
            availability =
                Id3v23UserUrlAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v23UserUrlAvailability
                    .requiresDecryption;
        }

        return
            ParseResult!Id3v23UserUrlOutcome
                .success(
                    Id3v23UserUrlOutcome(
                        availability,
                        Id3v23UserUrlFrame.init,
                        layout.rawPayload
                    )
                );
    }


    auto payload =
        layout.payloadCursor();


    /*
     * WXXX begins with an encoding marker for the description only.
     */
    auto encodingResult =
        payload.parseId3v23TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v23UserUrlOutcome
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * The description must be terminated according to its declared
     * encoding.
     */
    auto descriptionResult =
        payload.takeId3v23TerminatedTextSegment(
            encoding
        );

    if (
        descriptionResult.hasError
    )
    {
        return
            ParseResult!Id3v23UserUrlOutcome
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;


    auto description =
        decodeId3v23TextSpan(
            descriptionSegment.raw,
            encoding,
            layout.effectiveUnsynchronisation
        );

    if (
        description.hasError
    )
    {
        return
            ParseResult!Id3v23UserUrlOutcome
                .failure(
                    description.error
                );
    }


    /*
     * The URL is always ISO-8859-1. Search for its optional one-byte
     * terminator independently of the description encoding.
     */
    ByteSpan rawUrl;
    ByteSpan ignoredTrailingData;

    auto urlSegmentResult =
        payload.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    if (
        urlSegmentResult.hasValue
    )
    {
        rawUrl =
            urlSegmentResult.value.raw;

        ignoredTrailingData =
            payload.remainingRaw;
    }
    else
    {
        if (
            urlSegmentResult.error.code !=
            ParseErrorCode.patternNotFound
        )
        {
            return
                ParseResult!Id3v23UserUrlOutcome
                    .failure(
                        urlSegmentResult.error
                    );
        }

        /*
         * The URL terminator is optional. The enclosing frame boundary
         * defines the URL extent.
         *
         * The unsuccessful segment search was atomic.
         */
        rawUrl =
            payload.remainingRaw;

        ignoredTrailingData =
            rawUrl.subspan(
                rawUrl.length,
                0
            );
    }


    auto url =
        decodeId3v23TextSpan(
            rawUrl,
            Id3v23TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (
        url.hasError
    )
    {
        return
            ParseResult!Id3v23UserUrlOutcome
                .failure(
                    url.error
                );
    }


    const link =
        Id3v23UserUrlFrame(
            frame.header.sourceOffset,
            encoding,
            description.value,
            url.value,
            descriptionSegment.raw,
            rawUrl,
            ignoredTrailingData,
            layout.effectiveUnsynchronisation
        );


    return
        ParseResult!Id3v23UserUrlOutcome
            .success(
                Id3v23UserUrlOutcome(
                    Id3v23UserUrlAvailability.decoded,
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


/// A Latin-1 description precedes an ISO-8859-1 URL.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x11,
            0x00, 0x00,

            0x00,

            'h', 'o', 'm', 'e',
            0x00,

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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(link.sourceOffset == 100);

    assert(
        link.descriptionEncoding ==
        Id3v23TextEncoding.latin1
    );

    assert(link.description == "home");
    assert(link.url == "example.com");

    assert(
        link.rawDescription.sourceOffset ==
        111
    );

    assert(
        link.rawDescription.data ==
        ['h', 'o', 'm', 'e']
    );

    assert(
        link.rawUrl.sourceOffset ==
        116
    );

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
        127
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        110
    );

    assert(result.value.rawPayload.length == 17);

    assert(!link.effectiveUnsynchronisation);
}


/// A Unicode description does not change the URL encoding.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00,

            0x01,

            /*
             * Description "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            /*
             * URL remains ISO-8859-1.
             */
            'u', 'r', 'l'
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(
        link.descriptionEncoding ==
        Id3v23TextEncoding.utf16
    );

    assert(link.description == "A");
    assert(link.url == "url");

    assert(
        link.rawDescription.data ==
        [
            0xFF, 0xFE,
            0x41, 0x00
        ]
    );

    assert(link.rawUrl.sourceOffset == 217);

    assert(
        link.rawUrl.data ==
        ['u', 'r', 'l']
    );
}


/// A URL terminator causes following bytes to be ignored.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x00,
            'x',
            0x00,

            'u', 'r', 'l',
            0x00,

            'A', 'B'
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(link.description == "x");
    assert(link.url == "url");

    assert(
        link.rawUrl.data ==
        ['u', 'r', 'l']
    );

    assert(
        link.ignoredTrailingData.data ==
        ['A', 'B']
    );

    assert(
        link.ignoredTrailingData.sourceOffset ==
        317
    );
}


/// Description and URL may both be empty.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(link.description.length == 0);
    assert(link.url.length == 0);

    assert(link.rawDescription.empty);
    assert(link.rawDescription.sourceOffset == 411);

    assert(link.rawUrl.empty);
    assert(link.rawUrl.sourceOffset == 412);

    assert(link.ignoredTrailingData.empty);
    assert(link.ignoredTrailingData.sourceOffset == 412);
}


/// The URL remains ISO-8859-1 even when the description is Unicode.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Encoding + Unicode description + terminator + 2 URL bytes.
             */
            0x00, 0x00, 0x00, 0x09,

            0x00, 0x00,

            0x01,

            /*
             * Big-endian description "A".
             */
            0xFE, 0xFF,
            0x00, 0x41,
            0x00, 0x00,

            /*
             * ISO-8859-1 URL bytes.
             */
            'x',
            0xE9
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);

    assert(
        result.value.link.description ==
        "A"
    );

    assert(
        result.value.link.url ==
        "x\u00E9"
    );
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x00,
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 611);
    assert(result.error.requested == 1);
    assert(result.error.available == 3);
}


/// ID3v2.4-only description encoding markers remain invalid.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            /*
             * UTF-8 marker is undefined in ID3v2.3.
             */
            0x03,

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
            .decodeId3v23UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 710);
}


/// The WXXX codec rejects ordinary URL-link frames.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            'x'
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 800);
}


/// A non-empty Unicode description requires its own BOM.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Encoding + description + terminator + URL.
             */
            0x00, 0x00, 0x00, 0x06,

            0x00, 0x00,

            0x01,

            /*
             * "A" without a BOM.
             */
            0x00, 0x41,

            0x00, 0x00,

            'u'
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );

    assert(result.error.offset == 911);
}


/// Compressed WXXX data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Decompressed-size prefix + opaque payload.
             */
            0x00, 0x00, 0x00, 0x05,

            0x00, 0x80,

            /*
             * Decompressed size.
             */
            0x00, 0x00, 0x00, 0x01,

            /*
             * Opaque compressed semantic payload.
             */
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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UserUrlAvailability
            .requiresDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1014
    );
}


/// Encrypted WXXX data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Encryption method + opaque URL payload.
             */
            0x00, 0x00, 0x00, 0x02,

            0x00, 0x40,

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
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UserUrlAvailability
            .requiresDecryption
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1111
    );
}


/// Combined WXXX transformations remain explicit.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Decompressed size + method + opaque payload.
             */
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
                1200
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v23UserUrlAvailability
            .requiresDecryptionAndDecompression
    );

    assert(
        result.value.rawPayload.data ==
        [0xAA]
    );

    assert(
        result.value.rawPayload.sourceOffset ==
        1215
    );
}


/// Grouping identity is removed before WXXX semantic decoding.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Group symbol + encoding + description terminator + URL.
             */
            0x00, 0x00, 0x00, 0x06,

            0x00, 0x20,

            /*
             * Group symbol.
             */
            0x7A,

            /*
             * Latin-1 empty description.
             */
            0x00,
            0x00,

            'u', 'r', 'l'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1300
            )
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v23UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.link.description.length ==
        0
    );

    assert(
        result.value.link.url ==
        "url"
    );

    assert(
        result.value.link.rawUrl.sourceOffset ==
        1313
    );
}


/// Whole-tag unsynchronisation applies to description and URL traversal.
unittest
{
    /*
     * Logical frame data:
     *
     *   00
     *   FF 00
     *   u FF 00
     *
     * Meaning:
     *
     *   encoding = Latin-1
     *   description = FF
     *   description terminator
     *   URL = u FF
     *   URL terminator
     *
     * Physical representation:
     *
     *   00
     *   FF 00 00
     *   u FF 00 00
     */
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Six logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x06,

            0x00, 0x00,

            0x00,

            /*
             * Description logical FF + terminator.
             */
            0xFF, 0x00,
            0x00,

            /*
             * URL logical "u FF" + terminator.
             */
            'u',
            0xFF, 0x00,
            0x00
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
            .decodeId3v23UserUrlFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.decoded);

    const link =
        result.value.link;

    assert(
        link.description ==
        "\u00FF"
    );

    assert(
        link.url ==
        "u\u00FF"
    );

    assert(link.effectiveUnsynchronisation);

    /*
     * Both provenance spans retain their physical stuffing bytes.
     */
    assert(
        link.rawDescription.data ==
        [
            0xFF, 0x00
        ]
    );

    assert(
        link.rawUrl.data ==
        [
            'u',
            0xFF, 0x00
        ]
    );

    assert(
        link.rawDescription.sourceOffset ==
        1411
    );

    assert(
        link.rawUrl.sourceOffset ==
        1414
    );

    assert(link.ignoredTrailingData.empty);

    assert(
        link.ignoredTrailingData.sourceOffset ==
        1418
    );
}


/// Unsynchronisation inside a Unicode description BOM is reversed.
unittest
{
    /*
     * Logical frame data:
     *
     *   01
     *   FF FE 41 00
     *   00 00
     *   u
     *
     * Physical description begins:
     *
     *   FF 00 FE
     */
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Eight logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x08,

            0x00, 0x00,

            0x01,

            /*
             * Little-endian BOM with stuffing.
             */
            0xFF, 0x00,
            0xFE,

            /*
             * "A".
             */
            0x41, 0x00,

            /*
             * Description terminator.
             */
            0x00, 0x00,

            /*
             * ISO-8859-1 URL.
             */
            'u'
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
            .decodeId3v23UserUrlFrame(
                true
            );

    assert(result.hasValue);

    const link =
        result.value.link;

    assert(link.description == "A");
    assert(link.url == "u");

    assert(
        link.rawDescription.data ==
        [
            0xFF, 0x00,
            0xFE,
            0x41, 0x00
        ]
    );

    assert(
        link.rawUrl.sourceOffset ==
        1518
    );
}


/// Stuffing immediately before the URL terminator is preserved as URL data.
unittest
{
    /*
     * Logical URL:
     *
     *   FF 00
     *
     * Physical URL:
     *
     *   FF 00 00
     *
     * The first zero is stuffing; the second is the URL terminator.
     */
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',

            /*
             * Encoding + empty description terminator + FF + URL terminator.
             */
            0x00, 0x00, 0x00, 0x04,

            0x00, 0x00,

            0x00,
            0x00,

            0xFF, 0x00,
            0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1600
            ),
            true
        );

    auto frame =
        cursor.parseId3v23FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v23UserUrlFrame(
                true
            );

    assert(result.hasValue);

    const link =
        result.value.link;

    assert(link.description.length == 0);

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

    assert(link.ignoredTrailingData.empty);

    assert(
        link.ignoredTrailingData.sourceOffset ==
        1615
    );
}
