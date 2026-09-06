/++
ID3v2.4 ordinary URL-link payload serialization.

Ordinary `W***` frames, excluding `WXXX`, contain an ISO-8859-1 URL
without an encoding marker.

The canonical metadata model stores strings as UTF-8. Serialization
therefore validates the UTF-8 input and requires every Unicode scalar
value to be losslessly representable as one ISO-8859-1 byte.

Deterministic writer representation:

- non-empty URLs are written directly to the frame boundary without a
  terminator;
- an empty URL is written as one zero terminator byte so the resulting
  frame-data size remains non-zero;
- embedded U+0000 is rejected because it would terminate the native URL;
- Unicode values above U+00FF are rejected rather than transcoded
  lossily.

`WXXX` has a different native structure and is intentionally outside
this module.
+/
module audiotag.id3v2.v24.url_link_write;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


private enum size_t maximumFrameDataSize =
    0x0FFF_FFFF;


/++
Result of decoding one UTF-8 scalar from a canonical D string.
+/
private struct Utf8Scalar
{
    bool valid;
    uint codePoint;
    size_t width;
}


/++
Returns whether one byte is a UTF-8 continuation byte.
+/
private bool isUtf8Continuation(
    ubyte value
)
    @safe pure nothrow @nogc
{
    return
        (
            value &
            0xC0
        ) ==
        0x80;
}


/++
Decodes and validates one UTF-8 scalar beginning at `index`.

The function accepts only shortest-form UTF-8, rejects surrogate code
points and rejects values beyond U+10FFFF.

No input is consumed because this is an index-based validation helper.
+/
private Utf8Scalar decodeUtf8Scalar(
    string input,
    size_t index
)
    @safe pure nothrow @nogc
{
    assert(index < input.length);

    const first =
        cast(ubyte)
            input[index];

    if (first <= 0x7F)
    {
        return
            Utf8Scalar(
                true,
                first,
                1
            );
    }

    if (
        first >= 0xC2 &&
        first <= 0xDF
    )
    {
        if (
            index + 1 >= input.length
        )
        {
            return Utf8Scalar.init;
        }

        const second =
            cast(ubyte)
                input[index + 1];

        if (!isUtf8Continuation(second))
            return Utf8Scalar.init;

        const codePoint =
            (
                cast(uint)
                    (first & 0x1F)
                << 6
            ) |
            cast(uint)
                (second & 0x3F);

        return
            Utf8Scalar(
                true,
                codePoint,
                2
            );
    }

    if (
        first >= 0xE0 &&
        first <= 0xEF
    )
    {
        if (
            index + 2 >= input.length
        )
        {
            return Utf8Scalar.init;
        }

        const second =
            cast(ubyte)
                input[index + 1];

        const third =
            cast(ubyte)
                input[index + 2];

        if (
            !isUtf8Continuation(second) ||
            !isUtf8Continuation(third)
        )
        {
            return Utf8Scalar.init;
        }

        /*
         * E0 must not encode an overlong value.
         * ED must not encode UTF-16 surrogate code points.
         */
        if (
            first == 0xE0 &&
            second < 0xA0
        )
        {
            return Utf8Scalar.init;
        }

        if (
            first == 0xED &&
            second >= 0xA0
        )
        {
            return Utf8Scalar.init;
        }

        const codePoint =
            (
                cast(uint)
                    (first & 0x0F)
                << 12
            ) |
            (
                cast(uint)
                    (second & 0x3F)
                << 6
            ) |
            cast(uint)
                (third & 0x3F);

        return
            Utf8Scalar(
                true,
                codePoint,
                3
            );
    }

    if (
        first >= 0xF0 &&
        first <= 0xF4
    )
    {
        if (
            index + 3 >= input.length
        )
        {
            return Utf8Scalar.init;
        }

        const second =
            cast(ubyte)
                input[index + 1];

        const third =
            cast(ubyte)
                input[index + 2];

        const fourth =
            cast(ubyte)
                input[index + 3];

        if (
            !isUtf8Continuation(second) ||
            !isUtf8Continuation(third) ||
            !isUtf8Continuation(fourth)
        )
        {
            return Utf8Scalar.init;
        }

        /*
         * F0 must not encode an overlong value.
         * F4 is limited to U+10FFFF.
         */
        if (
            first == 0xF0 &&
            second < 0x90
        )
        {
            return Utf8Scalar.init;
        }

        if (
            first == 0xF4 &&
            second > 0x8F
        )
        {
            return Utf8Scalar.init;
        }

        const codePoint =
            (
                cast(uint)
                    (first & 0x07)
                << 18
            ) |
            (
                cast(uint)
                    (second & 0x3F)
                << 12
            ) |
            (
                cast(uint)
                    (third & 0x3F)
                << 6
            ) |
            cast(uint)
                (fourth & 0x3F);

        return
            Utf8Scalar(
                true,
                codePoint,
                4
            );
    }

    return Utf8Scalar.init;
}


