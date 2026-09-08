/++
Read-only MP3 prefix inspection.

This module recognizes only a prepended ID3v2 tag at the beginning of a
bounded byte source. ID3v2.3 and ID3v2.4 are delegated to their existing
revision-specific tag-envelope parsers.

The remainder is deliberately opaque. A successful result does not claim
that the remaining bytes are valid MPEG audio.
+/
module audiotag.mp3.prefix;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.tag :
    parseId3v23TagEnvelope;

import audiotag.id3v2.v24.tag :
    parseId3v24TagEnvelope;


/++
Identifies the supported prepended ID3v2 revision found at an MP3 source
prefix.
+/
enum Mp3LeadingId3v2Kind : ubyte
{
    /// No prepended ID3v2 tag is present.
    none,

    /// A prepended ID3v2.3 tag is present.
    v23,

    /// A prepended ID3v2.4 tag is present.
    v24
}


/++
Bounded read-only layout of the beginning of an MP3 byte source.

`leadingId3v2` is empty and positioned at the beginning of `source` when
no supported prepended tag is present. `remainder` then covers the whole
source.

When a supported tag is present, `leadingId3v2` contains the complete
physical tag envelope and `remainder` begins immediately after it.
+/
struct Mp3PrefixLayout
{
    /// Supported prepended ID3v2 revision, or `none`.
    Mp3LeadingId3v2Kind id3v2Kind;

    /// Complete prepended ID3v2 tag span, or an empty span.
    ByteSpan leadingId3v2;

    /// Bytes following the prepended tag, or the whole source if absent.
    ByteSpan remainder;
}


/++
Inspects the beginning of a bounded MP3 byte source for a prepended ID3v2
tag.

Only the exact `ID3` signature at the first source byte is treated as an
ID3v2 prefix. Supported major versions are delegated as follows:

- major version 3 → ID3v2.3 tag-envelope parser;
- major version 4 → ID3v2.4 tag-envelope parser.

No ID3 size or footer rule is duplicated here. A different ID3 major
version is reported as `unsupportedVersion`.

Params:
    source = Complete bounded byte source to inspect.

Returns:
    The bounded prefix layout, or a structured parse error from prefix
    dispatch or the delegated ID3 envelope parser.

Error semantics:
    The input is immutable. Malformed or truncated ID3 input produces a
    structured parse error and cannot partially modify caller state.
+/
ParseResult!Mp3PrefixLayout
parseMp3Prefix(ByteSpan source)
    @safe pure nothrow @nogc
{
    const data =
        source.data;

    if (
        data.length < 3 ||
        data[0] != 'I' ||
        data[1] != 'D' ||
        data[2] != '3'
    )
    {
        return
            ParseResult!Mp3PrefixLayout
                .success(
                    Mp3PrefixLayout(
                        Mp3LeadingId3v2Kind.none,
                        source.subspan(0, 0),
                        source
                    )
                );
    }

    if (data.length < 4)
    {
        return
            ParseResult!Mp3PrefixLayout
                .failure(
                    ParseError(
                        ParseErrorCode.endOfSpan,
                        source.sourceOffset + 3,
                        1,
                        0
                    )
                );
    }

    auto cursor =
        ByteCursor(source);

    Mp3LeadingId3v2Kind kind;

    switch (data[3])
    {
        case 3:
        {
            auto tagResult =
                cursor.parseId3v23TagEnvelope();

            if (tagResult.hasError)
            {
                return
                    ParseResult!Mp3PrefixLayout
                        .failure(tagResult.error);
            }

            kind =
                Mp3LeadingId3v2Kind.v23;

            break;
        }

        case 4:
        {
            auto tagResult =
                cursor.parseId3v24TagEnvelope();

            if (tagResult.hasError)
            {
                return
                    ParseResult!Mp3PrefixLayout
                        .failure(tagResult.error);
            }

            kind =
                Mp3LeadingId3v2Kind.v24;

            break;
        }

        default:
        {
            return
                ParseResult!Mp3PrefixLayout
                    .failure(
                        ParseError(
                            ParseErrorCode.unsupportedVersion,
                            source.sourceOffset + 3
                        )
                    );
        }
    }

    const consumed =
        cursor.position;

    const layout =
        Mp3PrefixLayout(
            kind,
            source.subspan(0, consumed),
            source.subspan(
                consumed,
                source.length - consumed
            )
        );

    return
        ParseResult!Mp3PrefixLayout
            .success(layout);
}


/// A source without an ID3 signature remains entirely available.
unittest
{
    const ubyte[] bytes =
        [0xFF, 0xFB, 0x90, 0x64];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 100)
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(
        layout.id3v2Kind ==
        Mp3LeadingId3v2Kind.none
    );

    assert(layout.leadingId3v2.empty);
    assert(layout.leadingId3v2.sourceOffset == 100);
    assert(layout.remainder.sourceOffset == 100);
    assert(layout.remainder.data == bytes);
}


/// An exact ID3 signature without a major-version byte is truncated.
unittest
{
    const ubyte[] bytes =
        ['I', 'D', '3'];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 200)
        );

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 203);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);
}


/// A prepended ID3v2.3 envelope is bounded before the remainder.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x02,
            0xAA, 0xBB,
            0xFF, 0xFB
        ];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 300)
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(
        layout.id3v2Kind ==
        Mp3LeadingId3v2Kind.v23
    );

    assert(layout.leadingId3v2.sourceOffset == 300);
    assert(layout.leadingId3v2.length == 12);
    assert(layout.remainder.sourceOffset == 312);
    assert(layout.remainder.data == [0xFF, 0xFB]);
}


/// A prepended ID3v2.4 footer belongs to the complete leading tag span.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x00,

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x00,

            0xFF, 0xFB
        ];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 400)
        );

    assert(result.hasValue);

    const layout =
        result.value;

    assert(
        layout.id3v2Kind ==
        Mp3LeadingId3v2Kind.v24
    );

    assert(layout.leadingId3v2.sourceOffset == 400);
    assert(layout.leadingId3v2.length == 20);
    assert(layout.remainder.sourceOffset == 420);
    assert(layout.remainder.data == [0xFF, 0xFB]);
}


/// Unsupported ID3 major versions fail at the version byte.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00
        ];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 500)
        );

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.unsupportedVersion
    );
    assert(result.error.offset == 503);
}


/// Truncated declared ID3v2.3 bodies preserve delegated error context.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x03,
            0xAA, 0xBB
        ];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 600)
        );

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.endOfSpan);
    assert(result.error.offset == 610);
    assert(result.error.requested == 3);
    assert(result.error.available == 2);
}


/// Invalid ID3v2.4 footers remain an ID3 structural error.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x00,

            'X', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x00
        ];

    auto result =
        parseMp3Prefix(
            ByteSpan(bytes, 700)
        );

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
    assert(result.error.offset == 710);
}
