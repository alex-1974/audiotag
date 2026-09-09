/++
Strict ID3v1 text-field decoding.

The ID3v1 specification defines its string fields as ISO-8859-1 and requires
unused field bytes to be padded with zero bytes. This module implements that
specified representation without guessing alternate legacy encodings.

Raw field spans remain available from `Id3v1Tag`, so callers can deliberately
apply a different decoder to non-conforming real-world tags without losing
the original bytes.
+/
module audiotag.id3v1.text_decode;

import std.utf :
    encode;

import audiotag.core.span :
    ByteSpan;


/++
Returns the logical text bytes before the first ID3v1 NUL padding byte.

The returned span is zero-copy and preserves the original source offset.
Bytes after the first zero byte are treated as padding for semantic text
decoding but are not validated or discarded from the underlying raw tag.

Params:
    raw = One already bounded ID3v1 string field.

Returns:
    The zero-copy prefix before the first zero byte, or the whole field if no
    zero byte is present.
+/
ByteSpan
id3v1TextContent(
    ByteSpan raw
)
    @safe pure nothrow @nogc
{
    const bytes =
        raw.data;

    size_t length = 0;

    while (
        length < bytes.length &&
        bytes[length] != 0
    )
    {
        ++length;
    }

    return
        raw.subspan(
            0,
            length
        );
}


/++
Decodes one ID3v1 string field according to the specification.

The logical field ends at the first zero padding byte. Each preceding byte is
interpreted as one ISO-8859-1 code point and transcoded to UTF-8.

This semantic operation may allocate.

Params:
    raw = One already bounded ID3v1 string field.

Returns:
    An owned UTF-8 D string.
+/
string
decodeId3v1Latin1Text(
    ByteSpan raw
)
    @safe
{
    const content =
        id3v1TextContent(raw);

    char[] output;

    foreach (value; content.data)
    {
        encode(
            output,
            cast(dchar)
                value
        );
    }

    return
        output.idup;
}


/// The first zero byte terminates semantic text and preserves source offset.
unittest
{
    const ubyte[] bytes =
        [
            'A',
            'B',
            0x00,
            0x00
        ];

    const content =
        id3v1TextContent(
            ByteSpan(
                bytes,
                100
            )
        );

    assert(content.data == ['A', 'B']);
    assert(content.length == 2);
    assert(content.sourceOffset == 100);
}


/// A field without zero padding remains complete.
unittest
{
    const ubyte[] bytes =
        [
            'A',
            'B',
            'C'
        ];

    const content =
        id3v1TextContent(
            ByteSpan(
                bytes,
                200
            )
        );

    assert(content.data == bytes);
    assert(content.sourceOffset == 200);
}


/// ISO-8859-1 bytes are transcoded to UTF-8.
unittest
{
    const ubyte[] bytes =
        [
            'A',
            0xC4,
            0xF6,
            0xFF
        ];

    const decoded =
        decodeId3v1Latin1Text(
            ByteSpan(bytes)
        );

    assert(
        decoded ==
        "A\u00C4\u00F6\u00FF"
    );
}


/// Bytes after the first NUL remain raw but are not semantic text.
unittest
{
    ubyte[] bytes =
        [
            'A',
            0x00,
            'X'
        ];

    const raw =
        ByteSpan(bytes);

    const content =
        id3v1TextContent(raw);

    assert(content.data == ['A']);
    assert(raw.data[2] == 'X');

    bytes[0] = 'B';

    assert(content.data[0] == 'B');
    assert(
        decodeId3v1Latin1Text(raw) ==
        "B"
    );
}


/// An empty or fully padded field decodes to an empty string.
unittest
{
    const ubyte[] empty = [];
    const ubyte[] padded =
        [
            0x00,
            0x00,
            0x00
        ];

    assert(
        decodeId3v1Latin1Text(
            ByteSpan(empty)
        ).length == 0
    );

    assert(
        decodeId3v1Latin1Text(
            ByteSpan(padded)
        ).length == 0
    );
}
