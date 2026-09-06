/++
ID3v2.4 unique-file-identifier (`UFID`) payload serialization.

A UFID semantic payload contains:

    <non-empty owner identifier as ISO-8859-1> $00
    <zero to 64 opaque identifier bytes>

The owner terminator is mandatory. Identifier bytes occupy the
remainder of the payload and may contain arbitrary values including
zero bytes.

The 64-byte limit applies to the logical identifier bytes emitted by
this serializer.

This module emits semantic payload bytes only. It does not emit a frame
header, grouping identity, data-length indicator or byte
unsynchronisation transformation.
+/
module audiotag.id3v2.v24.unique_file_identifier_write;

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
Native UFID identifier-data limit.
+/
private enum size_t maximumIdentifierLength =
    64;


/++
Measures one non-empty UFID owner identifier after conversion from D
UTF-8 text to ID3 ISO-8859-1.

Embedded U+0000 is rejected because it would terminate the native owner
field before the intended boundary.
+/
private SerializationResult!size_t
measureUniqueFileIdentifierOwner(
    string ownerIdentifier
)
    @safe
{
    if (ownerIdentifier.length == 0)
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidValue,
                        0
                    )
                );
    }

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
Measures and validates one deterministic ID3v2.4 UFID semantic payload.

The returned size includes:

- the non-empty ISO-8859-1 owner;
- its mandatory null terminator;
- zero to 64 opaque identifier bytes.

Params:
    ownerIdentifier = Canonical UFID owner qualifier.
    identifier = Opaque logical identifier bytes.

Returns:
    Required payload length or a structured serialization error.
+/
SerializationResult!size_t
measureId3v24UniqueFileIdentifierPayload(
    string ownerIdentifier,
    const(ubyte)[] identifier
)
    @safe
{
    if (
        identifier.length >
        maximumIdentifierLength
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode.invalidLength,
                        0,
                        identifier.length,
                        maximumIdentifierLength
                    )
                );
    }

    auto owner =
        measureUniqueFileIdentifierOwner(
            ownerIdentifier
        );

    if (owner.hasError)
        return owner;

    /*
     * One byte is mandatory for the owner terminator.
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
        identifier.length >
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
                        identifier.length,
                        maximumFrameDataSize -
                            ownerAndTerminator
                    )
                );
    }

    return
        SerializationResult!size_t
            .success(
                ownerAndTerminator +
                identifier.length
            );
}


/++
Serializes one deterministic ID3v2.4 UFID semantic payload.

Identifier bytes are copied verbatim and may contain arbitrary byte
values including zero.

Params:
    ownerIdentifier = Non-empty canonical owner string.
    identifier = Zero to 64 opaque logical identifier bytes.

Returns:
    Owned payload bytes or a structured serialization error.
+/
SerializationResult!(ubyte[])
serializeId3v24UniqueFileIdentifierPayload(
    string ownerIdentifier,
    const(ubyte)[] identifier
)
    @safe
{
    auto measured =
        measureId3v24UniqueFileIdentifierPayload(
            ownerIdentifier,
            identifier
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
     * Measurement established one-byte ISO-8859-1 representability.
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

    foreach (byteValue; identifier)
    {
        output[position++] =
            byteValue;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// Normal UFID preserves owner and opaque identifier bytes exactly.
unittest
{
    auto measured =
        measureId3v24UniqueFileIdentifierPayload(
            "example.com",
            [
                cast(ubyte) 0x11,
                cast(ubyte) 0x22,
                cast(ubyte) 0xFE,
                cast(ubyte) 0xFF
            ]
        );

    assert(measured.hasValue);
    assert(measured.value == 16);

    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
            "example.com",
            [
                cast(ubyte) 0x11,
                cast(ubyte) 0x22,
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
            0x11, 0x22, 0xFE, 0xFF
        ]
    );
}


/// Empty identifier data is valid UFID content.
unittest
{
    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
            "owner",
            []
        );

    assert(serialized.hasValue);

    assert(
        serialized.value ==
        [
            'o', 'w', 'n', 'e', 'r',
            0x00
        ]
    );
}


/// Empty UFID owner is invalid.
unittest
{
    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
            "",
            []
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidValue
    );
}


/// UFID owner identifiers use ISO-8859-1 bytes.
unittest
{
    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
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


/// Owner characters outside ISO-8859-1 are rejected.
unittest
{
    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
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


/// Embedded NUL cannot silently truncate the UFID owner.
unittest
{
    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
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


/// Exactly 64 opaque identifier bytes remain representable.
unittest
{
    ubyte[64] identifier;

    foreach (index; 0 .. identifier.length)
    {
        identifier[index] =
            cast(ubyte) index;
    }

    auto measured =
        measureId3v24UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );

    assert(measured.hasValue);

    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );

    assert(serialized.hasValue);

    assert(
        serialized.value.length ==
        "owner".length +
        1 +
        64
    );

    assert(
        serialized.value[
            "owner".length + 1 ..
            $
        ] ==
        identifier[]
    );
}


/// A 65-byte logical UFID identifier violates the native limit.
unittest
{
    ubyte[65] identifier;

    auto measured =
        measureId3v24UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );

    assert(measured.hasError);

    assert(
        measured.error.code ==
        SerializationErrorCode.invalidLength
    );

    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );

    assert(serialized.hasError);

    assert(
        serialized.error.code ==
        SerializationErrorCode.invalidLength
    );
}


/// Opaque UFID bytes may contain zero values.
unittest
{
    auto serialized =
        serializeId3v24UniqueFileIdentifierPayload(
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
