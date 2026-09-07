/++
ID3v2.3 user-defined text (`TXXX`) payload serialization.

One native TXXX semantic payload consists of:

    <encoding marker>
    <description according to encoding>
    <mandatory encoding-dependent terminator>
    <value according to encoding>

Description and value share one ID3v2.3 text-encoding marker.

The writer chooses that common encoding deterministically:

- ISO-8859-1 when both strings are losslessly representable there;
- otherwise strict ID3v2.3 UCS-2 with BOM when both are representable;
- otherwise serialization fails.

For UCS-2 every non-empty string is serialized independently and
therefore receives its own BOM. Empty UCS-2 strings contain no BOM.

The description terminator is always present:

- one zero byte for ISO-8859-1;
- two zero bytes for UCS-2.

The value occupies the remainder of the bounded semantic payload and
does not receive a trailing terminator.

Embedded U+0000 is rejected in both canonical strings. Although the
lower encoded-text primitive can represent it, allowing it here would
introduce native zero-sequence semantics that do not correspond to the
current single-description/single-value canonical shape.

No frame header, frame-format additions or tag-level
unsynchronisation are emitted here.
+/
module audiotag.id3v2.v23.user_text_write;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.text_encode :
    measureId3v23EncodedText,
    serializeId3v23EncodedText;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding,
    terminatorWidth;

import audiotag.id3v2.v23.text_encoding_policy :
    chooseId3v23TextEncoding;


/++
Maximum semantic frame-data size representable by the ordinary unsigned
32-bit ID3v2.3 frame-size field.
+/
private enum size_t maximumFrameDataSize =
    uint.max;


/++
Validates the canonical UTF-8 structure of one TXXX description/value
pair before native encoding selection.

This validation is intentionally payload-specific:

- malformed UTF-8 is rejected;
- embedded U+0000 is rejected because it would introduce native
  delimiter semantics.

Character-set representability is handled separately by the shared
ID3v2.3 encoding policy.

Params:
    description = User-defined TXXX description.
    value = Scalar user-defined text value.

Returns:
    Success or the first structural canonical-text error.
+/
private SerializationResult!bool
validateId3v23UserTextStrings(
    string description,
    string value
)
    @safe
{
    const descriptionValid =
        validLength(
            description
        );


    if (
        descriptionValid !=
        description.length
    )
    {
        return
            SerializationResult!bool
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        descriptionValid
                    )
                );
    }


    foreach (
        byteIndex,
        descriptionByte;
        description
    )
    {
        if (
            descriptionByte ==
            '\0'
        )
        {
            return
                SerializationResult!bool
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            byteIndex,
                            0
                        )
                    );
        }
    }


    const valueValid =
        validLength(
            value
        );


    if (
        valueValid !=
        value.length
    )
    {
        return
            SerializationResult!bool
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        valueValid
                    )
                );
    }


    foreach (
        byteIndex,
        valueByte;
        value
    )
    {
        if (
            valueByte ==
            '\0'
        )
        {
            return
                SerializationResult!bool
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            byteIndex,
                            0
                        )
                    );
        }
    }


    return
        SerializationResult!bool
            .success(
                true
            );
}


/++
Measures and validates one deterministic ID3v2.3 TXXX semantic payload.

The returned size includes:

- one encoding-marker byte;
- encoded description bytes;
- the mandatory encoding-dependent description terminator;
- encoded value bytes.

The value receives no trailing terminator.

Params:
    description = User-defined TXXX description.
    value = Scalar user-defined text value.

