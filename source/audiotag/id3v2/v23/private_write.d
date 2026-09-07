/++
ID3v2.3 private-frame (`PRIV`) payload serialization.

A PRIV semantic payload contains:

    <owner identifier as ISO-8859-1> $00 <private binary data>

The owner terminator is mandatory.

The owner identifier is supplied as canonical UTF-8 text and must be
losslessly representable as ISO-8859-1. Embedded U+0000 is rejected
because it would terminate the native owner field early.

An empty owner identifier is valid and is represented solely by the
mandatory zero terminator.

Private data occupies the remainder of the semantic payload and may
contain arbitrary bytes, including zero bytes. Empty private data is
valid.

This module emits logical semantic payload bytes only. It does not emit
a frame header, grouping identity, compression/encryption additions or
ID3v2.3 whole-tag unsynchronisation.
+/
module audiotag.id3v2.v23.private_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/++
Maximum semantic frame-data size representable by the ordinary unsigned
32-bit ID3v2.3 frame-size field.
+/
private enum size_t maximumFrameDataSize =
    uint.max;


/++
Measures one PRIV owner identifier after lossless conversion from
canonical UTF-8 text to native ISO-8859-1.

Embedded U+0000 is rejected because it would terminate the owner field
before the intended boundary.

Empty owner identifiers remain valid and have encoded length zero; the
mandatory terminator is accounted for by the enclosing payload
measurer.

Params:
    ownerIdentifier = Canonical owner identifier.

Returns:
    Number of ISO-8859-1 owner bytes or a structured serialization
    failure.

Error semantics:
    Malformed UTF-8 produces `invalidValue`.

    Unicode outside ISO-8859-1 or embedded U+0000 produces
    `unsupportedRepresentation`.
+/
private SerializationResult!size_t
measurePrivateOwner(
    string ownerIdentifier
)
    @safe
{
    const valid =
        validLength(
            ownerIdentifier
        );


    if (
        valid !=
        ownerIdentifier.length
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
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
        if (
            codePoint ==
            0
        )
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
                            encodedLength,
                            cast(ulong)
                                codePoint,
                            0xFF
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
Measures and validates one deterministic ID3v2.3 PRIV semantic payload.

The returned size includes:

- ISO-8859-1 owner bytes;
- the mandatory one-byte owner terminator;
- all opaque private binary bytes.

The complete semantic payload must fit the ordinary unsigned 32-bit
ID3v2.3 frame-size domain.

Params:
    ownerIdentifier = Canonical PRIV owner qualifier.
    privateData = Opaque logical private bytes.

Returns:
    Required payload length or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23PrivatePayload(
    string ownerIdentifier,
    const(ubyte)[] privateData
)
    @safe
{
    auto owner =
        measurePrivateOwner(
            ownerIdentifier
        );


    if (
        owner.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    owner.error
                );
    }


    /*
     * One byte is always required for the mandatory owner terminator.
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
                        SerializationErrorCode
                            .invalidLength,
                        owner.value,
                        1,
                        maximumFrameDataSize -
                            owner.value
                    )
                );
    }


    const ownerAndTerminator =
        owner.value +
        1;


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
                        SerializationErrorCode
                            .invalidLength,
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
Serializes one deterministic ID3v2.3 PRIV semantic payload.

Private binary bytes are copied unchanged and may contain arbitrary
values, including zero bytes.

ID3v2.3 whole-tag unsynchronisation is deliberately not applied here.
That transformation belongs to the later tag-level serializer.

Params:
    ownerIdentifier = Canonical owner identifier.
    privateData = Opaque logical private data.

Returns:
    Owned semantic payload bytes or the validation error reported by
    `measureId3v23PrivatePayload`.
+/
SerializationResult!(ubyte[])
serializeId3v23PrivatePayload(
    string ownerIdentifier,
    const(ubyte)[] privateData
)
    @safe
{
    auto measured =
        measureId3v23PrivatePayload(
            ownerIdentifier,
            privateData
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


    size_t position;


    /*
     * Measurement already proved that every Unicode scalar value maps
     * losslessly to exactly one ISO-8859-1 byte.
     */
    foreach (
        dchar codePoint;
        ownerIdentifier
    )
    {
        output[
            position++
        ] =
            cast(ubyte)
                codePoint;
    }


    output[
        position++
    ] =
        0x00;


    foreach (
        byteValue;
        privateData
    )
    {
        output[
            position++
        ] =
            byteValue;
    }


    assert(
        position ==
        output.length
    );


    return
        SerializationResult!(ubyte[])
            .success(
                output
            );
}


/// A normal PRIV payload preserves owner and opaque binary data exactly.
unittest
{
    const(ubyte)[] privateData =
        [
            0x01,
            0x02,
            0xFE,
            0xFF
        ];


    auto measured =
        measureId3v23PrivatePayload(
            "example.com",
            privateData
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        16
    );


    auto serialized =
        serializeId3v23PrivatePayload(
            "example.com",
            privateData
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value.length ==
        measured.value
    );


    assert(
        serialized.value ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm',

            0x00,

            0x01,
            0x02,
            0xFE,
            0xFF
        ]
    );
}


