/++
ID3v2.2 user-defined URL-link frame decoding.

A `WXX` frame contains:

- one text-encoding marker;
- one terminated description using that encoding;
- one URL encoded as ISO-8859-1.

The encoding marker applies only to the description. The URL is always
ISO-8859-1 regardless of the selected description encoding.

A URL terminator is optional. If present, following bytes are ignored
semantically but preserved as physical source provenance.

For ID3v2.2 UCS-2 descriptions, explicit byte-order marks are honoured while a
BOM-less description uses the revision-specific deterministic big-endian
default implemented by `text_decode.d`.

Whole-tag unsynchronisation is reversed only during logical traversal and text
decoding. Returned raw spans retain the exact stored physical bytes.

This module preserves native v2.2 semantics and performs no canonical mapping.
+/
module audiotag.id3v2.v22.user_url;

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
    Id3v22TextEncoding,
    parseId3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;


/++
Decoded ID3v2.2 `WXX` frame.

`rawDescription` excludes the mandatory description terminator while retaining
physical whole-tag-unsynchronisation stuffing.

`rawUrl` excludes an optional URL terminator.

`ignoredTrailingData` preserves all physical bytes after an encountered URL
terminator.
+/
struct Id3v22UserUrlFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Encoding used by the user-defined description.
    Id3v22TextEncoding descriptionEncoding;

    /// Decoded user-defined description.
    string description;

    /// Decoded ISO-8859-1 URL.
    string url;

    /// Physical description bytes excluding its terminator.
    ByteSpan rawDescription;

    /// Physical URL bytes excluding an optional terminator.
    ByteSpan rawUrl;

    /// Physical bytes after an encountered URL terminator.
    ByteSpan ignoredTrailingData;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes an ID3v2.2 user-defined URL-link (`WXX`) frame.

The semantic payload consists of:

    Text encoding    $xx
    Description      <text according to encoding> $00 (00)
    URL              <ISO-8859-1 text>

The description terminator is mandatory.

The URL always uses ISO-8859-1 and is independent of the description encoding.

A URL terminator is optional. If present, following bytes are ignored
semantically but retained in `ignoredTrailingData`.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native `WXX` frame or a structured parse/text error.
+/
ParseResult!Id3v22UserUrlFrame
decodeId3v22UserUrlFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "WXX"
    )
    {
        return
            ParseResult!Id3v22UserUrlFrame
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
     * WXX begins with an encoding marker for the description only.
     */
    auto encodingResult =
        payload.parseId3v22TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v22UserUrlFrame
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * The user-defined description must be terminated according to the
     * selected encoding.
     */
    auto descriptionResult =
        payload.takeId3v22TerminatedTextSegment(
            encoding
        );

    if (
        descriptionResult.hasError
    )
    {
        return
            ParseResult!Id3v22UserUrlFrame
                .failure(
                    descriptionResult.error
                );
    }

    const descriptionSegment =
        descriptionResult.value;


    auto description =
        decodeId3v22TextSpan(
            descriptionSegment.raw,
            encoding,
            tagUnsynchronised
        );

    if (
        description.hasError
    )
    {
        return
            ParseResult!Id3v22UserUrlFrame
                .failure(
                    description.error
                );
    }


    /*
     * The URL is always ISO-8859-1. Search independently for its optional
     * one-byte terminator.
     */
    ByteSpan rawUrl;
    ByteSpan ignoredTrailingData;

    auto urlSegmentResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
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
                ParseResult!Id3v22UserUrlFrame
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
        decodeId3v22TextSpan(
            rawUrl,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (
        url.hasError
    )
    {
        return
            ParseResult!Id3v22UserUrlFrame
                .failure(
                    url.error
                );
    }


    return
        ParseResult!Id3v22UserUrlFrame
            .success(
                Id3v22UserUrlFrame(
                    frame.header.sourceOffset,
                    encoding,
                    description.value,
                    url.value,
                    descriptionSegment.raw,
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


/// A Latin-1 description precedes an ISO-8859-1 URL.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',

            /*
             * encoding 1
             * + description 4
             * + terminator 1
             * + URL 11
             * = 17.
             */
            0x00, 0x00, 0x11,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserUrlFrame();

    assert(result.hasValue);

    const link =
        result.value;

    assert(link.sourceOffset == 100);

    assert(
        link.descriptionEncoding ==
        Id3v22TextEncoding.latin1
    );

    assert(link.description == "home");
    assert(link.url == "example.com");

    assert(link.rawDescription.sourceOffset == 107);

    assert(
        link.rawDescription.data ==
        ['h', 'o', 'm', 'e']
    );

    assert(link.rawUrl.sourceOffset == 112);

    assert(
        link.rawUrl.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );

    assert(link.ignoredTrailingData.empty);
    assert(link.ignoredTrailingData.sourceOffset == 123);

    assert(!link.effectiveUnsynchronisation);
}


/// A UCS-2 description does not change the URL encoding.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',

            /*
             * encoding 1
             * + LE BOM/A description 4
             * + terminator 2
             * + URL 3
             * = 10.
             */
            0x00, 0x00, 0x0A,

            0x01,

            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserUrlFrame();

    assert(result.hasValue);

    const link =
        result.value;

    assert(
        link.descriptionEncoding ==
        Id3v22TextEncoding.utf16
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

    assert(link.rawUrl.sourceOffset == 213);

    assert(
        link.rawUrl.data ==
        ['u', 'r', 'l']
    );
}


/// BOM-less UCS-2 descriptions use the v2.2 deterministic big-endian default.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x08,

            0x01,

            0x00, 0x41,
            0x00, 0x00,

            'u', 'r', 'l'
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
            .decodeId3v22UserUrlFrame();

    assert(result.hasValue);
    assert(result.value.description == "A");
    assert(result.value.url == "url");
}


/// A URL terminator causes following bytes to be ignored.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x09,

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
                400
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserUrlFrame();

    assert(result.hasValue);

    const link =
        result.value;

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

    assert(link.ignoredTrailingData.sourceOffset == 413);
}


/// Description and URL may both be empty.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x02,

            0x00,
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
            .decodeId3v22UserUrlFrame();

    assert(result.hasValue);

    assert(result.value.description.length == 0);
    assert(result.value.url.length == 0);

    assert(result.value.rawDescription.empty);
    assert(result.value.rawUrl.empty);

    assert(result.value.rawDescription.sourceOffset == 507);
    assert(result.value.rawUrl.sourceOffset == 508);
}