Returns:
    Complete semantic payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23UserTextPayload(
    string description,
    string value
)
    @safe
{
    auto valid =
        validateId3v23UserTextStrings(
            description,
            value
        );


    if (
        valid.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    valid.error
                );
    }


    const(string)[] values =
        [
            description,
            value
        ];


    auto encodingResult =
        chooseId3v23TextEncoding(
            values
        );


    if (
        encodingResult.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    encodingResult.error
                );
    }


    const encoding =
        encodingResult.value;


    auto descriptionSize =
        measureId3v23EncodedText(
            description,
            encoding
        );


    if (
        descriptionSize.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    descriptionSize.error
                );
    }


    auto valueSize =
        measureId3v23EncodedText(
            value,
            encoding
        );


    if (
        valueSize.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    valueSize.error
                );
    }


    size_t total =
        1; // Encoding marker.


    if (
        descriptionSize.value >
        maximumFrameDataSize -
        total
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        cast(ulong)
                            total +
                            cast(ulong)
                                descriptionSize.value,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        descriptionSize.value;


    const terminatorSize =
        cast(size_t)
            terminatorWidth(
                encoding
            );


    if (
        terminatorSize >
        maximumFrameDataSize -
        total
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        cast(ulong)
                            total +
                            cast(ulong)
                                terminatorSize,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        terminatorSize;


    if (
        valueSize.value >
        maximumFrameDataSize -
        total
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .valueOutOfRange,
                        0,
                        cast(ulong)
                            total +
                            cast(ulong)
                                valueSize.value,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        valueSize.value;


    return
        SerializationResult!size_t
            .success(
                total
            );
}


/++
Serializes one canonical TXXX description/value pair as deterministic
ID3v2.3 semantic frame data.

The output layout is:

    $00 <Latin-1 description> $00 <Latin-1 value>

or:

    $01 <UCS-2 description with own BOM when non-empty>
        $00 $00
        <UCS-2 value with own BOM when non-empty>

Both Unicode strings use the deterministic big-endian BOM emitted by
`serializeId3v23EncodedText`.

Params:
    description = User-defined TXXX description.
    value = Scalar user-defined text value.

Returns:
    Owned semantic payload bytes or the validation error reported by
    `measureId3v23UserTextPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v23UserTextPayload(
    string description,
    string value
)
    @safe
{
    auto measured =
        measureId3v23UserTextPayload(
            description,
            value
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


    const(string)[] values =
        [
            description,
            value
        ];


    auto encodingResult =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        encodingResult.hasValue
    );


    const encoding =
        encodingResult.value;


    auto encodedDescription =
        serializeId3v23EncodedText(
            description,
            encoding
        );


    assert(
        encodedDescription.hasValue
    );


    auto encodedValue =
        serializeId3v23EncodedText(
            value,
            encoding
        );


    assert(
        encodedValue.hasValue
    );


    auto output =
        new ubyte[
            measured.value
        ];


    size_t position;


    output[
        position++
    ] =
        cast(ubyte)
            encoding;


    if (
        encodedDescription.value.length !=
        0
    )
    {
        output[
            position ..
            position +
                encodedDescription.value.length
        ] =
            encodedDescription.value[];


        position +=
            encodedDescription.value.length;
    }


    /*
     * TXXX requires the description terminator even when the description
     * itself is empty.
     */
    foreach (
        ignored;
        0 ..
        terminatorWidth(
            encoding
        )
    )
    {
        output[
            position++
        ] =
            0;
    }


    if (
        encodedValue.value.length !=
        0
    )
    {
        output[
            position ..
            position +
                encodedValue.value.length
        ] =
            encodedValue.value[];


        position +=
            encodedValue.value.length;
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


/// Ordinary ASCII TXXX data uses compact Latin-1.
unittest
{
    auto measured =
        measureId3v23UserTextPayload(
            "key",
            "value"
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        10
    );


    auto serialized =
        serializeId3v23UserTextPayload(
            "key",
            "value"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'k', 'e', 'y',
            0x00,

            'v', 'a', 'l', 'u', 'e'
        ]
    );
}


/// Latin-1 non-ASCII text remains on encoding marker $00.
unittest
{
    auto serialized =
        serializeId3v23UserTextPayload(
            "Gr\u00F6\u00DFe",
            "Gr\u00FC\u00DFe"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'G', 'r',
            0xF6,
            0xDF,
            'e',

            0x00,

            'G', 'r',
            0xFC,
            0xDF,
            'e'
        ]
    );
}


/// Empty description and value retain the mandatory Latin-1 separator.
unittest
{
    auto measured =
        measureId3v23UserTextPayload(
            "",
            ""
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        2
    );


    auto serialized =
        serializeId3v23UserTextPayload(
            "",
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,
            0x00
        ]
    );
}


/// Wider BMP text promotes both TXXX strings to UCS-2.
unittest
{
    auto serialized =
        serializeId3v23UserTextPayload(
            "\u03A9",
            "\u0416"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            /*
             * Description Ω with its own big-endian BOM.
             */
            0xFE, 0xFF,
            0x03, 0xA9,

            /*
             * Mandatory UCS-2 description terminator.
             */
            0x00, 0x00,

            /*
             * Value Ж with its own big-endian BOM.
             */
            0xFE, 0xFF,
            0x04, 0x16
        ]
    );
}


/// One wider value promotes an ASCII description to UCS-2 as well.
unittest
{
    auto serialized =
        serializeId3v23UserTextPayload(
            "A",
            "\u03A9"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            /*
             * The shared marker is UCS-2, so non-empty ASCII description
             * also receives its own BOM.
             */
            0xFE, 0xFF,
            0x00, 0x41,

            0x00, 0x00,

            0xFE, 0xFF,
            0x03, 0xA9
        ]
    );
}


/// Empty Unicode description emits no BOM, only its mandatory terminator.
unittest
{
    auto serialized =
        serializeId3v23UserTextPayload(
            "",
            "\u03A9"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            /*
             * Empty description has no BOM.
             */
            0x00, 0x00,

            /*
             * Non-empty value has its own BOM.
             */
            0xFE, 0xFF,
            0x03, 0xA9
        ]
    );
}


/// Empty Unicode value emits neither a BOM nor a trailing terminator.
unittest
{
    auto serialized =
        serializeId3v23UserTextPayload(
            "\u03A9",
            ""
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00
        ]
    );
}


/// Embedded NUL in the description would alter native field boundaries.
unittest
{
    auto measured =
        measureId3v23UserTextPayload(
            "a\0b",
            "value"
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
        1
    );
}


/// Embedded NUL in the scalar value remains conservatively unsupported.
unittest
{
    auto measured =
        measureId3v23UserTextPayload(
            "key",
            "a\0b"
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
        1
    );
}


/// Supplementary Unicode cannot be represented by strict ID3v2.3 UCS-2.
unittest
{
    auto measured =
        measureId3v23UserTextPayload(
            "key",
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


    assert(
        measured.error.limit ==
        0xFFFF
    );
}


/// Malformed UTF-8 description is rejected before native serialization.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 0xC3,
                cast(char) 0x28
            ];


    auto measured =
        measureId3v23UserTextPayload(
            malformed,
            "value"
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


/// Malformed UTF-8 value is rejected before native serialization.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 'A',
                cast(char) 0xC3
            ];


    auto measured =
        measureId3v23UserTextPayload(
            "key",
            malformed
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


/// Measurement and serialization remain exactly synchronized.
unittest
{
    auto latinMeasured =
        measureId3v23UserTextPayload(
            "MusicBrainz Album Id",
            "abc-123"
        );


    auto latinSerialized =
        serializeId3v23UserTextPayload(
            "MusicBrainz Album Id",
            "abc-123"
        );


    assert(latinMeasured.hasValue);
    assert(latinSerialized.hasValue);

    assert(
        latinMeasured.value ==
        latinSerialized.value.length
    );


    auto unicodeMeasured =
        measureId3v23UserTextPayload(
            "A",
            "\u03A9"
        );


    auto unicodeSerialized =
        serializeId3v23UserTextPayload(
            "A",
            "\u03A9"
        );


    assert(unicodeMeasured.hasValue);
    assert(unicodeSerialized.hasValue);

    assert(
        unicodeMeasured.value ==
        unicodeSerialized.value.length
    );
}
