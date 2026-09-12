/++
Terminated ID3v2.2 text-segment parsing.

This module locates encoding-dependent string terminators in the logical
ID3v2.2 frame-data byte stream.

Tag-level unsynchronisation is reversed while searching, but the returned text
segment preserves its original physical source bytes.

No character decoding or UCS-2 byte-order handling is performed here. Those
semantics belong to `text_decode.d`.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.text_segment;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding,
    usesUtf16,
    terminatorWidth;


/++
One terminated ID3v2.2 encoded text segment.

`raw` contains the physical source representation of the encoded text only.
It excludes the terminator but retains any physical whole-tag
unsynchronisation stuffing bytes.

`logicalLength` is the number of logical text bytes after unsynchronisation
reversal and before the terminator.
+/
struct Id3v22TextSegment
{
    /// Encoding used by this text segment.
    Id3v22TextEncoding encoding;

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
        unsynchronised = Whether ID3v2.2 tag-level unsynchronisation applies
            to `raw`.
    +/
    Id3v22DataCursor
    textCursor(
        bool unsynchronised
    ) const
        @safe pure nothrow @nogc
    {
        return
            Id3v22DataCursor(
                raw,
                unsynchronised
            );
    }
}


/++
Consumes one terminated text segment according to `encoding`.

For ISO-8859-1, the first logical `$00` terminates the string.

For UCS-2, logical bytes are examined in two-byte code-unit pairs starting at
the beginning of this string. Only a complete logical `$00 $00` pair on that
alignment is accepted as the terminator.

This function does not inspect or validate a Unicode BOM. ID3v2.2 permits
BOM-less UCS-2, and byte-order interpretation belongs to semantic decoding.

Params:
    cursor = Logical cursor positioned at the first encoded text byte.
    encoding = ID3v2.2 text encoding controlling terminator semantics.

Returns:
    The text segment without its terminator.

Error semantics:
    Any failure leaves `cursor` unchanged.

    `patternNotFound` means no complete terminator was present.

    `invalidLength` means a UCS-2 segment ended with an incomplete logical
    code unit.
+/
ParseResult!Id3v22TextSegment
takeId3v22TerminatedTextSegment(
    ref Id3v22DataCursor cursor,
    Id3v22TextEncoding encoding
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
                    Id3v22TextSegment(
                        encoding,
                        raw,
                        logicalLength,
                        decoded.sourceOffset
                    );

                cursor =
                    probe;

                return
                    ParseResult!Id3v22TextSegment
                        .success(
                            segment
                        );
            }
        }

        return
            ParseResult!Id3v22TextSegment
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
     * UCS-2 termination is aligned to logical two-byte code units.
     *
     * The alignment must use logical bytes because physical v2.2
     * unsynchronisation stuffing may increase the stored byte count inside a
     * code unit.
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
                ParseResult!Id3v22TextSegment
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
                Id3v22TextSegment(
                    encoding,
                    raw,
                    logicalLength,
                    first.sourceOffset
                );

            cursor =
                probe;

            return
                ParseResult!Id3v22TextSegment
                    .success(
                        segment
                    );
        }
    }

    return
        ParseResult!Id3v22TextSegment
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
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                100
            ),
            false
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    assert(result.hasValue);

    const segment =
        result.value;

    assert(
        segment.encoding ==
        Id3v22TextEncoding.latin1
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
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                200
            ),
            false
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    assert(result.hasValue);
    assert(result.value.raw.empty);
    assert(result.value.raw.sourceOffset == 200);
    assert(result.value.logicalLength == 0);
    assert(result.value.terminatorSourceOffset == 200);
    assert(cursor.absoluteOffset == 201);
}


/// UCS-2 terminators are recognised only on code-unit alignment.
unittest
{
    /*
     * Logical two-byte units:
     *
     *   41 00
     *   00 42
     *   00 00
     *
     * The adjacent zero bytes at offsets 1 and 2 cross a code-unit boundary
     * and must not terminate the segment.
     */
    const ubyte[] bytes =
        [
            0x41, 0x00,
            0x00, 0x42,
            0x00, 0x00,
            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                300
            ),
            false
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.utf16
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
    assert(segment.terminatorSourceOffset == 304);
    assert(segment.terminatorLength == 2);

    assert(cursor.logicalPosition == 6);
    assert(cursor.physicalPosition == 6);
    assert(cursor.absoluteOffset == 306);

    assert(
        cursor.remainingRaw.data ==
        [0x55]
    );
}


/// Unsynchronisation stuffing remains part of the physical Latin-1 segment.
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
     * The first zero is stuffing; the second is the terminator.
     */
    const ubyte[] bytes =
        [
            0xFF, 0x00,
            0x00,
            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                400
            ),
            true
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    assert(result.hasValue);

    const segment =
        result.value;

    assert(segment.logicalLength == 1);

    assert(
        segment.raw.data ==
        [0xFF, 0x00]
    );

    assert(segment.raw.length == 2);
    assert(segment.terminatorSourceOffset == 402);

    assert(cursor.logicalPosition == 2);
    assert(cursor.physicalPosition == 3);
    assert(cursor.absoluteOffset == 403);
}


/// UCS-2 alignment is logical even when one code-unit byte is stuffed.
unittest
{
    /*
     * Logical stream:
     *
     *   00 FF | 00 00
     *
     * Physical representation:
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
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.utf16
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
    assert(segment.terminatorSourceOffset == 503);

    assert(cursor.logicalPosition == 4);
    assert(cursor.physicalPosition == 5);
    assert(cursor.absoluteOffset == 505);
}


/// Missing Latin-1 terminators fail atomically.
unittest
{
    const ubyte[] bytes =
        [
            'A', 'B', 'C'
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            false
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 600);
    assert(result.error.requested == 1);
    assert(result.error.available == 3);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 600);
}


/// Missing aligned UCS-2 terminators fail atomically.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x00, 0x42
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                700
            ),
            false
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 700);
    assert(result.error.requested == 2);
    assert(result.error.available == 4);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 700);
}


/// An incomplete final UCS-2 code unit is rejected atomically.
unittest
{
    const ubyte[] bytes =
        [
            0x00, 0x41,
            0x00
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                800
            ),
            false
        );

    auto result =
        cursor.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.utf16
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 802);
    assert(result.error.requested == 2);
    assert(result.error.available == 1);

    assert(cursor.logicalPosition == 0);
    assert(cursor.physicalPosition == 0);
    assert(cursor.absoluteOffset == 800);
}
