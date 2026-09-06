/++
ID3v2.3 tag-body structural partitioning.

The outer tag parser provides one physically bounded tag-body span.
This module partitions that body into:

- an optional ID3v2.3 extended header;
- the remaining physical region containing frames and padding.

When tag-level unsynchronisation is active, the extended header is
consumed through one logical `Id3v23DataCursor`. The remaining
frame/padding region nevertheless stays represented by its original
physical `ByteSpan`.

Frame parsing and padding validation are deliberately not performed
here.
+/
module audiotag.id3v2.v23.body;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.extended_header :
    Id3v23ExtendedHeader,
    parseId3v23ExtendedHeader;

import audiotag.id3v2.v23.tag :
    Id3v23TagEnvelope;


/++
Structural partition of an ID3v2.3 tag body.

When `hasExtendedHeader` is false, `extendedHeader` contains its default
value and must not be interpreted.

`framesAndPadding` always preserves the complete physical source region
remaining after the optional extended header.

When tag-level unsynchronisation is active, the physical length of the
extended header may exceed its logical length because stuffing bytes
remain part of the source representation.
+/
struct Id3v23BodyLayout
{
    /// Whether an extended header was declared and parsed.
    bool hasExtendedHeader;

    /// Parsed extended header when `hasExtendedHeader` is true.
    Id3v23ExtendedHeader extendedHeader;

    /// Remaining physical region containing frames and padding.
    ByteSpan framesAndPadding;
}


/++
Partitions the bounded body of an ID3v2.3 tag.

If the tag header declares an extended header, one logical data cursor
is created over the already bounded physical body. The extended header
is consumed from that logical stream and the remaining physical bytes
become the frame/padding region.

If no extended header is declared, the complete physical body becomes
the frame/padding region without applying unsynchronisation at this
stage.

The extended header's declared padding size is retained but is not
validated against the remaining tag body here. That check belongs to
the later frame-sequence/padding parser.

Params:
    tag = Previously validated and bounded ID3v2.3 tag envelope.

Returns:
    The structural body layout or the parse error produced by an
    invalid declared extended header.

Safety:
    Parsing cannot read beyond `tag.body`.
+/
ParseResult!Id3v23BodyLayout
parseId3v23BodyLayout(
    Id3v23TagEnvelope tag
)
    @safe pure nothrow @nogc
{
    if (
        !tag.header.hasExtendedHeader
    )
    {
        return
            ParseResult!Id3v23BodyLayout
                .success(
                    Id3v23BodyLayout(
                        false,
                        Id3v23ExtendedHeader.init,
                        tag.body
                    )
                );
    }

    auto cursor =
        Id3v23DataCursor(
            tag.body,
            tag.header.unsynchronisation
        );

    auto extendedResult =
        cursor.parseId3v23ExtendedHeader();

    if (extendedResult.hasError)
    {
        return
            ParseResult!Id3v23BodyLayout
                .failure(
                    extendedResult.error
                );
    }

    const framesAndPadding =
        cursor.remainingRaw;

    return
        ParseResult!Id3v23BodyLayout
            .success(
                Id3v23BodyLayout(
                    true,
                    extendedResult.value,
                    framesAndPadding
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.id3v2.v23.tag :
        parseId3v23TagEnvelope;
}


/// Without the flag, the complete physical body remains available.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * Body size = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            0x11, 0x22, 0x33
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasValue);

    const body =
        bodyResult.value;

    assert(!body.hasExtendedHeader);

    assert(
        body.extendedHeader ==
        Id3v23ExtendedHeader.init
    );

    assert(
        body.framesAndPadding.sourceOffset ==
        110
    );

    assert(
        body.framesAndPadding.length ==
        3
    );

    assert(
        body.framesAndPadding.data ==
        [0x11, 0x22, 0x33]
    );
}


/// A declared extended header is removed from the frame region.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Extended-header flag.
             */
            0x40,

            /*
             * Physical body size:
             *
             *   10-byte minimal extended header
             *    3 remaining bytes
             */
            0x00, 0x00, 0x00, 0x0D,

            /*
             * Extended-header size = 6.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * Extended flags.
             */
            0x00, 0x00,

            /*
             * Padding size = 0.
             */
            0x00, 0x00, 0x00, 0x00,

            /*
             * Remaining frame/padding bytes.
             */
            0x11, 0x22, 0x33
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasValue);

    const body =
        bodyResult.value;

    assert(body.hasExtendedHeader);

    assert(
        body.extendedHeader.sourceOffset ==
        210
    );

    assert(
        body.extendedHeader.size ==
        6
    );

    assert(
        body.extendedHeader.logicalLength ==
        10
    );

    assert(
        body.extendedHeader.raw.length ==
        10
    );

    assert(
        body.framesAndPadding.sourceOffset ==
        220
    );

    assert(
        body.framesAndPadding.length ==
        3
    );

    assert(
        body.framesAndPadding.data ==
        [0x11, 0x22, 0x33]
    );
}