/// Undefined text-encoding markers remain invalid.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x02,

            0x02,
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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 606);
}


/// The description terminator is mandatory.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'X', 'X',
            0x00, 0x00, 0x04,

            0x00,
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
            .decodeId3v22UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// Ordinary URL-link frames are rejected by the WXX codec.
unittest
{
    const ubyte[] bytes =
        [
            'W', 'A', 'R',
            0x00, 0x00, 0x01,

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
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22UserUrlFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 800);
}


/// Whole-tag unsynchronisation preserves physical bytes in both fields.
unittest
{
    /*
     * Logical payload:
     *
     *   00
     *   FF
     *   00
     *   FF
     *
     * Physical payload:
     *
     *   00
     *   FF 00
     *   00
     *   FF 00
     */
    const ubyte[] bytes =
        [
            'W', 'X', 'X',

            /*
             * Logical frame-data length = 4.
             */
            0x00, 0x00, 0x04,

            0x00,

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
    assert(frame.value.header.size == 4);
    assert(frame.value.data.length == 6);

    auto result =
        frame.value
            .decodeId3v22UserUrlFrame(
                true
            );

    assert(result.hasValue);

    const link =
        result.value;

    assert(link.effectiveUnsynchronisation);
    assert(link.description == "\u00FF");
    assert(link.url == "\u00FF");

    assert(
        link.rawDescription.data ==
        [0xFF, 0x00]
    );

    assert(
        link.rawUrl.data ==
        [0xFF, 0x00]
    );
}


/// Unsynchronisation stuffing does not terminate the ISO-8859-1 URL.
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
     * First zero is stuffing; second zero is the optional URL terminator.
     */
    const ubyte[] bytes =
        [
            'W', 'X', 'X',

            /*
             * Logical payload:
             * encoding 1
             * empty description terminator 1
             * URL FF 1
             * URL terminator 1
             * = 4.
             */
            0x00, 0x00, 0x04,

            0x00,
            0x00,

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
            .decodeId3v22UserUrlFrame(
                true
            );

    assert(result.hasValue);

    assert(result.value.description.length == 0);
    assert(result.value.url == "\u00FF");

    assert(
        result.value.rawUrl.data ==
        [0xFF, 0x00]
    );

    assert(result.value.ignoredTrailingData.empty);
}
