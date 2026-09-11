/++
ID3v2.2 popularity-meter (`POP`) frame decoding.

A `POP` frame contains:

- one null-terminated ISO-8859-1 email/user identity string;
- one rating byte;
- an optional play counter.

The counter, when present, is unsigned, big-endian, at least four logical bytes
wide and may grow beyond machine-integer widths. The common `Id3v2Counter`
representation therefore preserves its exact logical bytes.

Whole-tag unsynchronisation is reversed only during logical traversal and text
decoding. Returned raw spans retain the exact stored physical bytes.

This module preserves native v2.2 semantics and performs no canonical mapping.
+/
module audiotag.id3v2.v22.popularity_meter;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.counter :
    Id3v2Counter;

import audiotag.id3v2.common.popularity :
    Id3v2Popularity;

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
Decoded native ID3v2.2 `POP` frame.

`rawEmail` excludes the mandatory null terminator while retaining physical
whole-tag-unsynchronisation stuffing.

`rawCounter` contains the exact physical bytes belonging to the optional
counter after the rating byte has been consumed. It is empty when the counter
is omitted.

The complete frame envelope remains available in `Id3v22NativeFrame`.
+/
struct Id3v22PopularityMeterFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Shared semantic popularity-meter value.
    Id3v2Popularity popularity;

    /// Physical email bytes excluding the mandatory terminator.
    ByteSpan rawEmail;

    /// Physical optional-counter bytes.
    ByteSpan rawCounter;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 popularity-meter (`POP`) frame.

The logical payload is:

    Email to user    <ISO-8859-1 text> $00
    Rating           $xx
    Counter          $xx xx xx xx (xx ...)   [optional]

The email terminator and rating byte are mandatory. The email itself may be
empty because the specification does not impose a non-empty constraint.

If a counter is present, it must contain at least four logical bytes. No upper
width is imposed.

Params:
    frame = Previously validated and bounded ID3v2.2 frame.
    tagUnsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    The decoded native `POP` frame or a structured parse/text error.
+/
ParseResult!Id3v22PopularityMeterFrame
decodeId3v22PopularityMeterFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "POP"
    )
    {
        return
            ParseResult!Id3v22PopularityMeterFrame
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


    auto emailResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (
        emailResult.hasError
    )
    {
        return
            ParseResult!Id3v22PopularityMeterFrame
                .failure(
                    emailResult.error
                );
    }

    const emailSegment =
        emailResult.value;


    auto email =
        decodeId3v22TextSpan(
            emailSegment.raw,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (
        email.hasError
    )
    {
        return
            ParseResult!Id3v22PopularityMeterFrame
                .failure(
                    email.error
                );
    }


    auto ratingResult =
        payload.takeByte();

    if (
        ratingResult.hasError
    )
    {
        return
            ParseResult!Id3v22PopularityMeterFrame
                .failure(
                    ratingResult.error
                );
    }

    const rating =
        ratingResult.value.value;


    const rawCounter =
        payload.remainingRaw;

    ubyte[] logicalCounter;

    logicalCounter.reserve(
        payload.remainingPhysical
    );

    while (
        !payload.empty
    )
    {
        auto byteResult =
            payload.takeByte();

        if (
            byteResult.hasError
        )
        {
            return
                ParseResult!Id3v22PopularityMeterFrame
                    .failure(
                        byteResult.error
                    );
        }

        logicalCounter ~=
            byteResult.value.value;
    }


    const hasCounter =
        logicalCounter.length !=
        0;

    if (
        hasCounter &&
        logicalCounter.length < 4
    )
    {
        return
            ParseResult!Id3v22PopularityMeterFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        rawCounter.sourceOffset,
                        4,
                        logicalCounter.length
                    )
                );
    }


    return
        ParseResult!Id3v22PopularityMeterFrame
            .success(
                Id3v22PopularityMeterFrame(
                    frame.header.sourceOffset,
                    Id3v2Popularity(
                        email.value,
                        rating,
                        hasCounter,
                        Id3v2Counter(
                            logicalCounter
                        )
                    ),
                    emailSegment.raw,
                    rawCounter,
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


/// A normal POP frame decodes email, rating and four-byte counter.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x09,

            'a', '@', 'b',
            0x00,
            0xC8,
            0x00, 0x00, 0x00, 0x2A
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasValue);

    const meter =
        result.value;

    assert(meter.sourceOffset == 100);
    assert(meter.popularity.email == "a@b");
    assert(meter.popularity.rating == 0xC8);
    assert(meter.popularity.hasCounter);

    assert(
        meter.popularity.counter.bigEndianBytes ==
        [
            0x00, 0x00, 0x00, 0x2A
        ]
    );

    assert(meter.rawEmail.sourceOffset == 106);
    assert(meter.rawEmail.data == ['a', '@', 'b']);

    assert(meter.rawCounter.sourceOffset == 111);

    assert(
        meter.rawCounter.data ==
        [
            0x00, 0x00, 0x00, 0x2A
        ]
    );

    assert(!meter.effectiveUnsynchronisation);
}


