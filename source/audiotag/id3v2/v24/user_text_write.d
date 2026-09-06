/++
ID3v2.4 user-defined text (`TXXX`) payload serialization.

Regenerated and newly created TXXX frames use UTF-8 deterministically:

    $03 <description> $00 <value>

The description terminator is mandatory even when the description is
empty. The value occupies the remainder of the bounded frame payload and
therefore receives no trailing terminator.

The current canonical model represents one TXXX frame as one scalar
`MetadataText` plus canonical field description context. Embedded U+0000
is therefore rejected in both parts rather than introducing ambiguous
native separator semantics.

No frame header or frame-format transformation is emitted here.
+/
module audiotag.id3v2.v24.user_text_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/++
Maximum ID3v2.4 frame-data size representable by the four-byte
synchsafe frame-size field.
+/
private enum size_t maximumFrameDataSize =
    0x0FFF_FFFF;


/++
Measures and validates one deterministic UTF-8 TXXX payload.

Validation guarantees:

- description and value contain valid UTF-8;
- neither contains U+0000;
- one mandatory description terminator fits;
- the complete payload fits the ID3v2.4 28-bit frame-size domain.

The returned size includes:

- the `$03` UTF-8 encoding marker;
- description bytes;
- the one-byte description terminator;
- value bytes.

Params:
    description = User-defined TXXX description.
    value = Scalar user-defined text value.

Returns:
    Encoded payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v24Utf8UserTextPayload(
    string description,
    string value
)
    @safe
{
    size_t total = 1; // UTF-8 encoding marker.

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

    total += description.length;

    /*
     * TXXX always requires a description terminator.
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

    const valueValid =
        validLength(value);

    if (
        valueValid !=
        value.length
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.invalidValue,
                    total + valueValid
                )
            );
    }

    foreach (
        byteIndex,
        valueByte;
        value
    )
    {
        if (valueByte == '\0')
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
        value.length >
        maximumFrameDataSize - total
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.valueOutOfRange,
                    0,
                    cast(ulong) total +
                        cast(ulong) value.length,
                    maximumFrameDataSize
                )
            );
    }

    total += value.length;

    return
        SerializationResult!size_t.success(
            total
        );
}


/++
Serializes one canonical TXXX description/value pair as deterministic
UTF-8 frame data.

The resulting payload is:

    $03 <description> $00 <value>

The output owns its bytes.

Params:
    description = User-defined TXXX description.
    value = Scalar user-defined text value.

Returns:
    Encoded payload or the validation error reported by
    `measureId3v24Utf8UserTextPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v24Utf8UserTextPayload(
    string description,
    string value
)
    @safe
{
    auto measured =
        measureId3v24Utf8UserTextPayload(
            description,
            value
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

    /*
     * Mandatory TXXX description terminator.
     */
    output[position++] = 0x00;

    foreach (valueByte; value)
    {
        output[position++] =
            cast(ubyte) valueByte;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// Description and scalar value use the native TXXX UTF-8 layout.
unittest
{
    auto result =
        serializeId3v24Utf8UserTextPayload(
            "key",
            "value"
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'k', 'e', 'y',
            0x00,
            'v', 'a', 'l', 'u', 'e'
        ]
    );
}


/// Empty description and value retain the mandatory separator.
unittest
{
    auto result =
        serializeId3v24Utf8UserTextPayload(
            "",
            ""
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            0x00
        ]
    );
}


/// Non-ASCII description and value are emitted as UTF-8.
unittest
{
    auto result =
        serializeId3v24Utf8UserTextPayload(
            "Größe",
            "Grüße"
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,

            'G', 'r',
            0xC3, 0xB6,
            0xC3, 0x9F,
            'e',

            0x00,

            'G', 'r',
            0xC3, 0xBC,
            0xC3, 0x9F,
            'e'
        ]
    );
}


/// Embedded NUL in the description would terminate it early.
unittest
{
    auto result =
        measureId3v24Utf8UserTextPayload(
            "a\0b",
            "value"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    /*
     * Encoding marker occupies payload position zero.
     */
    assert(result.error.index == 2);
}


/// Embedded NUL in the scalar value is conservatively unsupported.
unittest
{
    auto result =
        measureId3v24Utf8UserTextPayload(
            "key",
            "a\0b"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    /*
     * $03 + "key" + $00 + "a" = first invalid byte at index 6.
     */
    assert(result.error.index == 6);
}


/// Malformed UTF-8 descriptions are rejected with payload-relative index.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    auto result =
        measureId3v24Utf8UserTextPayload(
            malformed,
            "value"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 1);
}


/// Malformed UTF-8 values are rejected after the description separator.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    auto result =
        measureId3v24Utf8UserTextPayload(
            "key",
            malformed
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    /*
     * $03 + "key" + $00 = five bytes before the value.
     */
    assert(result.error.index == 5);
}


/// Measurement exactly matches serialization for normal input.
unittest
{
    auto measured =
        measureId3v24Utf8UserTextPayload(
            "MusicBrainz Album Id",
            "abc-123"
        );

    auto serialized =
        serializeId3v24Utf8UserTextPayload(
            "MusicBrainz Album Id",
            "abc-123"
        );

    assert(measured.hasValue);
    assert(serialized.hasValue);

    assert(
        measured.value ==
        serialized.value.length
    );
}
