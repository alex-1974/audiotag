/++
ID3v2.4 private-frame (`PRIV`) payload serialization.

A PRIV semantic payload contains:

    <owner identifier as ISO-8859-1> $00 <private binary data>

The owner terminator is mandatory. Private data occupies the remainder
of the bounded frame payload and may contain arbitrary bytes including
zero bytes.

This module serializes semantic payload bytes only. It does not emit a
frame header, grouping identity, data-length indicator or any
unsynchronisation transformation.
+/
module audiotag.id3v2.v24.private_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/++
Maximum semantic PRIV payload size representable by an ID3v2.4
four-byte synchsafe frame-size field.
+/
private enum size_t maximumFrameDataSize =
    0x0FFF_FFFF;


/++
Measures one owner identifier after conversion from D UTF-8 text to
ID3 ISO-8859-1.

Embedded U+0000 is rejected because it would terminate the owner field
before the intended boundary.

Empty owner identifiers remain representable; the resulting physical
owner field consists solely of its mandatory null terminator.
+/
private SerializationResult!size_t
measurePrivateOwner(
    string ownerIdentifier
)
    @safe
{
    const valid =
        validLength(ownerIdentifier);

    if (valid != ownerIdentifier.length)
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        valid
                    )
                );
    }

    size_t encodedLength;

    foreach (
        inputIndex,
        dchar codePoint;
        ownerIdentifier
    )
    {
        if (codePoint == 0)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            encodedLength,
                            0
                        )
                    );
        }

        if (codePoint > 0xFF)
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            encodedLength,
                            cast(ulong) codePoint,
                            0xFF
                        )
                    );
        }

        ++encodedLength;
    }

    return
        SerializationResult!size_t
            .success(encodedLength);
}


/++
Measures and validates one deterministic ID3v2.4 PRIV semantic payload.

The returned size includes:

- ISO-8859-1 owner bytes;
- the mandatory one-byte owner terminator;
- all private binary bytes.

The complete semantic payload must fit the 28-bit ID3v2.4 frame-size
domain.

Params:
    ownerIdentifier = Canonical PRIV owner qualifier.
    privateData = Opaque logical private bytes.

Returns:
    Required payload length or a structured serialization error.
+/
SerializationResult!size_t
measureId3v24PrivatePayload(
    string ownerIdentifier,
    const(ubyte)[] privateData
)
    @safe
{
    auto owner =
        measurePrivateOwner(
            ownerIdentifier
        );

    if (owner.hasError)
        return owner;

    /*
     * One byte is always required for the owner terminator.
     */
    if (
        owner.value >=
        maximumFrameDataSize
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidLength,
                        owner.value,
                        1,
                        maximumFrameDataSize -
                            owner.value
                    )
                );
    }

    const ownerAndTerminator =
        owner.value + 1;

    if (
        privateData.length >
        maximumFrameDataSize -
            ownerAndTerminator
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidLength,
                        ownerAndTerminator,
                        privateData.length,
                        maximumFrameDataSize -
                            ownerAndTerminator
                    )
                );
    }

    return
        SerializationResult!size_t
            .success(
                ownerAndTerminator +
                privateData.length
            );
}


/++
Serializes one deterministic ID3v2.4 PRIV semantic payload.

Private binary bytes are copied unchanged and may contain arbitrary
values including U+0000-like zero bytes.

Params:
    ownerIdentifier = Canonical owner string.
    privateData = Opaque logical private data.

Returns:
    Owned payload bytes or a structured serialization error.
+/
SerializationResult!(ubyte[])
serializeId3v24PrivatePayload(
    string ownerIdentifier,
    const(ubyte)[] privateData
)
    @safe
{
    auto measured =
        measureId3v24PrivatePayload(
            ownerIdentifier,
            privateData
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

    /*
     * Measurement already proved that every Unicode scalar value fits
     * exactly one ISO-8859-1 byte.
     */
    foreach (
        dchar codePoint;
        ownerIdentifier
    )
    {
        output[position++] =
            cast(ubyte) codePoint;
    }

    output[position++] =
        0x00;

    foreach (byteValue; privateData)
    {
        output[position++] =
            byteValue;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// A normal PRIV payload preserves owner and opaque binary data exactly.
unittest
{
    auto measured =
        measureId3v24PrivatePayload(
            "example.com",
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x02,
                cast(ubyte) 0xFE,
                cast(ubyte) 0xFF
            ]
        );

    assert(measured.hasValue);
    assert(measured.value == 16);

    auto serialized =
        serializeId3v24PrivatePayload(
            "example.com",
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x02,
                cast(ubyte) 0xFE,
                cast(ubyte) 0xFF
            ]
        );

    assert(serialized.hasValue);
    assert(serialized.value.length == measured.value);

    assert(
        serialized.value ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm',
            0x00,
            0x01, 0x02, 0xFE, 0xFF
        ]
    );
}


/// Empty owner and empty private data retain the mandatory owner terminator.
unittest
{
    auto serialized =
        serializeId3v24PrivatePayload(
            "",
            []
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [0x00]
    );
}


/// Owner identifiers use ID3 ISO-8859-1 bytes.
unittest
{
    auto serialized =
        serializeId3v24PrivatePayload(
            "caf\u00E9",
            []
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'c', 'a', 'f',
            0xE9,
            0x00
        ]
    );
}


/// Owner identifiers outside ISO-8859-1 are not silently rewritten.
unittest
{
    auto serialized =
        serializeId3v24PrivatePayload(
            "owner/\u20AC",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Embedded NUL cannot silently truncate the PRIV owner identifier.
unittest
{
    auto serialized =
        serializeId3v24PrivatePayload(
            "owner\0suffix",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}


/// Private data remains opaque and may contain zero bytes.
unittest
{
    auto serialized =
        serializeId3v24PrivatePayload(
            "owner",
            [
                cast(ubyte) 0x00,
                cast(ubyte) 0xFF,
                cast(ubyte) 0x00,
                cast(ubyte) 0x7F
            ]
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'o', 'w', 'n', 'e', 'r',
            0x00,
            0x00, 0xFF, 0x00, 0x7F
        ]
    );
}
