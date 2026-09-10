/++
Strict ID3v1 text-field encoding.

ID3v1 string fields are fixed-width ISO-8859-1 byte regions padded with NUL
bytes. This module is the exact inverse of `audiotag.id3v1.text_decode` for
canonical Unicode text that is representable in the native format.

Writer policy is deliberately conservative:

- input must be well-formed UTF-8;
- every Unicode scalar value must fit ISO-8859-1 (U+0000..U+00FF);
- U+0000 itself is rejected because NUL terminates ID3v1 semantic text;
- text is never truncated to fit a fixed field;
- unused output bytes are zero-filled.

No CP1252 or locale-dependent fallback is attempted.
+/
module audiotag.id3v1.text_encode;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


private enum Utf8Latin1Status : ubyte
{
    latin1,
    unsupported,
    invalid
}


private struct Utf8Latin1Decode
{
    Utf8Latin1Status status;
    ubyte value;
    size_t consumed;
}


private bool
isContinuation(
    ubyte value
)
    @safe pure nothrow @nogc
{
    return
        value >= 0x80 &&
        value <= 0xBF;
}


/++
Decodes and validates one UTF-8 scalar beginning at `offset`.

Only values through U+00FF are returned as `latin1`. Higher valid Unicode
scalars are reported as `unsupported`, while malformed UTF-8 is `invalid`.
+/
private Utf8Latin1Decode
decodeUtf8Latin1(
    string text,
    size_t offset
)
    @safe pure nothrow @nogc
{
    assert(offset < text.length);

    const b0 =
        cast(ubyte)
            text[offset];

    if (b0 <= 0x7F)
    {
        return
            Utf8Latin1Decode(
                Utf8Latin1Status.latin1,
                b0,
                1
            );
    }

    if (
        b0 >= 0xC2 &&
        b0 <= 0xDF
    )
    {
        if (
            offset + 1 >= text.length ||
            !isContinuation(
                cast(ubyte)
                    text[offset + 1]
            )
        )
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        const b1 =
            cast(ubyte)
                text[offset + 1];

        if (b0 <= 0xC3)
        {
            const codePoint =
                (
                    cast(uint)
                        (b0 & 0x1F) << 6
                ) |
                cast(uint)
                    (b1 & 0x3F);

            assert(codePoint <= 0xFF);

            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.latin1,
                    cast(ubyte)
                        codePoint,
                    2
                );
        }

        return
            Utf8Latin1Decode(
                Utf8Latin1Status.unsupported,
                0,
                2
            );
    }

    if (
        b0 >= 0xE0 &&
        b0 <= 0xEF
    )
    {
        if (offset + 2 >= text.length)
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        const b1 =
            cast(ubyte)
                text[offset + 1];

        const b2 =
            cast(ubyte)
                text[offset + 2];

        if (
            !isContinuation(b1) ||
            !isContinuation(b2)
        )
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        /*
         * Reject overlong three-byte encodings and UTF-16 surrogate scalar
         * values.
         */
        if (
            (
                b0 == 0xE0 &&
                b1 < 0xA0
            ) ||
            (
                b0 == 0xED &&
                b1 > 0x9F
            )
        )
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        return
            Utf8Latin1Decode(
                Utf8Latin1Status.unsupported,
                0,
                3
            );
    }

    if (
        b0 >= 0xF0 &&
        b0 <= 0xF4
    )
    {
        if (offset + 3 >= text.length)
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        const b1 =
            cast(ubyte)
                text[offset + 1];

        const b2 =
            cast(ubyte)
                text[offset + 2];

        const b3 =
            cast(ubyte)
                text[offset + 3];

        if (
            !isContinuation(b1) ||
            !isContinuation(b2) ||
            !isContinuation(b3)
        )
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        /*
         * Reject overlong four-byte encodings and values beyond U+10FFFF.
         */
        if (
            (
                b0 == 0xF0 &&
                b1 < 0x90
            ) ||
            (
                b0 == 0xF4 &&
                b1 > 0x8F
            )
        )
        {
            return
                Utf8Latin1Decode(
                    Utf8Latin1Status.invalid
                );
        }

        return
            Utf8Latin1Decode(
                Utf8Latin1Status.unsupported,
                0,
                4
            );
    }

    /*
     * Includes stray continuation bytes, overlong C0/C1 leaders and F5..FF.
     */
    return
        Utf8Latin1Decode(
            Utf8Latin1Status.invalid
        );
}


/++
Encodes one canonical UTF-8 string into an exact fixed-width ID3v1 text field.

The returned array always has exactly `width` bytes and is padded with zero
bytes after the encoded content.

