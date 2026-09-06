/++
ID3v2.4 user-defined URL (`WXXX`) payload serialization.

Regenerated and newly created WXXX frames use deterministic UTF-8 for
the description and ISO-8859-1 for the URL:

    $03 <description> $00 <url>

The description terminator is mandatory even when the description is
empty.

The URL occupies the remainder of the frame and is therefore written
without its optional native terminator. Consequently an empty URL
occupies zero bytes after the description terminator.

The canonical model stores both description and URL strings as UTF-8.
The description may contain arbitrary valid UTF-8 except U+0000. The
URL must additionally be losslessly representable as ISO-8859-1.

No frame header or frame-format transformation is emitted here.
+/
module audiotag.id3v2.v24.user_url_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v24.url_link_write :
    measureId3v24UrlLinkPayload,
    serializeId3v24UrlLinkPayload;


/++
Maximum ID3v2.4 frame-data size representable by the four-byte
synchsafe frame-size field.
+/
private enum size_t maximumFrameDataSize =
    0x0FFF_FFFF;


/++
Converts an error whose index is relative to the canonical URL string
into an error whose index is relative to the complete WXXX payload.
+/
private SerializationError
shiftUrlError(
    const(SerializationError) error,
    size_t payloadUrlOffset
)
    @safe pure nothrow @nogc
{
    return
        SerializationError(
            error.code,
            payloadUrlOffset + error.index,
            error.value,
            error.limit
        );
}


/++
Measures and validates one deterministic WXXX payload.

Validation guarantees:

- the description is valid UTF-8;
- the description contains no U+0000;
- one mandatory description terminator fits;
- the URL is valid UTF-8 and losslessly representable as ISO-8859-1;
- the URL contains no U+0000;
- the complete payload fits the ID3v2.4 28-bit frame-size domain.

Unlike ordinary W*** serialization, an empty WXXX URL contributes zero
bytes because the preceding description structure already makes the
frame data non-empty.

Params:
    description = User-defined WXXX description.
    url = Canonical UTF-8 URL.

Returns:
    Encoded payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v24Utf8UserUrlPayload(
    string description,
    string url
)
    @safe
{
    size_t total = 1; // UTF-8 description encoding marker.

    const descriptionValid =
        validLength(description);

    if (
        descriptionValid !=
        description.length
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.invalidValue,
                    total + descriptionValid
                )
            );
    }

    foreach (
        byteIndex,
        descriptionByte;
        description
    )
    {
        if (descriptionByte == '\0')
        {
            return
                SerializationResult!size_t.failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        total + byteIndex
                    )
                );
        }
    }

    if (
        description.length >
        maximumFrameDataSize - total
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.valueOutOfRange,
                    0,
                    cast(ulong) total +
                        cast(ulong) description.length,
                    maximumFrameDataSize
                )
            );
    }

    total +=
        description.length;

    /*
     * WXXX always requires the encoded description terminator.
     */
    if (total == maximumFrameDataSize)
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.valueOutOfRange,
                    0,
                    cast(ulong) total + 1,
                    maximumFrameDataSize
                )
            );
    }

    ++total;

    /*
     * The URL terminator is optional for WXXX. The deterministic writer
     * omits it, so an empty URL contributes no further physical bytes.
     */
    if (url.length == 0)
    {
        return
            SerializationResult!size_t.success(
                total
            );
    }

    auto measuredUrl =
        measureId3v24UrlLinkPayload(
            url
        );

    if (measuredUrl.hasError)
    {
        return
            SerializationResult!size_t.failure(
                shiftUrlError(
                    measuredUrl.error,
                    total
                )
            );
    }

    /*
     * For a non-empty URL the ordinary W*** codec writes exactly the
     * ISO-8859-1 URL bytes and no terminator.
     */
    assert(measuredUrl.value != 0);

    if (
        measuredUrl.value >
        maximumFrameDataSize - total
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.valueOutOfRange,
                    total,
                    cast(ulong) total +
                        cast(ulong) measuredUrl.value,
                    maximumFrameDataSize
                )
            );
    }

    total +=
        measuredUrl.value;

    return
        SerializationResult!size_t.success(
            total
        );
}


/++
Serializes one canonical WXXX description/URL pair.

