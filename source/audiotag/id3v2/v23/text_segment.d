/++
Terminated ID3v2.3 text-segment parsing.

This module locates encoding-dependent string terminators in the
logical ID3v2.3 frame-data byte stream.

Tag-level unsynchronisation is reversed while searching, but the
returned text segment preserves its original physical source bytes.

No character decoding or UTF-16 BOM validation is performed here.
+/
module audiotag.id3v2.v23.text_segment;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding,
    usesUtf16,
    terminatorWidth;


/++
One terminated ID3v2.3 encoded text segment.

`raw` contains the physical source representation of the encoded text
only. It excludes the terminator but retains any physical
unsynchronisation stuffing bytes.

`logicalLength` is the number of logical text bytes after
unsynchronisation reversal and before the terminator.
+/
struct Id3v23TextSegment
{
    /// Encoding used by this text segment.
    Id3v23TextEncoding encoding;

    /// Physical encoded text bytes, excluding the terminator.
    ByteSpan raw;

    /// Number of logical text bytes, excluding the terminator.
    size_t logicalLength;

    /// Physical source offset of the first terminator byte.
    size_t terminatorSourceOffset;


    /// Logical terminator width: one or two zero bytes.
    @property
    ubyte terminatorLength() const
        @safe pure nothrow @nogc
    {
        return
            encoding.terminatorWidth;
    }


    /++
    Constructs a logical cursor over the encoded text bytes.

    Params:
        unsynchronised = Whether ID3v2.3 tag-level unsynchronisation
            applies to `raw`.
    +/
    Id3v23DataCursor
    textCursor(
        bool unsynchronised
    ) const
        @safe pure nothrow @nogc
    {
        return
            Id3v23DataCursor(
                raw,
                unsynchronised
            );
    }
}


/++
Consumes one terminated text segment according to `encoding`.

For ISO-8859-1, the first logical `$00` terminates the string.

For UTF-16, logical bytes are examined in two-byte code-unit pairs
starting at the beginning of this string. Only a complete logical
`$00 $00` pair on that alignment is accepted as the terminator.

This function does not inspect or validate a UTF-16 BOM.

Params:
    cursor = Logical cursor positioned at the first encoded text byte.
    encoding = ID3v2.3 text encoding controlling terminator semantics.

Returns:
    The text segment without its terminator.

Error semantics:
    Any failure leaves `cursor` unchanged.

    `patternNotFound` means no complete terminator was present.

    `invalidLength` means a UTF-16 segment ended with an incomplete
    logical code unit.
+/
ParseResult!Id3v23TextSegment
takeId3v23TerminatedTextSegment(
    ref Id3v23DataCursor cursor,
    Id3v23TextEncoding encoding
)
    @safe pure nothrow @nogc
{
    auto probe =
        cursor;

    const startRaw =
        probe.remainingRaw;

    const startLogicalPosition =
        probe.logicalPosition;


    if (
        !encoding.usesUtf16
    )
    {
        while (
            !probe.empty
        )
        {
            auto byteResult =
                probe.takeByte();

            /*
             * The loop established that physical input remains.
             * A failure here would therefore violate DataCursor's
             * internal traversal invariant.
             */
            assert(byteResult.hasValue);

            const decoded =
                byteResult.value;

            if (
                decoded.value ==
                0x00
            )
            {
                const rawLength =
                    decoded.sourceOffset -
                    startRaw.sourceOffset;

                const raw =
                    startRaw.subspan(
                        0,
                        rawLength
                    );

                const logicalLength =
                    probe.logicalPosition -
                    startLogicalPosition -
                    1;

                const segment =
                    Id3v23TextSegment(
                        encoding,
                        raw,
                        logicalLength,
                        decoded.sourceOffset
                    );

                cursor =
                    probe;

                return
                    ParseResult!Id3v23TextSegment
                        .success(
                            segment
                        );
            }
        }

        return
            ParseResult!Id3v23TextSegment
                .failure(
                    ParseError(
                        ParseErrorCode.patternNotFound,
                        startRaw.sourceOffset,
                        1,
                        probe.logicalPosition -
                            startLogicalPosition
                    )
                );
    }


    /*
     * UTF-16 termination is aligned to logical two-byte code units.
     *
     * This alignment must be based on logical bytes because physical
     * ID3v2.3 unsynchronisation stuffing may increase the number of
     * stored bytes inside a code unit.
     */
    while (
        !probe.empty
    )
    {
        auto firstResult =
            probe.takeByte();

        assert(firstResult.hasValue);

        const first =
            firstResult.value;

        if (
            probe.empty
        )
        {
            return
                ParseResult!Id3v23TextSegment
                    .failure(
                        ParseError(
                            ParseErrorCode.invalidLength,
                            first.sourceOffset,
                            2,
                            1
                        )
                    );
        }

        auto secondResult =
            probe.takeByte();

        assert(secondResult.hasValue);

        const second =
            secondResult.value;

        if (
            first.value == 0x00 &&
            second.value == 0x00
        )
        {
            const rawLength =
                first.sourceOffset -
                startRaw.sourceOffset;

            const raw =
                startRaw.subspan(
                    0,
                    rawLength
                );

            const logicalLength =
                probe.logicalPosition -
                startLogicalPosition -
                2;

            assert(
                (logicalLength % 2) ==
                0
            );

            const segment =
                Id3v23TextSegment(
                    encoding,
                    raw,
                    logicalLength,
                    first.sourceOffset
                );

            cursor =
                probe;

            return
                ParseResult!Id3v23TextSegment
                    .success(
                        segment
                    );
        }
    }

    return
        ParseResult!Id3v23TextSegment
            .failure(
                ParseError(
                    ParseErrorCode.patternNotFound,
                    startRaw.sourceOffset,
                    2,
                    probe.logicalPosition -
                        startLogicalPosition
                )
            );
}