Malformed UTF-8 is an `invalidValue` error. A valid Unicode scalar outside
ISO-8859-1 is an `unsupportedRepresentation` error. Embedded U+0000 is
`invalidValue` because it would terminate the native field early. Content
requiring more than `width` native bytes is `invalidLength`.

`SerializationError.index` identifies the UTF-8 input byte offset for text
representation errors and the first unrepresentable native output position for
a length overflow.

Params:
    text = Canonical UTF-8 text.
    width = Exact native ID3v1 field width.

Returns:
    Exact NUL-padded ISO-8859-1 field bytes or a structured writer error.
+/
SerializationResult!(ubyte[])
encodeId3v1Latin1Text(
    string text,
    size_t width
)
    @safe
{
    auto output =
        new ubyte[width];

    size_t inputOffset;
    size_t outputOffset;

    while (inputOffset < text.length)
    {
        const decoded =
            decodeUtf8Latin1(
                text,
                inputOffset
            );

        final switch (decoded.status)
        {
            case Utf8Latin1Status.invalid:
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .invalidValue,
                                inputOffset
                            )
                        );

            case Utf8Latin1Status.unsupported:
                return
                    SerializationResult!(ubyte[])
                        .failure(
                            SerializationError(
                                SerializationErrorCode
                                    .unsupportedRepresentation,
                                inputOffset
                            )
                        );

            case Utf8Latin1Status.latin1:
                break;
        }

        if (decoded.value == 0)
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            inputOffset
                        )
                    );
        }

        if (outputOffset >= width)
        {
            return
                SerializationResult!(ubyte[])
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidLength,
                            outputOffset,
                            cast(ulong)
                                outputOffset + 1,
                            width
                        )
                    );
        }

        output[outputOffset++] =
            decoded.value;

        inputOffset +=
            decoded.consumed;
    }

    return
        SerializationResult!(ubyte[])
            .success(output);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v1.text_decode :
        decodeId3v1Latin1Text;
}


/// ASCII text is emitted and the complete fixed-width remainder is NUL padded.
unittest
{
    auto result =
        encodeId3v1Latin1Text(
            "Title",
            8
        );

    assert(result.hasValue);
    assert(result.value.length == 8);

    assert(
        result.value ==
        [
            'T', 'i', 't', 'l', 'e',
            0x00, 0x00, 0x00
        ]
    );
}


/// ISO-8859-1 Unicode values roundtrip through the strict ID3v1 decoder.
unittest
{
    auto encoded =
        encodeId3v1Latin1Text(
            "\u00C4\u00F6\u00FF",
            5
        );

    assert(encoded.hasValue);

    assert(
        encoded.value ==
        [
            0xC4,
            0xF6,
            0xFF,
            0x00,
            0x00
        ]
    );

    assert(
        decodeId3v1Latin1Text(
            ByteSpan(
                encoded.value
            )
        ) ==
        "\u00C4\u00F6\u00FF"
    );
}


/// Exact field-width content is representable without an added terminator.
unittest
{
    auto result =
        encodeId3v1Latin1Text(
            "ABCD",
            4
        );

    assert(result.hasValue);

    assert(
        result.value ==
        cast(const(ubyte)[])
            "ABCD"
    );
}


/// Text is never truncated to fit a fixed-width field.
unittest
{
    auto result =
        encodeId3v1Latin1Text(
            "ABCDE",
            4
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidLength
    );

    assert(result.error.index == 4);
    assert(result.error.value == 5);
    assert(result.error.limit == 4);
}


/// Unicode outside ISO-8859-1 is rejected rather than approximated.
unittest
{
    auto result =
        encodeId3v1Latin1Text(
            "\u0100",
            30
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    assert(result.error.index == 0);
}


/// Embedded NUL cannot be represented as semantic ID3v1 text.
unittest
{
    auto result =
        encodeId3v1Latin1Text(
            "A\0B",
            30
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 1);
}


/// Malformed UTF-8 is rejected explicitly.
unittest
{
    const invalid =
        cast(string)
            [
                cast(char) 0xC2
            ];

    auto result =
        encodeId3v1Latin1Text(
            invalid,
            30
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 0);
}


/// Empty text produces a completely padded field, including width zero.
unittest
{
    auto padded =
        encodeId3v1Latin1Text(
            "",
            4
        );

    assert(padded.hasValue);

    assert(
        padded.value ==
        [
            0x00,
            0x00,
            0x00,
            0x00
        ]
    );

    auto empty =
        encodeId3v1Latin1Text(
            "",
            0
        );

    assert(empty.hasValue);
    assert(empty.value.length == 0);
}
