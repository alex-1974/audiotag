/++
ID3v2.4 ordinary text-information payload serialization.

This module serializes only the semantic payload of ordinary `T***`
frames, excluding `TXXX`.

Regenerated and newly created ordinary text-information frames use
UTF-8 deterministically:

    $03 <value> [$00 <value> ...]

The final value normally needs no terminator because the enclosing frame
defines its extent. When the final logical value is empty, one final
zero byte is emitted so that the existing decoder can observe that
empty value.

No frame header or frame-format transformation is emitted here.
+/
module audiotag.id3v2.v24.text_information_write;

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
Measures and validates one UTF-8 ordinary text-information payload.

Validation guarantees:

- at least one logical text value;
- every D string contains valid UTF-8;
- no value contains U+0000, because zero is the native value separator;
- the complete payload fits the ID3v2.4 28-bit frame-size domain.

The returned size includes the `$03` encoding marker.

Params:
    values = Logical text values in native order.

Returns:
    Encoded payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v24Utf8TextInformationPayload(
    const(string)[] values
)
    @safe
{
    if (values.length == 0)
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.invalidLength
                )
            );
    }

    size_t total = 1; // UTF-8 encoding marker.

    foreach (valueIndex, value; values)
    {
        const valid =
            validLength(value);

        if (valid != value.length)
        {
            return
                SerializationResult!size_t.failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        total + valid
                    )
                );
        }

        foreach (byteIndex, valueByte; value)
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

        if (
            valueIndex + 1 <
            values.length
        )
        {
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
        }
    }

    /*
     * A final empty value must occupy one physical terminator byte.
     * Otherwise a trailing separator would only terminate the preceding
     * value and the decoder could not observe the final empty value.
     */
    if (values[$ - 1].length == 0)
    {
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
    }

    return
        SerializationResult!size_t.success(
            total
        );
}


/++
Serializes ordinary ID3v2.4 text-information values as UTF-8.

The output owns its bytes and begins with encoding marker `$03`.

Params:
    values = Logical text values in native order.

Returns:
    Encoded payload or the validation error reported by
    `measureId3v24Utf8TextInformationPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v24Utf8TextInformationPayload(
    const(string)[] values
)
    @safe
{
    auto measured =
        measureId3v24Utf8TextInformationPayload(
            values
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

    foreach (valueIndex, value; values)
    {
        foreach (valueByte; value)
        {
            output[position++] =
                cast(ubyte) valueByte;
        }

        if (
            valueIndex + 1 <
            values.length
        )
        {
            output[position++] = 0x00;
        }
    }

    if (values[$ - 1].length == 0)
        output[position++] = 0x00;

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// One UTF-8 value uses the encoding marker and no trailing terminator.
unittest
{
    const(string)[] values =
        ["Title"];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'T', 'i', 't', 'l', 'e'
        ]
    );
}


/// Ordered multiple values use one-byte UTF-8 separators.
unittest
{
    const(string)[] values =
        [
            "Artist A",
            "Artist B"
        ];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'A', 'r', 't', 'i', 's', 't', ' ', 'A',
            0x00,
            'A', 'r', 't', 'i', 's', 't', ' ', 'B'
        ]
    );
}


/// Non-ASCII UTF-8 bytes are preserved exactly.
unittest
{
    const(string)[] values =
        ["Grüße"];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'G', 'r',
            0xC3, 0xBC,
            0xC3, 0x9F,
            'e'
        ]
    );
}


/// One empty value remains observable by the existing decoder.
unittest
{
    const(string)[] values =
        [""];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [0x03, 0x00]
    );
}


/// A final empty value receives an additional physical terminator.
unittest
{
    const(string)[] values =
        ["Artist", ""];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'A', 'r', 't', 'i', 's', 't',
            0x00,
            0x00
        ]
    );
}


/// An empty logical value list has no lossless native representation.
unittest
{
    const(string)[] values = [];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidLength
    );
}


/// Embedded NUL would change native value cardinality and is rejected.
unittest
{
    const(string)[] values =
        ["A\0B"];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Malformed UTF-8 is rejected rather than copied into a UTF-8 frame.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    const(string)[] values =
        [malformed];

    auto result =
        serializeId3v24Utf8TextInformationPayload(
            values
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );
}