/// Latin-1 terminates at the first logical zero byte.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C',
            0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                100
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(result.hasValue);

    const segment =
        result.value;

    assert(
        segment.encoding ==
        Id3v23TextEncoding.latin1
    );

    assert(segment.raw.sourceOffset == 100);

    assert(
        segment.raw.data ==
        ['A', 'B', 'C']
    );

    assert(segment.logicalLength == 3);
    assert(segment.terminatorSourceOffset == 103);
    assert(segment.terminatorLength == 1);

    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 104);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// An empty Latin-1 string consists only of its terminator.
unittest
{
    const ubyte[] bytes =
        [
            0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                200
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(result.hasValue);

    assert(result.value.raw.empty);
    assert(result.value.raw.sourceOffset == 200);

    assert(result.value.logicalLength == 0);

    assert(
        result.value.terminatorSourceOffset ==
        200
    );

    assert(cursor.absoluteOffset == 201);
}


/// UTF-16 terminators are recognised only on code-unit alignment.
unittest
{
    /*
     * Logical two-byte units:
     *
     *   41 00
     *   00 42
     *   00 00
     *
     * The adjacent zero bytes at logical offsets 1 and 2 cross a
     * code-unit boundary and must not terminate the segment.
     */
    const ubyte[] bytes =
        [
            0x41, 0x00,
            0x00, 0x42,
            0x00, 0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(result.hasValue);

    const segment =
        result.value;

    assert(
        segment.raw.data ==
        [
            0x41, 0x00,
            0x00, 0x42
        ]
    );

    assert(segment.logicalLength == 4);

    assert(
        segment.terminatorSourceOffset ==
        304
    );

    assert(segment.terminatorLength == 2);

    assert(cursor.logicalPosition == 6);
    assert(cursor.physicalPosition == 6);
    assert(cursor.absoluteOffset == 306);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// An empty UTF-16 string consists of one aligned zero code unit.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                400
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(result.hasValue);

    assert(result.value.raw.empty);
    assert(result.value.raw.sourceOffset == 400);
    assert(result.value.logicalLength == 0);

    assert(
        result.value.terminatorSourceOffset ==
        400
    );

    assert(cursor.absoluteOffset == 402);
}


/// Latin-1 segmentation preserves physical unsynchronisation stuffing.
unittest
{
    /*
     * Logical bytes:
     *
     *   FF 00
     *
     * Physical representation:
     *
     *   FF 00 00
     *
     * The first zero is stuffing; the second is the string terminator.
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(result.hasValue);

    const segment =
        result.value;

    assert(segment.logicalLength == 1);

    /*
     * Stuffing remains part of the physical raw text region.
     */
    assert(
        segment.raw.data ==
        [0xFF, 0x00]
    );

    assert(segment.raw.length == 2);

    assert(
        segment.terminatorSourceOffset ==
        502
    );

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 503);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// UTF-16 alignment is based on logical, not physical, bytes.
unittest
{
    /*
     * Logical stream:
     *
     *   00 FF | 00 00
     *
     * First pair is text; second pair is the terminator.
     *
     * Whole-tag unsynchronisation expands the FF:
     *
     *   00 FF 00 | 00 00
     */
    const ubyte[] bytes =
        [
            0x00,
            0xFF, 0x00,

            0x00, 0x00,

            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            true
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(result.hasValue);

    const segment =
        result.value;

    assert(segment.logicalLength == 2);

    assert(
        segment.raw.data ==
        [
            0x00,
            0xFF, 0x00
        ]
    );

    assert(segment.raw.length == 3);

    assert(
        segment.terminatorSourceOffset ==
        603
    );

    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 5);
    assert(cursor.absoluteOffset == 605);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Missing Latin-1 terminators fail atomically.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C'
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                700
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 700);
    assert(result.error.requested == 1);
    assert(result.error.available == 3);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 700);

    assert(
        cursor.remainingRaw.data ==
        bytes
    );
}


/// Missing aligned UTF-16 terminators fail atomically.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x00, 0x42
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 800);
    assert(result.error.requested == 2);
    assert(result.error.available == 4);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
}


/// An incomplete UTF-16 code unit is reported separately.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                900
            ),
            false
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 902);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 900);
}


/// Missing UTF-16 terminators remain atomic after unsynchronisation.
unittest
{
    /*
     * Logical text:
     *
     *   00 FF
     *
     * but no terminating zero code unit.
     */
    const ubyte[] bytes =
        [
            0x00,
            0xFF, 0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 1000);
    assert(result.error.requested == 2);
    assert(result.error.available == 2);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 1000);
}


/// Consecutive terminated Latin-1 strings can share one cursor.
unittest
{
    const ubyte[] bytes =
        [
            'A', 0x00,
            'B', 0x00,
            0x55
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1100
            ),
            false
        );

    auto first =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    auto second =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(first.hasValue);
    assert(first.value.raw.data == ['A']);

    assert(second.hasValue);
    assert(second.value.raw.data == ['B']);

    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 4);
    assert(cursor.absoluteOffset == 1104);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// textCursor reconstructs the same logical bytes from raw provenance.
unittest
{
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x42,
            0x00
        ];

    auto cursor =
        Id3v23DataCursor(
            ByteSpan(
                bytes,
                1200
            ),
            true
        );

    auto result =
        cursor.takeId3v23TerminatedTextSegment(
            Id3v23TextEncoding.latin1
        );

    assert(result.hasValue);

    auto text =
        result.value
            .textCursor(true);

    auto first =
        text.takeByte();

    auto second =
        text.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 1200);

    assert(second.hasValue);
    assert(second.value.value == 0x42);
    assert(second.value.sourceOffset == 1202);

    assert(text.empty);
}
