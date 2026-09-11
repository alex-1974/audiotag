/++
ID3v2.2 ordinary URL-link frame decoding.

This module decodes ordinary `W**` URL-link frames, excluding the structurally
different `WXX` frame.

Ordinary URL-link frames contain no encoding marker. Their URL is an
ISO-8859-1 text string extending to the frame boundary.

If a string terminator occurs, following bytes are ignored semantically but
preserved as physical source provenance.

The decoder intentionally accepts every structurally valid `W**` identifier
except `WXX`, not only the predefined v2.2 URL frame IDs. This preserves broad
support for experimental/vendor URL-link frames while keeping their native
identifier intact.

ID3v2.2 whole-tag unsynchronisation is reversed while traversing the bounded
physical frame-data representation.
+/
module audiotag.id3v2.v22.url_link;

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
Decoded ordinary ID3v2.2 URL-link frame.

This represents `W**` frames except `WXX`.

`rawUrl` contains the physical URL bytes excluding an optional terminator
while retaining whole-tag unsynchronisation stuffing.

`ignoredTrailingData` contains physical bytes after an encountered URL
terminator.
+/
struct Id3v22UrlLinkFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Native three-character ID3v2.2 frame identifier.
    char[3] id;

    /// Decoded ISO-8859-1 URL.
    string url;

    /// Physical bytes belonging to the URL, excluding a terminator.
    ByteSpan rawUrl;

    /// Physical bytes following a URL terminator, if present.
    ByteSpan ignoredTrailingData;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ordinary ID3v2.2 URL-link frame.

The frame identifier must begin with `W` and must not be `WXX`.

Ordinary URL-link frames contain exactly one ISO-8859-1 URL and no text
encoding marker.

A URL terminator is optional. If present, bytes following it are ignored
semantically but remain preserved in `ignoredTrailingData`.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native URL-link frame or a structured error for an
    incompatible frame.
+/
ParseResult!Id3v22UrlLinkFrame
decodeId3v22UrlLinkFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[0] != 'W' ||
        frame.header.id[] == "WXX"
    )
    {
        return
            ParseResult!Id3v22UrlLinkFrame
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

    ByteSpan rawUrl;
    ByteSpan ignoredTrailingData;


    /*
     * Search transactionally for the optional ISO-8859-1 terminator.
     */
    auto segmentResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (
        segmentResult.hasValue
    )
    {
        rawUrl =
            segmentResult.value.raw;

        /*
         * The segment parser consumed the terminator. Everything physically
         * remaining is ignored extension data.
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
                ParseResult!Id3v22UrlLinkFrame
                    .failure(
                        segmentResult.error
                    );
        }

        /*
         * A URL terminator is optional. The enclosing frame boundary defines
         * the URL extent.
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


    auto decoded =
        decodeId3v22TextSpan(
            rawUrl,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (
        decoded.hasError
    )
    {
        return
            ParseResult!Id3v22UrlLinkFrame
                .failure(
                    decoded.error
                );
    }


    return
        ParseResult!Id3v22UrlLinkFrame
            .success(
                Id3v22UrlLinkFrame(
                    frame.header.sourceOffset,
                    frame.header.id,
                    decoded.value,
                    rawUrl,
                    ignoredTrailingData,
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


/// A normal predefined URL-link frame extends to the frame boundary.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'A', 'R',
            0x00, 0x00, 0x0B,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame();

    assert(result.hasValue);

    const link =
        result.value;

    assert(link.sourceOffset == 100);
    assert(link.id[] == "WAR");
    assert(link.url == "example.com");

    assert(link.rawUrl.sourceOffset == 106);
    assert(link.rawUrl.length == 11);

    assert(
        link.rawUrl.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );

    assert(link.ignoredTrailingData.empty);
    assert(link.ignoredTrailingData.sourceOffset == 117);

    assert(!link.effectiveUnsynchronisation);
}


/// A URL terminator causes following bytes to be ignored.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'C', 'P',
            0x00, 0x00, 0x09,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame();

    assert(result.hasValue);

    const link =
        result.value;

    assert(link.url == "url");

    assert(
        link.rawUrl.data ==
        ['u', 'r', 'l']
    );

    assert(link.rawUrl.sourceOffset == 206);

    assert(
        link.ignoredTrailingData.data ==
        ['i', 'g', 'n', 'o', 'r']
    );

    assert(link.ignoredTrailingData.sourceOffset == 210);
}


/// Relative URLs are accepted without normalization.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'A', 'F',
            0x00, 0x00, 0x0A,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.url == "../audio.x");
}


/// ISO-8859-1 URL bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'A', 'R',
            0x00, 0x00, 0x02,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.url == "x\u00E9");
}


/// A terminator may represent an empty URL.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'P', 'B',
            0x00, 0x00, 0x01,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame();

    assert(result.hasValue);

    assert(result.value.url.length == 0);
    assert(result.value.rawUrl.empty);
    assert(result.value.rawUrl.sourceOffset == 506);

    assert(result.value.ignoredTrailingData.empty);
    assert(
        result.value.ignoredTrailingData.sourceOffset ==
        507
    );
}


/// WXX is deliberately excluded from the ordinary URL codec.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x01,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame();

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
            'T', 'T', '2',
            0x00, 0x00, 0x01,

            'x'
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
            .decodeId3v22UrlLinkFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 700);
}


/// Experimental/vendor URL identifiers remain decodable natively.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'Z', '9',
            0x00, 0x00, 0x03,

            'u', 'r', 'l'
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
            .decodeId3v22UrlLinkFrame();

    assert(result.hasValue);
    assert(result.value.id[] == "WZ9");
    assert(result.value.url == "url");
}


/// Whole-tag unsynchronisation preserves physical URL bytes.
unittest
{
    /*
     * Logical URL:
     *
     *   x FF y
     *
     * Physical representation:
     *
     *   x FF 00 y
     */
    const ubyte[] bytes =
        [
            'W', 'A', 'R',

            /*
             * Three logical frame-data bytes.
             */
            0x00, 0x00, 0x03,

            'x',
            0xFF, 0x00,
            'y'
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
    assert(frame.value.header.size == 3);
    assert(frame.value.data.length == 4);

    auto result =
        frame.value
            .decodeId3v22UrlLinkFrame(
                true
            );

    assert(result.hasValue);

    const link =
        result.value;

    assert(link.effectiveUnsynchronisation);
    assert(link.url == "x\u00FFy");

    assert(
        link.rawUrl.data ==
        [
            'x',
            0xFF, 0x00,
            'y'
        ]
    );
}


/// Unsynchronisation stuffing does not become an accidental terminator.
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
     * First zero is stuffing, second zero is the actual URL terminator.
     */
    const ubyte[] bytes =
        [
            'W', 'C', 'M',

            /*
             * Two logical frame-data bytes.
             */
            0x00, 0x00, 0x02,

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
            .decodeId3v22UrlLinkFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.url == "\u00FF");

    assert(
        result.value.rawUrl.data ==
        [0xFF, 0x00]
    );

    assert(result.value.ignoredTrailingData.empty);
}
