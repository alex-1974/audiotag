/++
ID3v2.4 user-defined URL-link frame decoding.

A `WXXX` frame contains:

- one text-encoding marker;
- one terminated description using that encoding;
- one URL encoded as ISO-8859-1.

A URL terminator is optional. If present, following bytes are ignored
semantically but preserved as provenance.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.user_url;

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

import audiotag.id3v2.v24.text_decode :
    decodeId3v24TextSpan;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding,
    parseId3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/++
Semantic availability of a user-defined URL-link frame.
+/
enum Id3v24UserUrlAvailability : ubyte
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
Decoded ID3v2.4 `WXXX` frame.
+/
struct Id3v24UserUrlFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by the description.
    Id3v24TextEncoding descriptionEncoding;

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

    /// Whether unsynchronisation was effective for this frame.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `WXXX` decoding.
+/
struct Id3v24UserUrlOutcome
{
    /// Semantic availability.
    Id3v24UserUrlAvailability availability;

    /// Decoded frame when available.
    Id3v24UserUrlFrame link;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;

    /// Whether semantic data is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24UserUrlAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 user-defined URL-link (`WXXX`) frame.

The description is terminated according to its encoding. The
following URL is always ISO-8859-1.

If the URL itself contains a string terminator, subsequent bytes are
ignored semantically but remain preserved.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level unsynchronisation applies.

Returns:
    Decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v24UserUrlOutcome
decodeId3v24UserUrlFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "WXXX")
    {
        return ParseResult!Id3v24UserUrlOutcome.failure(
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
        return ParseResult!Id3v24UserUrlOutcome.failure(
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
        Id3v24UserUrlAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24UserUrlAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24UserUrlAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24UserUrlAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24UserUrlOutcome.success(
            Id3v24UserUrlOutcome(
                availability,
                Id3v24UserUrlFrame.init,
                layout.rawPayload
            )
        );
    }

    auto payload =
        layout.payloadCursor();

    auto encodingResult =
        payload.parseId3v24TextEncoding();

    if (encodingResult.hasError)
    {
        return ParseResult!Id3v24UserUrlOutcome.failure(
            encodingResult.error
        );
    }

    const encoding =
        encodingResult.value;

    auto descriptionResult =
        payload.takeId3v24TerminatedTextSegment(
            encoding
        );

    if (descriptionResult.hasError)
    {
        return ParseResult!Id3v24UserUrlOutcome.failure(
            descriptionResult.error
        );
    }

    const descriptionSegment =
        descriptionResult.value;

    auto description =
        decodeId3v24TextSpan(
            descriptionSegment.raw,
            encoding,
            layout.effectiveUnsynchronisation
        );

    if (description.hasError)
    {
        return ParseResult!Id3v24UserUrlOutcome.failure(
            description.error
        );
    }

    ByteSpan rawUrl;
    ByteSpan ignoredTrailingData;

    auto urlSegmentResult =
        payload.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.latin1
        );

    if (urlSegmentResult.hasValue)
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
            return ParseResult!Id3v24UserUrlOutcome.failure(
                urlSegmentResult.error
            );
        }

        rawUrl =
            payload.remainingRaw;

        ignoredTrailingData =
            rawUrl.subspan(
                rawUrl.length,
                0
            );
    }

    auto url =
        decodeId3v24TextSpan(
            rawUrl,
            Id3v24TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (url.hasError)
    {
        return ParseResult!Id3v24UserUrlOutcome.failure(
            url.error
        );
    }

    auto link =
        Id3v24UserUrlFrame(
            frame.header.sourceOffset,
            encoding,
            description.value,
            url.value,
            descriptionSegment.raw,
            rawUrl,
            ignoredTrailingData,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24UserUrlOutcome.success(
        Id3v24UserUrlOutcome(
            Id3v24UserUrlAvailability.decoded,
            link,
            layout.rawPayload
        )
    );
}


import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A UTF-8 description precedes an ISO-8859-1 URL.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x11,
            0x00, 0x00,

            0x03,
            'h', 'o', 'm', 'e',
            0x00,
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link = result.value.link;

    assert(link.sourceOffset == 100);
    assert(
        link.descriptionEncoding ==
        Id3v24TextEncoding.utf8
    );

    assert(link.description == "home");
    assert(link.url == "example.com");

    assert(link.rawDescription.sourceOffset == 111);
    assert(link.rawDescription.length == 4);

    assert(link.rawUrl.sourceOffset == 116);
    assert(link.rawUrl.length == 11);

    assert(link.ignoredTrailingData.length == 0);
}


/// A UTF-16 description does not change the URL encoding.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00,

            0x01,

            // Description "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // URL remains ISO-8859-1.
            'u', 'r', 'l'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.link.description == "A");
    assert(result.value.link.url == "url");

    assert(result.value.link.rawUrl.sourceOffset == 217);
}


/// A URL terminator causes following bytes to be ignored.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x09,
            0x00, 0x00,

            0x03,
            'x',
            0x00,

            'u', 'r', 'l',
            0x00,

            'A', 'B'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.link.description == "x");
    assert(result.value.link.url == "url");

    assert(
        result.value.link.ignoredTrailingData.data ==
        ['A', 'B']
    );

    assert(
        result.value.link.ignoredTrailingData.sourceOffset ==
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

            0x03,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.link.description.length == 0);
    assert(result.value.link.url.length == 0);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x03,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
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
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 600);
}


/// Compressed WXXX data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            // Required DLI.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 700));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24UserUrlAvailability.requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Frame-level unsynchronisation applies to both semantic fields.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x02,

            0x00,
            'x',
            0x00,

            'u',
            0xFF, 0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.link.description == "x");
    assert(result.value.link.url == "u\u00FF");

    assert(
        result.value.link.effectiveUnsynchronisation
    );

    // Physical provenance retains the stuffing byte.
    assert(
        result.value.link.rawUrl.data ==
        ['u', 0xFF, 0x00]
    );
}
