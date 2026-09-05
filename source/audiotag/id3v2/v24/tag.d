/++
Bounded ID3v2.4 tag-envelope parsing.

This module parses the complete outer structure of an ID3v2.4 tag:

- fixed 10-byte header;
- exactly the body length declared by the header;
- optional 10-byte footer.

The tag body remains an opaque bounded `ByteSpan`. Extended headers,
frames and padding are parsed by later structural stages.

Parsing is atomic: any malformed or truncated outer structure leaves
the caller's cursor unchanged.
+/
module audiotag.id3v2.v24.tag;

import audiotag.core.cursor : ByteCursor;
import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.numeric : readSynchsafe32;
import audiotag.core.result : ParseResult, ParseStatus;
import audiotag.core.span : ByteSpan;
import audiotag.id3v2.v24.header :
    Id3v24Header,
    parseId3v24Header;


/++
The bounded outer structure of one ID3v2.4 tag.

`body` contains exactly `header.tagSize` bytes.

When no footer is present, `footer` is an empty span positioned
immediately after the body. When a footer is present it contains the
complete 10-byte footer.
+/
struct Id3v24TagEnvelope
{
    /// Parsed ID3v2.4 header.
    Id3v24Header header;

    /// Bounded tag body containing extended header, frames and/or padding.
    ByteSpan body;

    /// Raw footer span, or an empty span when no footer is present.
    ByteSpan footer;

    /// Absolute offset immediately following the complete tag.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return footer.sourceOffset + footer.length;
    }
}


/++
Parses and bounds one complete ID3v2.4 tag envelope.

The footer, when indicated by the header, must be a copy of the header
except for its reversed identifier `"3DI"`.

Params:
    cursor = Cursor positioned at the beginning of an ID3v2.4 tag.

Returns:
    A bounded tag envelope or a structured parse error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24TagEnvelope parseId3v24TagEnvelope(
    ref ByteCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;

    auto headerResult = probe.parseId3v24Header();

    if (headerResult.hasError)
        return ParseResult!Id3v24TagEnvelope.failure(
            headerResult.error
        );

    const header = headerResult.value;

    auto bodyResult = probe.takeBytes(header.tagSize);

    if (bodyResult.hasError)
        return ParseResult!Id3v24TagEnvelope.failure(
            bodyResult.error
        );

    const body = bodyResult.value;

    ByteSpan footer =
        ByteSpan(
            body.data[body.length .. body.length],
            body.sourceOffset + body.length
        );

    if (header.hasFooter)
    {
        auto footerResult = probe.takeBytes(10);

        if (footerResult.hasError)
            return ParseResult!Id3v24TagEnvelope.failure(
                footerResult.error
            );

        footer = footerResult.value;

        auto validation =
            validateId3v24Footer(header, footer);

        if (validation.hasError)
            return ParseResult!Id3v24TagEnvelope.failure(
                validation.error
            );
    }

    const envelope = Id3v24TagEnvelope(
        header,
        body,
        footer
    );

    cursor = probe;

    return ParseResult!Id3v24TagEnvelope.success(envelope);
}


/++
Validates an ID3v2.4 footer against its header.

The footer must contain `"3DI"` and otherwise repeat version,
revision, flags and tag size exactly.
+/
private ParseStatus validateId3v24Footer(
    Id3v24Header header,
    ByteSpan footer
)
    @safe pure nothrow @nogc
{
    assert(footer.length == 10);

    const data = footer.data;

    immutable ubyte[3] identifier = ['3', 'D', 'I'];

    foreach (index; 0 .. identifier.length)
    {
        if (data[index] != identifier[index])
        {
            return ParseStatus.failure(
                ParseError(
                    ParseErrorCode.invalidSignature,
                    footer.sourceOffset + index
                )
            );
        }
    }

    if (data[3] != 0x04)
    {
        return ParseStatus.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                footer.sourceOffset + 3
            )
        );
    }

    if (data[4] != header.revision)
    {
        return ParseStatus.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                footer.sourceOffset + 4
            )
        );
    }

    if (data[5] != header.flags)
    {
        return ParseStatus.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                footer.sourceOffset + 5
            )
        );
    }

    auto sizeCursor =
        ByteCursor(footer.subspan(6, 4));

    auto sizeResult =
        sizeCursor.readSynchsafe32();

    if (sizeResult.hasError)
        return ParseStatus.failure(sizeResult.error);

    if (sizeResult.value != header.tagSize)
    {
        return ParseStatus.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                footer.sourceOffset + 6
            )
        );
    }

    return ParseStatus.success();
}