The deterministic physical representation is:

    $03 <description UTF-8> $00 <URL ISO-8859-1>

No optional URL terminator or trailing data is emitted.

Params:
    description = User-defined WXXX description.
    url = Canonical UTF-8 URL.

Returns:
    Owned native payload bytes or the validation error reported by
    `measureId3v24Utf8UserUrlPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v24Utf8UserUrlPayload(
    string description,
    string url
)
    @safe
{
    auto measured =
        measureId3v24Utf8UserUrlPayload(
            description,
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

    size_t position;

    output[position++] = 0x03;

    foreach (descriptionByte; description)
    {
        output[position++] =
            cast(ubyte) descriptionByte;
    }

    output[position++] = 0x00;

    if (url.length != 0)
    {
        auto serializedUrl =
            serializeId3v24UrlLinkPayload(
                url
            );

        /*
         * Measurement immediately above validated the same immutable URL.
         */
        assert(serializedUrl.hasValue);
        assert(serializedUrl.value.length != 0);

        output[
            position ..
            position + serializedUrl.value.length
        ] =
            serializedUrl.value[];

        position +=
            serializedUrl.value.length;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// UTF-8 description precedes an unterminated ISO-8859-1 URL.
unittest
{
    auto result =
        serializeId3v24Utf8UserUrlPayload(
            "home",
            "example.com"
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'h', 'o', 'm', 'e',
            0x00,
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );
}


/// Empty description and URL need only marker and description terminator.
unittest
{
    auto measured =
        measureId3v24Utf8UserUrlPayload(
            "",
            ""
        );

    assert(measured.hasValue);
    assert(measured.value == 2);

    auto result =
        serializeId3v24Utf8UserUrlPayload(
            "",
            ""
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [0x03, 0x00]
    );
}


/// Description remains UTF-8 while the URL is transcoded to ISO-8859-1.
unittest
{
    auto result =
        serializeId3v24Utf8UserUrlPayload(
            "Größe",
            "https://example.test/\u00E9"
        );

    assert(result.hasValue);

    assert(
        result.value[0 .. 8] ==
        [
            0x03,
            'G', 'r',
            0xC3, 0xB6,
            0xC3, 0x9F,
            'e'
        ]
    );

    assert(result.value[8] == 0x00);

    assert(
        result.value[$ - 1] ==
        0xE9
    );
}


/// Embedded NUL cannot terminate the WXXX description early.
unittest
{
    auto result =
        measureId3v24Utf8UserUrlPayload(
            "a\0b",
            "example.com"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    assert(result.error.index == 2);
}


/// Embedded NUL in the URL would truncate its native semantics.
unittest
{
    auto result =
        measureId3v24Utf8UserUrlPayload(
            "key",
            "a\0b"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    /*
     * $03 + "key" + $00 = five bytes before URL input offset one.
     */
    assert(result.error.index == 6);
}


/// URL Unicode outside ISO-8859-1 is rejected at payload-relative offset.
unittest
{
    auto result =
        measureId3v24Utf8UserUrlPayload(
            "key",
            "x\u20AC"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    /*
     * URL starts at payload offset five; Euro starts at UTF-8 input
     * offset one.
     */
    assert(result.error.index == 6);

    assert(result.error.value == 0x20AC);
    assert(result.error.limit == 0xFF);
}


/// Malformed UTF-8 description is rejected before URL validation.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    auto result =
        measureId3v24Utf8UserUrlPayload(
            malformed,
            "example.com"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 1);
}


/// Malformed UTF-8 URL error indices are shifted into the WXXX payload.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    auto result =
        measureId3v24Utf8UserUrlPayload(
            "key",
            malformed
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    /*
     * URL begins after $03 + "key" + $00.
     */
    assert(result.error.index == 5);
}


/// Measurement exactly matches serialized WXXX payload length.
unittest
{
    auto measured =
        measureId3v24Utf8UserUrlPayload(
            "homepage",
            "https://example.test/"
        );

    auto serialized =
        serializeId3v24Utf8UserUrlPayload(
            "homepage",
            "https://example.test/"
        );

    assert(measured.hasValue);
    assert(serialized.hasValue);

    assert(
        measured.value ==
        serialized.value.length
    );
}
