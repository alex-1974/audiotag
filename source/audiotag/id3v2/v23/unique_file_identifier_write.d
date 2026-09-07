/++
ID3v2.3 unique-file-identifier (`UFID`) payload serialization.

A UFID semantic payload contains:

    <non-empty owner identifier as ISO-8859-1> $00
    <zero to 64 opaque identifier bytes>

The owner terminator is mandatory.

The owner identifier is supplied as canonical UTF-8 text and must be:

- non-empty;
- valid UTF-8;
- losslessly representable as ISO-8859-1;
- free of embedded U+0000.

Identifier data is opaque and may contain arbitrary byte values,
including zero bytes.

The native 64-byte UFID limit applies to the logical identifier bytes
supplied to this serializer.

This module emits logical semantic payload bytes only. It does not emit
a frame header, grouping identity, compression/encryption additions or
ID3v2.3 whole-tag unsynchronisation.
+/
module audiotag.id3v2.v23.unique_file_identifier_write;

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
Native ID3v2.3 UFID identifier-data limit.
+/
private enum size_t maximumIdentifierLength =
    64;


/++
Measures one non-empty UFID owner identifier after lossless conversion
from canonical UTF-8 to native ISO-8859-1.

Params:
    ownerIdentifier = Canonical UFID owner qualifier.

Returns:
    Number of native owner bytes or a structured serialization error.

Error semantics:
    An empty owner or malformed UTF-8 produces `invalidValue`.

    Embedded U+0000 or a Unicode scalar outside ISO-8859-1 produces
    `unsupportedRepresentation`.
+/
private SerializationResult!size_t
measureUniqueFileIdentifierOwner(
    string ownerIdentifier
)
    @safe
{
    if (
        ownerIdentifier.length ==
        0
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        0
                    )
                );
    }


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
Measures and validates one deterministic ID3v2.3 UFID semantic payload.

The returned size includes:

- the non-empty ISO-8859-1 owner identifier;
- its mandatory one-byte null terminator;
- zero to 64 opaque logical identifier bytes.

Params:
    ownerIdentifier = Canonical UFID owner qualifier.
    identifier = Opaque logical identifier bytes.

Returns:
    Required payload length or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23UniqueFileIdentifierPayload(
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
                        SerializationErrorCode
                            .invalidLength,
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
        identifier.length >
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
Serializes one deterministic ID3v2.3 UFID semantic payload.

Identifier bytes are copied unchanged and may contain arbitrary byte
values including zero.

Whole-tag unsynchronisation is deliberately not applied here. It belongs
to the later ID3v2.3 tag-level serializer.

Params:
    ownerIdentifier = Non-empty canonical owner string.
    identifier = Zero to 64 opaque logical identifier bytes.

Returns:
    Owned semantic payload bytes or the validation error reported by
    `measureId3v23UniqueFileIdentifierPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v23UniqueFileIdentifierPayload(
    string ownerIdentifier,
    const(ubyte)[] identifier
)
    @safe
{
    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
            ownerIdentifier,
            identifier
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
     * Measurement established one-byte ISO-8859-1 representability.
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
        identifier
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


/// Normal UFID preserves owner and opaque identifier bytes exactly.
unittest
{
    const(ubyte)[] identifier =
        [
            0x11,
            0x22,
            0xFE,
            0xFF
        ];


    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
            "example.com",
            identifier
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        16
    );


    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
            "example.com",
            identifier
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

            0x11,
            0x22,
            0xFE,
            0xFF
        ]
    );
}


/// Empty identifier data is valid UFID content.
unittest
{
    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
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


/// Empty UFID owner is invalid.
unittest
{
    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
            "",
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
        0
    );
}


/// UFID owner identifiers use ISO-8859-1 bytes.
unittest
{
    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
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


/// Owner characters outside ISO-8859-1 are rejected.
unittest
{
    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
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


/// Embedded NUL cannot silently truncate the UFID owner.
unittest
{
    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
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
        measureId3v23UniqueFileIdentifierPayload(
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


/// Exactly 64 logical identifier bytes remain representable.
unittest
{
    ubyte[64] identifier;


    foreach (
        index;
        0 ..
        identifier.length
    )
    {
        identifier[
            index
        ] =
            cast(ubyte)
                index;
    }


    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );


    assert(
        measured.hasValue
    );


    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );


    assert(
        serialized.hasValue
    );


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


/// A 65-byte logical identifier violates the native UFID limit.
unittest
{
    ubyte[65] identifier;


    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );


    assert(
        measured.hasError
    );


    assert(
        measured.error.code ==
        SerializationErrorCode
            .invalidLength
    );


    assert(
        measured.error.value ==
        65
    );


    assert(
        measured.error.limit ==
        64
    );


    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier[]
        );


    assert(
        serialized.hasError
    );


    assert(
        serialized.error.code ==
        SerializationErrorCode
            .invalidLength
    );
}


/// Opaque UFID bytes may contain zero values.
unittest
{
    const(ubyte)[] identifier =
        [
            0x00,
            0xFF,
            0x00,
            0x7F
        ];


    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier
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


/// Unsynchronisation-like bytes remain logical identifier bytes here.
unittest
{
    const(ubyte)[] identifier =
        [
            0xFF,
            0xE0,
            0xFF
        ];


    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
            "x",
            identifier
        );


    assert(
        serialized.hasValue
    );


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
    const(ubyte)[] identifier =
        [
            0x11,
            0x00,
            0x22,
            0xFF
        ];


    auto measured =
        measureId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier
        );


    auto serialized =
        serializeId3v23UniqueFileIdentifierPayload(
            "owner",
            identifier
        );


    assert(measured.hasValue);
    assert(serialized.hasValue);

    assert(
        measured.value ==
        serialized.value.length
    );
}