/// Empty owner and empty private data retain the mandatory terminator.
unittest
{
    auto measured =
        measureId3v23PrivatePayload(
            "",
            []
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        1
    );


    auto serialized =
        serializeId3v23PrivatePayload(
            "",
            []
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00
        ]
    );
}


/// An empty owner remains valid when private data follows.
unittest
{
    auto serialized =
        serializeId3v23PrivatePayload(
            "",
            [
                cast(ubyte)
                    0xAA
            ]
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            0xAA
        ]
    );
}


/// Empty private data is valid after a non-empty owner.
unittest
{
    auto serialized =
        serializeId3v23PrivatePayload(
            "owner",
            []
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            'o', 'w', 'n', 'e', 'r',
            0x00
        ]
    );
}


/// Owner identifiers are serialized as ISO-8859-1 bytes.
unittest
{
    auto serialized =
        serializeId3v23PrivatePayload(
            "caf\u00E9",
            []
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            'c', 'a', 'f',
            0xE9,
            0x00
        ]
    );
}


/// Owner identifiers outside ISO-8859-1 cannot be silently rewritten.
unittest
{
    auto measured =
        measureId3v23PrivatePayload(
            "owner/\u20AC",
            []
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


/// Embedded U+0000 would terminate the owner identifier prematurely.
unittest
{
    auto measured =
        measureId3v23PrivatePayload(
            "owner\0suffix",
            []
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
        measured.error.index ==
        5
    );
}


/// Malformed canonical UTF-8 owner text is rejected.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 'A',
            cast(char) 0xC3
        ];


    auto measured =
        measureId3v23PrivatePayload(
            malformed,
            []
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


/// Private data remains opaque and may contain zero bytes.
unittest
{
    const(ubyte)[] privateData =
        [
            0x00,
            0xFF,
            0x00,
            0x7F
        ];


    auto serialized =
        serializeId3v23PrivatePayload(
            "owner",
            privateData
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            'o', 'w', 'n', 'e', 'r',

            0x00,

            0x00,
            0xFF,
            0x00,
            0x7F
        ]
    );
}


/// Binary bytes resembling unsynchronisation sequences remain logical data.
unittest
{
    const(ubyte)[] privateData =
        [
            0xFF,
            0xE0,
            0xFF
        ];


    auto serialized =
        serializeId3v23PrivatePayload(
            "x",
            privateData
        );


    assert(
        serialized.hasValue
    );


    /*
     * Whole-tag unsynchronisation belongs above this payload serializer.
     */
    assert(
        serialized.value ==
        [
            'x',
            0x00,

            0xFF,
            0xE0,
            0xFF
        ]
    );
}


/// Measurement and serialization remain exactly synchronized.
unittest
{
    const(ubyte)[] privateData =
        [
            0x11,
            0x00,
            0x22,
            0xFF
        ];


    auto measured =
        measureId3v23PrivatePayload(
            "owner",
            privateData
        );


    auto serialized =
        serializeId3v23PrivatePayload(
            "owner",
            privateData
        );


    assert(measured.hasValue);
    assert(serialized.hasValue);

    assert(
        measured.value ==
        serialized.value.length
    );
}
