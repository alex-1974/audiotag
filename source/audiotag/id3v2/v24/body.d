/++
ID3v2.4 tag-body structural partitioning.

The outer tag parser provides one bounded body span. This module
partitions that body into:

- an optional ID3v2.4 extended header;
- the remaining region containing frames and padding.

Frame parsing is deliberately not performed here.
+/
module audiotag.id3v2.v24.body;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;
import audiotag.id3v2.v24.extended_header :
    Id3v24ExtendedHeader,
    parseId3v24ExtendedHeader;
import audiotag.id3v2.v24.tag :
    Id3v24TagEnvelope,
    parseId3v24TagEnvelope;


/++
Structural partition of an ID3v2.4 tag body.

When `hasExtendedHeader` is false, `extendedHeader` contains its
default value and must not be interpreted.

`framesAndPadding` always covers exactly the portion of the tag body
remaining after the optional extended header.
+/
struct Id3v24BodyLayout
{
    /// Whether an extended header was declared and parsed.
    bool hasExtendedHeader;

    /// Parsed extended header when `hasExtendedHeader` is true.
    Id3v24ExtendedHeader extendedHeader;

    /// Remaining bounded region containing frames and padding.
    ByteSpan framesAndPadding;
}


/++
Partitions the bounded body of an ID3v2.4 tag.

If the tag header declares an extended header, it is parsed from the
beginning of the already bounded body span. Any remaining bytes form
the frames-and-padding region.

If no extended header is declared, the complete body becomes the
frames-and-padding region.

Params:
    tag = Previously validated ID3v2.4 tag envelope.

Returns:
    The structural body layout or the parse error produced by an
    invalid declared extended header.

Safety:
    Parsing cannot read beyond `tag.body`.
+/
ParseResult!Id3v24BodyLayout parseId3v24BodyLayout(
    Id3v24TagEnvelope tag
)
    @safe pure nothrow @nogc
{
    if (!tag.header.hasExtendedHeader)
    {
        return ParseResult!Id3v24BodyLayout.success(
            Id3v24BodyLayout(
                false,
                Id3v24ExtendedHeader.init,
                tag.body
            )
        );
    }

    auto cursor = ByteCursor(tag.body);

    auto extendedResult =
        cursor.parseId3v24ExtendedHeader();

    if (extendedResult.hasError)
    {
        return ParseResult!Id3v24BodyLayout.failure(
            extendedResult.error
        );
    }

    const framesAndPadding =
        tag.body.subspan(
            cursor.position,
            cursor.remaining
        );

    return ParseResult!Id3v24BodyLayout.success(
        Id3v24BodyLayout(
            true,
            extendedResult.value,
            framesAndPadding
        )
    );
}


/// Without the flag, the complete body remains available for frames.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x03,
         0x11, 0x22, 0x33];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));

    auto tagResult =
        cursor.parseId3v24TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value.parseId3v24BodyLayout();

    assert(bodyResult.hasValue);

    const body = bodyResult.value;

    assert(!body.hasExtendedHeader);
    assert(body.framesAndPadding.sourceOffset == 110);
    assert(body.framesAndPadding.length == 3);
    assert(
        body.framesAndPadding.data ==
        [0x11, 0x22, 0x33]
    );
}


/// A declared extended header is removed from the frame region.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x40,
         0x00, 0x00, 0x00, 0x09,

         // Minimal six-byte extended header.
         0x00, 0x00, 0x00, 0x06,
         0x01,
         0x00,

         // Remaining frame/padding bytes.
         0x11, 0x22, 0x33];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));

    auto tagResult =
        cursor.parseId3v24TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value.parseId3v24BodyLayout();

    assert(bodyResult.hasValue);

    const body = bodyResult.value;

    assert(body.hasExtendedHeader);

    assert(body.extendedHeader.sourceOffset == 210);
    assert(body.extendedHeader.size == 6);
    assert(body.extendedHeader.raw.length == 6);

    assert(body.framesAndPadding.sourceOffset == 216);
    assert(body.framesAndPadding.length == 3);
    assert(
        body.framesAndPadding.data ==
        [0x11, 0x22, 0x33]
    );
}


/// The extended header may consume the entire tag body.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x40,
         0x00, 0x00, 0x00, 0x06,

         0x00, 0x00, 0x00, 0x06,
         0x01,
         0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 300));

    auto tagResult =
        cursor.parseId3v24TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value.parseId3v24BodyLayout();

    assert(bodyResult.hasValue);

    const body = bodyResult.value;

    assert(body.hasExtendedHeader);
    assert(body.extendedHeader.sourceOffset == 310);

    assert(body.framesAndPadding.empty);
    assert(body.framesAndPadding.sourceOffset == 316);
}


/// A declared but missing extended header fails inside the body bound.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x40,
         0x00, 0x00, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));

    auto tagResult =
        cursor.parseId3v24TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value.parseId3v24BodyLayout();

    assert(bodyResult.hasError);
    assert(
        bodyResult.error.code ==
        ParseErrorCode.endOfSpan
    );
    assert(bodyResult.error.offset == 410);
    assert(bodyResult.error.requested == 4);
    assert(bodyResult.error.available == 0);
}


/// Malformed extended headers preserve their absolute source offsets.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x40,
         0x00, 0x00, 0x00, 0x06,

         0x00, 0x00, 0x00, 0x06,
         0x02,
         0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));

    auto tagResult =
        cursor.parseId3v24TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value.parseId3v24BodyLayout();

    assert(bodyResult.hasError);
    assert(
        bodyResult.error.code ==
        ParseErrorCode.invalidLength
    );
    assert(bodyResult.error.offset == 514);
}


/// Extended-header-looking bytes are ordinary body data without the flag.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x06,

         0x00, 0x00, 0x00, 0x06,
         0x01,
         0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 600));

    auto tagResult =
        cursor.parseId3v24TagEnvelope();

    assert(tagResult.hasValue);

    auto bodyResult =
        tagResult.value.parseId3v24BodyLayout();

    assert(bodyResult.hasValue);
    assert(!bodyResult.value.hasExtendedHeader);

    assert(
        bodyResult.value.framesAndPadding.data ==
        tagResult.value.body.data
    );
}