/// A tag without footer exposes exactly the declared bounded body.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x03,
         0x11, 0x22, 0x33,
         0x99];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24TagEnvelope();

    assert(result.hasValue);

    const tag = result.value;

    assert(tag.header.sourceOffset == 100);
    assert(tag.header.tagSize == 3);

    assert(tag.body.sourceOffset == 110);
    assert(tag.body.length == 3);
    assert(tag.body.data == [0x11, 0x22, 0x33]);

    assert(tag.footer.empty);
    assert(tag.footer.sourceOffset == 113);
    assert(tag.endOffset == 113);

    assert(cursor.absoluteOffset == 113);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x99);
}


/// A footer is outside tagSize and is consumed after the body.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x10,
         0x00, 0x00, 0x00, 0x02,

         0x11, 0x22,

         '3', 'D', 'I',
         0x04, 0x00,
         0x10,
         0x00, 0x00, 0x00, 0x02,

         0x99];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));
    auto result = cursor.parseId3v24TagEnvelope();

    assert(result.hasValue);

    const tag = result.value;

    assert(tag.body.sourceOffset == 510);
    assert(tag.body.length == 2);

    assert(tag.footer.sourceOffset == 512);
    assert(tag.footer.length == 10);
    assert(tag.endOffset == 522);

    assert(cursor.absoluteOffset == 522);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x99);
}


/// A truncated declared body leaves the original cursor unchanged.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x05,
         0x11, 0x22];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24TagEnvelope();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 110);
    assert(result.error.requested == 5);
    assert(result.error.available == 2);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 100);
}


/// A missing footer leaves the original cursor unchanged.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x10,
         0x00, 0x00, 0x00, 0x01,
         0x11];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));
    auto result = cursor.parseId3v24TagEnvelope();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 111);
    assert(result.error.requested == 10);
    assert(result.error.available == 0);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 100);
}


/// Invalid footer identifiers report their exact absolute offset.
unittest
{
    foreach (invalidIndex; 0 .. 3)
    {
        ubyte[] bytes =
            ['I', 'D', '3',
             0x04, 0x00,
             0x10,
             0x00, 0x00, 0x00, 0x00,

             '3', 'D', 'I',
             0x04, 0x00,
             0x10,
             0x00, 0x00, 0x00, 0x00];

        bytes[10 + invalidIndex] = 0x00;

        auto cursor = ByteCursor(ByteSpan(bytes, 1000));
        auto result = cursor.parseId3v24TagEnvelope();

        assert(result.hasError);
        assert(result.error.code == ParseErrorCode.invalidSignature);
        assert(result.error.offset == 1010 + invalidIndex);

        assert(cursor.position == 0);
    }
}


/// Footer revision, flags and size must match the header.
unittest
{
    foreach (field; 0 .. 3)
    {
        ubyte[] bytes =
            ['I', 'D', '3',
             0x04, 0x01,
             0x10,
             0x00, 0x00, 0x00, 0x01,

             0x55,

             '3', 'D', 'I',
             0x04, 0x01,
             0x10,
             0x00, 0x00, 0x00, 0x01];

        final switch (field)
        {
            case 0:
                bytes[15] = 0x02;
                break;

            case 1:
                bytes[16] = 0x30;
                break;

            case 2:
                bytes[20] = 0x02;
                break;
        }

        auto cursor = ByteCursor(ByteSpan(bytes, 200));
        auto result = cursor.parseId3v24TagEnvelope();

        assert(result.hasError);
        assert(
            result.error.code ==
            ParseErrorCode.inconsistentStructure
        );

        assert(cursor.position == 0);
        assert(cursor.absoluteOffset == 200);
    }
}


/// Invalid synchsafe footer sizes retain the exact offending offset.
unittest
{
    ubyte[] bytes =
        ['I', 'D', '3',
         0x04, 0x00,
         0x10,
         0x00, 0x00, 0x00, 0x00,

         '3', 'D', 'I',
         0x04, 0x00,
         0x10,
         0x00, 0x80, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));
    auto result = cursor.parseId3v24TagEnvelope();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSynchsafeInteger
    );
    assert(result.error.offset == 417);

    assert(cursor.position == 0);
}


/// Tag-envelope parsing preserves absolute offsets inside parent data.
unittest
{
    const ubyte[] bytes =
        [0x99,
         'I', 'D', '3',
         0x04, 0x00,
         0x00,
         0x00, 0x00, 0x00, 0x01,
         0x55,
         0xAA];

    auto cursor = ByteCursor(ByteSpan(bytes, 700));
    cursor.popFront();

    auto result = cursor.parseId3v24TagEnvelope();

    assert(result.hasValue);
    assert(result.value.header.sourceOffset == 701);
    assert(result.value.body.sourceOffset == 711);
    assert(result.value.endOffset == 712);

    assert(cursor.absoluteOffset == 712);
    assert(cursor.front == 0xAA);
}