/++
Measures a deterministic ordinary ID3v2.4 URL-link payload.

The input is validated as UTF-8 and every scalar must fit ISO-8859-1.

For an empty canonical URL the payload length is one because the writer
uses one native zero terminator to preserve an empty URL while retaining
the non-zero frame-data invariant.

Params:
    url = Canonical UTF-8 URL.

Returns:
    Native payload byte count or a structured serialization failure.

Error semantics:
    `SerializationError.index` identifies the UTF-8 code-unit offset at
    which an invalid or unrepresentable scalar begins.
+/
SerializationResult!size_t
measureId3v24UrlLinkPayload(
    string url
)
    @safe pure nothrow @nogc
{
    if (url.length == 0)
    {
        return
            SerializationResult!size_t
                .success(1);
    }

    size_t index;
    size_t encodedLength;

    while (index < url.length)
    {
        const scalar =
            decodeUtf8Scalar(
                url,
                index
            );

        if (!scalar.valid)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            index,
                            cast(ubyte)
                                url[index]
                        )
                    );
        }

        if (scalar.codePoint == 0)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            index,
                            0
                        )
                    );
        }

        if (scalar.codePoint > 0xFF)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            index,
                            scalar.codePoint,
                            0xFF
                        )
                    );
        }

        ++encodedLength;

        if (
            encodedLength >
            maximumFrameDataSize
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .valueOutOfRange,
                            index,
                            encodedLength,
                            maximumFrameDataSize
                        )
                    );
        }

        index += scalar.width;
    }

    return
        SerializationResult!size_t
            .success(encodedLength);
}


/++
Serializes one canonical URL as an ordinary ID3v2.4 `W***` payload.

No text-encoding marker is emitted.

A non-empty URL occupies exactly one ISO-8859-1 byte per Unicode scalar.
An empty URL becomes one zero terminator byte.

Params:
    url = Canonical UTF-8 URL.