/// The extended header may consume the complete physical body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            /*
             * Body consists only of the ten physical extended-header
             * bytes.
             */
            0x00, 0x00, 0x00, 0x0A,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasValue);

    const body =
        bodyResult.value;

    assert(body.hasExtendedHeader);

    assert(
        body.extendedHeader.sourceOffset ==
        310
    );

    assert(body.framesAndPadding.empty);

    assert(
        body.framesAndPadding.sourceOffset ==
        320
    );
}


/// A declared but missing extended header fails inside the body bound.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            /*
             * Empty physical body despite the extended-header flag.
             */
            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasError);

    assert(
        bodyResult.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(bodyResult.error.offset == 410);
    assert(bodyResult.error.requested == 1);
    assert(bodyResult.error.available == 0);
}


/// Malformed extended headers retain absolute physical source offsets.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x0A,

            /*
             * Valid size.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * Undefined extended flag.
             */
            0x40, 0x00,

            0x00, 0x00, 0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasError);

    assert(
        bodyResult.error.code ==
        ParseErrorCode.invalidFlags
    );

    assert(bodyResult.error.offset == 514);
}


/// Unsynchronised extended headers consume their expanded physical form.
unittest
{
    /*
     * Logical padding-size field:
     *
     *   00 FF 00 02
     *
     * Physical field:
     *
     *   00 FF 00 00 02
     *
     * The minimal extended header therefore occupies eleven physical
     * bytes instead of ten.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Unsynchronisation + extended header.
             */
            0xC0,

            /*
             * Physical body:
             *
             *   11-byte physical extended header
             *    3 remaining physical bytes
             */
            0x00, 0x00, 0x00, 0x0E,

            /*
             * Logical extended-header size = 6.
             */
            0x00, 0x00, 0x00, 0x06,

            0x00, 0x00,

            /*
             * Physical unsynchronised padding-size representation.
             */
            0x00,
            0xFF, 0x00,
            0x00,
            0x02,

            /*
             * Remaining frame/padding source bytes.
             */
            0x11, 0x22, 0x33
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    const tag =
        tagResult.value;

    assert(tag.header.unsynchronisation);
    assert(tag.header.hasExtendedHeader);
    assert(tag.body.length == 14);

    auto bodyResult =
        tag.parseId3v23BodyLayout();

    assert(bodyResult.hasValue);

    const body =
        bodyResult.value;

    assert(body.hasExtendedHeader);

    assert(
        body.extendedHeader.paddingSize ==
        0x00FF_0002
    );

    assert(
        body.extendedHeader.logicalLength ==
        10
    );

    /*
     * Ten logical bytes consumed eleven physical bytes.
     */
    assert(
        body.extendedHeader.raw.length ==
        11
    );

    assert(
        body.framesAndPadding.sourceOffset ==
        621
    );

    assert(
        body.framesAndPadding.length ==
        3
    );

    assert(
        body.framesAndPadding.data ==
        [0x11, 0x22, 0x33]
    );
}


/// Without an extended header unsynchronisation is deliberately deferred.
unittest
{
    /*
     * The complete physical body must survive this stage unchanged.
     * Frame parsing will later traverse it logically.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x80,

            0x00, 0x00, 0x00, 0x03,

            0xFF, 0x00, 0xE1
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasValue);

    const body =
        bodyResult.value;

    assert(!body.hasExtendedHeader);

    assert(
        body.framesAndPadding.sourceOffset ==
        710
    );

    assert(
        body.framesAndPadding.length ==
        3
    );

    assert(
        body.framesAndPadding.data ==
        [0xFF, 0x00, 0xE1]
    );
}


/// Body partitioning preserves parent-relative absolute offsets.
unittest
{
    const ubyte[] bytes =
        [
            0x99,

            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x0B,

            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,

            0x55,

            0xAA
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1000
            )
        );

    cursor.popFront();

    auto tagResult =
        cursor.parseId3v23TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value
            .parseId3v23BodyLayout();

    assert(bodyResult.hasValue);

    const body =
        bodyResult.value;

    assert(
        body.extendedHeader.sourceOffset ==
        1011
    );

    assert(
        body.framesAndPadding.sourceOffset ==
        1021
    );

    assert(
        body.framesAndPadding.data ==
        [0x55]
    );

    /*
     * The outer tag parser ended before the unrelated following byte.
     */
    assert(cursor.absoluteOffset == 1022);
    assert(cursor.front == 0xAA);
}
