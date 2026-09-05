/++
ID3v2.4 URL-link frame decoding.

This module decodes ordinary `W***` URL-link frames, excluding the
structurally different `WXXX` frame.

Ordinary URL-link frames contain no encoding marker. Their URL is an
ISO-8859-1 text string extending to the frame boundary. If a string
terminator occurs, following bytes are ignored semantically but
preserved as provenance.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.url_link;

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
    Id3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/++
Semantic availability of an ordinary URL-link frame.
+/
enum Id3v24UrlLinkAvailability : ubyte
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
Decoded ordinary ID3v2.4 URL-link frame.

This represents `W***` frames except `WXXX`.
+/
struct Id3v24UrlLinkFrame
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

    /// Whether unsynchronisation was effective for this frame.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic URL-link decoding.
+/
struct Id3v24UrlLinkOutcome
{
    /// Semantic availability.
    Id3v24UrlLinkAvailability availability;

    /// Decoded URL frame when available.
    Id3v24UrlLinkFrame link;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;

    /// Whether the URL is semantically available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24UrlLinkAvailability.decoded;
    }
}


/++
Decodes an ordinary ID3v2.4 URL-link frame.

The frame identifier must begin with `W` and must not be `WXXX`.

A URL terminator is optional. If present, bytes following it are
ignored semantically as required by ID3v2.4, but remain preserved in
`ignoredTrailingData`.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level unsynchronisation applies.

Returns:
    Decoded or transformation-pending URL outcome, or a structured
    error for an incompatible frame.
+/
ParseResult!Id3v24UrlLinkOutcome
decodeId3v24UrlLinkFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[0] != 'W' ||
        frame.header.id[] == "WXXX"
    )
    {
        return ParseResult!Id3v24UrlLinkOutcome.failure(
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
        return ParseResult!Id3v24UrlLinkOutcome.failure(
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
        Id3v24UrlLinkAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24UrlLinkAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24UrlLinkAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24UrlLinkAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24UrlLinkOutcome.success(
            Id3v24UrlLinkOutcome(
                availability,
                Id3v24UrlLinkFrame.init,
                layout.rawPayload
            )
        );
    }

    auto payload =
        layout.payloadCursor();

    ByteSpan rawUrl;
    ByteSpan ignoredTrailingData;

    auto segmentResult =
        payload.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.latin1
        );

    if (segmentResult.hasValue)
    {
        rawUrl =
            segmentResult.value.raw;

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
            return ParseResult!Id3v24UrlLinkOutcome.failure(
                segmentResult.error
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

    auto decoded =
        decodeId3v24TextSpan(
            rawUrl,
            Id3v24TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (decoded.hasError)
    {
        return ParseResult!Id3v24UrlLinkOutcome.failure(
            decoded.error
        );
    }

    auto link =
        Id3v24UrlLinkFrame(
            frame.header.sourceOffset,
            frame.header.id,
            decoded.value,
            rawUrl,
            ignoredTrailingData,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24UrlLinkOutcome.success(
        Id3v24UrlLinkOutcome(
            Id3v24UrlLinkAvailability.decoded,
            link,
            layout.rawPayload
        )
    );
}


import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


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
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const link = result.value.link;

    assert(link.sourceOffset == 100);
    assert(link.id[] == "WOAR");
    assert(link.url == "example.com");

    assert(link.rawUrl.sourceOffset == 110);
    assert(link.rawUrl.length == 11);

    assert(link.ignoredTrailingData.length == 0);
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
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.link.url == "url");

    assert(
        result.value.link.ignoredTrailingData.data ==
        ['i', 'g', 'n', 'o', 'r']
    );

    assert(
        result.value.link.ignoredTrailingData.sourceOffset ==
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
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.link.url == "../audio.x");
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
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);
    assert(result.value.link.url.length == 0);
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
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
    assert(result.error.offset == 500);
}


/// A non-URL frame is rejected.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03,
            'A'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
}


/// Compressed URL data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',
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
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24UrlLinkAvailability.requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Frame-level unsynchronisation is reversed before URL decoding.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'O', 'A', 'R',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x02,

            'x',
            0xFF, 0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.link.url == "x\u00FF");
    assert(result.value.link.effectiveUnsynchronisation);

    // Raw physical bytes retain the stuffing byte.
    assert(
        result.value.link.rawUrl.data ==
        ['x', 0xFF, 0x00]
    );
}