Returns:
    Owned native payload bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeId3v24UrlLinkPayload(
    string url
)
    @safe
{
    auto measured =
        measureId3v24UrlLinkPayload(
            url
        );

    if (measured.hasError)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    measured.error
                );
    }

    auto output =
        new ubyte[
            measured.value
        ];

    if (url.length == 0)
    {
        /*
         * Dynamic arrays are zero-initialized. This single byte is the
         * optional native URL terminator and represents an empty URL.
         */
        assert(output.length == 1);
        assert(output[0] == 0);

        return
            SerializationResult!(ubyte[])
                .success(output);
    }

    size_t inputIndex;
    size_t outputIndex;

    while (inputIndex < url.length)
    {
        const scalar =
            decodeUtf8Scalar(
                url,
                inputIndex
            );

        /*
         * Measurement validated this immutable input immediately above.
         * These are programmer invariants, not external-input checks.
         */
        assert(scalar.valid);
        assert(scalar.codePoint != 0);
        assert(scalar.codePoint <= 0xFF);

        output[outputIndex++] =
            cast(ubyte)
                scalar.codePoint;

        inputIndex +=
            scalar.width;
    }

    assert(outputIndex == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


version (unittest)
{
}


/// ASCII URL bytes are written without an encoding marker or terminator.
unittest
{
    const url =
        "https://example.test/a";

    auto measured =
        measureId3v24UrlLinkPayload(
            url
        );

    assert(measured.hasValue);
    assert(measured.value == url.length);

    auto serialized =
        serializeId3v24UrlLinkPayload(
            url
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        cast(const(ubyte)[])
            url
    );
}


/// Relative URLs remain valid ordinary URL-link payloads.
unittest
{
    auto serialized =
        serializeId3v24UrlLinkPayload(
            "../audio.x"
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            '.', '.', '/',
            'a', 'u', 'd', 'i', 'o',
            '.', 'x'
        ]
    );
}


/// ISO-8859-1 characters are transcoded losslessly from canonical UTF-8.
unittest
{
    auto serialized =
        serializeId3v24UrlLinkPayload(
            "https://example.test/\u00E9"
        );

    assert(serialized.hasValue);

    assert(
        serialized.value[
            $ - 1
        ] ==
        0xE9
    );

    assert(
        serialized.value.length ==
        "https://example.test/".length +
        1
    );
}


/// The upper ISO-8859-1 scalar U+00FF is representable.
unittest
{
    auto serialized =
        serializeId3v24UrlLinkPayload(
            "\u00FF"
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [0xFF]
    );
}


/// An empty canonical URL uses one native zero terminator.
unittest
{
    auto measured =
        measureId3v24UrlLinkPayload(
            ""
        );

    assert(measured.hasValue);
    assert(measured.value == 1);

    auto serialized =
        serializeId3v24UrlLinkPayload(
            ""
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [0x00]
    );
}


/// Embedded NUL would truncate native semantics and is rejected.
unittest
{
    auto measured =
        measureId3v24UrlLinkPayload(
            "abc\0def"
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(measured.error.index == 3);
}


/// Unicode outside ISO-8859-1 is never silently approximated.
unittest
{
    auto measured =
        measureId3v24UrlLinkPayload(
            "https://example.test/\u20AC"
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    assert(
        measured.error.value ==
        0x20AC
    );

    assert(
        measured.error.limit ==
        0xFF
    );
}


/// A truncated UTF-8 sequence is rejected at its leading byte.
unittest
{
    const invalid =
        cast(string)
            [
                cast(char) 'x',
                cast(char) 0xC3
            ];

    auto measured =
        measureId3v24UrlLinkPayload(
            invalid
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(measured.error.index == 1);
}


/// UTF-8 continuation bytes cannot occur without a leading byte.
unittest
{
    const invalid =
        cast(string)
            [
                cast(char) 0x80
            ];

    auto measured =
        measureId3v24UrlLinkPayload(
            invalid
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(measured.error.index == 0);
}


/// Overlong UTF-8 encodings are rejected.
unittest
{
    const invalid =
        cast(string)
            [
                cast(char) 0xC0,
                cast(char) 0xAF
            ];

    auto measured =
        measureId3v24UrlLinkPayload(
            invalid
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode.invalidValue
    );
}


/// UTF-8 surrogate encodings are rejected.
unittest
{
    const invalid =
        cast(string)
            [
                cast(char) 0xED,
                cast(char) 0xA0,
                cast(char) 0x80
            ];

    auto measured =
        measureId3v24UrlLinkPayload(
            invalid
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode.invalidValue
    );
}


/// Valid multibyte Unicode may still be structurally valid but unrepresentable.
unittest
{
    auto measured =
        measureId3v24UrlLinkPayload(
            "\U0001F600"
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    assert(
        measured.error.value ==
        0x1F600
    );
}
