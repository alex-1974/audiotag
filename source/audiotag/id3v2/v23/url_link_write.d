/++
ID3v2.3 ordinary URL-link payload serialization.

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

ID3v2.3 frame sizes are ordinary unsigned 32-bit big-endian values, so
this module uses the complete non-zero 32-bit frame-data domain rather
than the 28-bit synchsafe limit used by ID3v2.4.

`WXXX` has a different native structure and is intentionally outside
this module.

No frame header or tag-level unsynchronisation is emitted here.
+/
module audiotag.id3v2.v23.url_link_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/++
Maximum frame-data size representable by an ID3v2.3 frame header.
+/
private enum size_t maximumFrameDataSize =
    uint.max;


/++
Measures a deterministic ordinary ID3v2.3 URL-link payload.

The input is validated as UTF-8 and every scalar must fit exactly one
ISO-8859-1 byte.

For an empty canonical URL the payload length is one because the writer
uses one native zero terminator to preserve the empty value while also
retaining the ID3v2.3 non-zero frame-data invariant.

Params:
    url = Canonical UTF-8 URL.

Returns:
    Native payload byte count or a structured serialization failure.

Error semantics:
    `SerializationError.index` identifies the UTF-8 code-unit offset at
    which an invalid or unrepresentable scalar begins.
+/
SerializationResult!size_t
measureId3v23UrlLinkPayload(
    string url
)
    @safe
{
    if (
        url.length == 0
    )
    {
        return
            SerializationResult!size_t
                .success(
                    1
                );
    }


    const valid =
        validLength(
            url
        );


    if (
        valid !=
        url.length
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        valid,
                        cast(ubyte)
                            url[valid]
                    )
                );
    }


    size_t encodedLength;


    foreach (
        byteIndex,
        dchar codePoint;
        url
    )
    {
        if (
            codePoint == 0
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            byteIndex,
                            0
                        )
                    );
        }


        if (
            codePoint >
            0xFF
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            byteIndex,
                            cast(ulong)
                                codePoint,
                            0xFF
                        )
                    );
        }


        /*
         * Check before incrementing so the complete uint domain remains
         * valid even when size_t itself is 32 bits.
         */
        if (
            encodedLength ==
            maximumFrameDataSize
        )
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .valueOutOfRange,
                            byteIndex,
                            cast(ulong)
                                encodedLength +
                                1,
                            maximumFrameDataSize
                        )
                    );
        }


        ++encodedLength;
    }


    return
        SerializationResult!size_t
            .success(
                encodedLength
            );
}


/++
Serializes one canonical URL as an ordinary ID3v2.3 `W***` payload.

No text-encoding marker is emitted.

A non-empty URL occupies exactly one ISO-8859-1 byte per Unicode scalar.
An empty URL becomes one zero terminator byte.

Params:
    url = Canonical UTF-8 URL.

Returns:
    Owned native payload bytes or a structured serialization failure.
+/
SerializationResult!(ubyte[])
serializeId3v23UrlLinkPayload(
    string url
)
    @safe
{
    auto measured =
        measureId3v23UrlLinkPayload(
            url
        );


    if (
        measured.hasError
    )
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


    if (
        url.length == 0
    )
    {
        /*
         * Dynamic arrays are zero-initialized. This byte is the optional
         * native URL terminator representing the empty URL.
         */
        assert(
            output.length ==
            1
        );

        assert(
            output[0] ==
            0
        );


        return
            SerializationResult!(ubyte[])
                .success(
                    output
                );
    }


    size_t outputIndex;


    /*
     * Measurement validated the immutable input immediately above and
     * established one-byte ISO-8859-1 representability.
     */
    foreach (
        dchar codePoint;
        url
    )
    {
        assert(
            codePoint !=
            0
        );

        assert(
            codePoint <=
            0xFF
        );


        output[
            outputIndex++
        ] =
            cast(ubyte)
                codePoint;
    }


    assert(
        outputIndex ==
        output.length
    );


    return
        SerializationResult!(ubyte[])
            .success(
                output
            );
}


/// ASCII URL bytes are written without an encoding marker or terminator.
unittest
{
    const url =
        "https://example.test/a";


    auto measured =
        measureId3v23UrlLinkPayload(
            url
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        url.length
    );


    auto serialized =
        serializeId3v23UrlLinkPayload(
            url
        );


    assert(
        serialized.hasValue
    );


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
        serializeId3v23UrlLinkPayload(
            "../audio.x"
        );


    assert(
        serialized.hasValue
    );


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
        serializeId3v23UrlLinkPayload(
            "https://example.test/\u00E9"
        );


    assert(
        serialized.hasValue
    );


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


/// The upper ISO-8859-1 scalar U+00FF remains representable.
unittest
{
    auto serialized =
        serializeId3v23UrlLinkPayload(
            "\u00FF"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [0xFF]
    );
}


/// An empty canonical URL uses one native zero terminator.
unittest
{
    auto measured =
        measureId3v23UrlLinkPayload(
            ""
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        1
    );


    auto serialized =
        serializeId3v23UrlLinkPayload(
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [0x00]
    );
}


/// Embedded NUL would truncate native semantics and is rejected.
unittest
{
    auto measured =
        measureId3v23UrlLinkPayload(
            "abc\0def"
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidValue
    );


    assert(
        measured.error.index ==
        3
    );
}


/// Unicode outside ISO-8859-1 is never silently approximated.
unittest
{
    auto measured =
        measureId3v23UrlLinkPayload(
            "https://example.test/\u20AC"
        );


    assert(
        measured.hasError
    );


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
        measureId3v23UrlLinkPayload(
            invalid
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidValue
    );


    assert(
        measured.error.index ==
        1
    );
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
        measureId3v23UrlLinkPayload(
            invalid
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidValue
    );


    assert(
        measured.error.index ==
        0
    );
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
        measureId3v23UrlLinkPayload(
            invalid
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidValue
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
        measureId3v23UrlLinkPayload(
            invalid
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidValue
    );
}


/// Valid Unicode outside Latin-1 remains structurally valid but unrepresentable.
unittest
{
    auto measured =
        measureId3v23UrlLinkPayload(
            "\U0001F600"
        );


    assert(
        measured.hasError
    );


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