/// The personal counter may be omitted completely.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x03,

            'x',
            0x00,
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasValue);

    const meter =
        result.value;

    assert(meter.popularity.email == "x");
    assert(meter.popularity.rating == 0x00);
    assert(!meter.popularity.hasCounter);
    assert(meter.popularity.counter.byteLength == 0);
    assert(meter.rawCounter.empty);
    assert(meter.rawCounter.sourceOffset == 209);
}


/// An empty but terminated user identity remains structurally valid.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x02,

            0x00,
            0xFF
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasValue);
    assert(result.value.popularity.email.length == 0);
    assert(result.value.popularity.rating == 0xFF);
    assert(!result.value.popularity.hasCounter);
}


/// A present counter shorter than four logical bytes is invalid.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x06,

            'x',
            0x00,
            0x7F,
            0x00, 0x00, 0x01
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 409);
    assert(result.error.requested == 4);
    assert(result.error.available == 3);
}


/// Counter widths greater than 64 bits remain valid.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x0F,

            'x',
            0x00,
            0x80,

            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasValue);
    assert(result.value.popularity.hasCounter);
    assert(result.value.popularity.counter.byteLength == 12);

    assert(
        result.value.popularity.counter.bigEndianBytes ==
        [
            0x01, 0x02, 0x03, 0x04,
            0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C
        ]
    );
}


/// ISO-8859-1 user bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x06,

            'c', 'a', 'f', 0xE9,
            0x00,
            0x01
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasValue);
    assert(result.value.popularity.email == "caf\u00E9");
}


/// The user identity must terminate inside the frame.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
    assert(result.error.offset == 706);
}


/// The mandatory rating byte must follow the terminated user identity.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x02,

            'x',
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
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 808);
}


/// The POP codec rejects a different native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'N', 'T',
            0x00, 0x00, 0x04,

            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22PopularityMeterFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 900);
}


/// Whole-tag unsynchronisation preserves raw and logical counter forms.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'O', 'P',
            0x00, 0x00, 0x07,

            'x',
            0x00,
            0x80,

            0x00,
            0xFF, 0x00,
            0xE1,
            0x01
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
    assert(frame.value.header.size == 7);
    assert(frame.value.data.length == 8);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22PopularityMeterFrame(
                true
            );

    assert(result.hasValue);

    const meter =
        result.value;

    assert(meter.effectiveUnsynchronisation);
    assert(meter.popularity.email == "x");
    assert(meter.popularity.rating == 0x80);
    assert(meter.popularity.hasCounter);

    assert(
        meter.popularity.counter.bigEndianBytes ==
        [
            0x00,
            0xFF,
            0xE1,
            0x01
        ]
    );

    assert(
        meter.rawCounter.data ==
        [
            0x00,
            0xFF, 0x00,
            0xE1,
            0x01
        ]
    );

    assert(meter.rawCounter.sourceOffset == 1009);
}
