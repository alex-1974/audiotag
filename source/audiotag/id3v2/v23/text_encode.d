/++
ID3v2.3 encoded-text serialization primitives.

This module converts canonical UTF-8 D strings to one explicitly
selected native ID3v2.3 text encoding.

Supported native encodings are exactly those defined by ID3v2.3:

- ISO-8859-1 (`$00`);
- 16-bit Unicode / UCS-2 with BOM (`$01`).

ID3v2.3 does not define UTF-8 or UTF-16BE-without-BOM text markers.

Deterministic Unicode representation:

- empty UCS-2 text occupies zero bytes;
- every non-empty UCS-2 string begins with the big-endian BOM
  `FE FF`;
- every Unicode scalar is then emitted as one big-endian UCS-2 code
  unit;
- values outside the UCS-2 domain are rejected rather than encoded as
  surrogate pairs.

This module serializes one encoded text string only. It does not emit:

- an ID3 text-encoding marker;
- a string terminator;
- frame headers;
- frame-format additions;
- tag-level unsynchronisation.

Embedded U+0000 is therefore representable here. Payload codecs whose
native structure uses zero terminators must separately reject values
where U+0000 would alter the intended field boundary.
+/
module audiotag.id3v2.v23.text_encode;

import std.encoding :
    validLength;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding;


/++
Maximum byte count one encoded text region could contribute to a single
ID3v2.3 frame.

The complete frame payload may require additional marker, terminator or
structural bytes, so higher writer layers must still validate their
complete payload size.
+/
private enum size_t maximumEncodedTextSize =
    uint.max;


/++
Measures one UTF-8 string after conversion to an explicitly selected
ID3v2.3 text encoding.

For Latin-1, every Unicode scalar contributes one byte.

For UCS-2:

- an empty string contributes zero bytes;
- a non-empty string contributes a two-byte big-endian BOM plus two
  bytes per Unicode scalar.

Supplementary Unicode values are not representable because the strict
ID3v2.3 reader treats `$01` as UCS-2 rather than modern UTF-16.

Params:
    value = Canonical UTF-8 text.
    encoding = Native ID3v2.3 encoding to use.

Returns:
    Encoded text byte count, excluding encoding marker and terminator,
    or a structured serialization failure.

Error semantics:
    `SerializationError.index` identifies the UTF-8 code-unit offset
    at which invalid or unrepresentable input begins.
+/
SerializationResult!size_t
measureId3v23EncodedText(
    string value,
    Id3v23TextEncoding encoding
)
    @safe
{
    const valid =
        validLength(
            value
        );


    if (
        valid !=
        value.length
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


    switch (
        encoding
    )
    {
        case Id3v23TextEncoding.latin1:
        {
            size_t encodedLength;


            foreach (
                byteIndex,
                dchar codePoint;
                value
            )
            {
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


                if (
                    encodedLength ==
                    maximumEncodedTextSize
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
                                    maximumEncodedTextSize
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


        case Id3v23TextEncoding.utf16:
        {
            if (
                value.length ==
                0
            )
            {
                return
                    SerializationResult!size_t
                        .success(
                            0
                        );
            }


            /*
             * Every non-empty UCS-2 string begins with its own BOM.
             */
            size_t encodedLength =
                2;


            foreach (
                byteIndex,
                dchar codePoint;
                value
            )
            {
                /*
                 * ID3v2.3 specifies UCS-2 for marker $01. Do not silently
                 * upgrade supplementary characters to UTF-16 surrogate
                 * pairs.
                 */
                if (
                    codePoint >
                    0xFFFF
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
                                    0xFFFF
                                )
                            );
                }


                /*
                 * `validLength` has already rejected invalid Unicode,
                 * including surrogate scalar encodings. This explicit
                 * check documents the native UCS-2 invariant defensively.
                 */
                if (
                    codePoint >= 0xD800 &&
                    codePoint <= 0xDFFF
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
                                    0xFFFF
                                )
                            );
                }


                if (
                    encodedLength >
                    maximumEncodedTextSize -
                    2
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
                                        2,
                                    maximumEncodedTextSize
                                )
                            );
                }


                encodedLength +=
                    2;
            }


            return
                SerializationResult!size_t
                    .success(
                        encodedLength
                    );
        }


        default:
        {
            return
                SerializationResult!size_t
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .invalidValue,
                            0,
                            cast(ubyte)
                                encoding
                        )
                    );
        }
    }
}


/++
Serializes one UTF-8 string in an explicitly selected ID3v2.3 text
encoding.

Latin-1 produces one native byte per Unicode scalar.

Non-empty UCS-2 is emitted deterministically as:

    FE FF <big-endian UCS-2 code units>

An empty UCS-2 string emits no bytes. A surrounding payload codec may
still append its required two-byte terminator.

Params:
    value = Canonical UTF-8 text.
    encoding = Native ID3v2.3 encoding to use.

Returns:
    Owned encoded text bytes or the validation error reported by
    `measureId3v23EncodedText`.
+/
SerializationResult!(ubyte[])
serializeId3v23EncodedText(
    string value,
    Id3v23TextEncoding encoding
)
    @safe
{
    auto measured =
        measureId3v23EncodedText(
            value,
            encoding
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


    switch (
        encoding
    )
    {
        case Id3v23TextEncoding.latin1:
        {
            size_t position;


            foreach (
                dchar codePoint;
                value
            )
            {
                assert(
                    codePoint <=
                    0xFF
                );


                output[
                    position++
                ] =
                    cast(ubyte)
                        codePoint;
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


        case Id3v23TextEncoding.utf16:
        {
            if (
                value.length ==
                0
            )
            {
                assert(
                    output.length ==
                    0
                );


                return
                    SerializationResult!(ubyte[])
                        .success(
                            output
                        );
            }


            assert(
                output.length >=
                2
            );


            /*
             * Deterministic writer byte order.
             */
            output[0] = 0xFE;
            output[1] = 0xFF;


            size_t position =
                2;


            foreach (
                dchar codePoint;
                value
            )
            {
                assert(
                    codePoint <=
                    0xFFFF
                );

                assert(
                    codePoint < 0xD800 ||
                    codePoint > 0xDFFF
                );


                const unit =
                    cast(ushort)
                        codePoint;


                output[
                    position++
                ] =
                    cast(ubyte)
                    (
                        unit >>
                        8
                    );


                output[
                    position++
                ] =
                    cast(ubyte)
                    (
                        unit &
                        0xFF
                    );
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


        default:
        {
            /*
             * Measurement already rejected an invalid enum value.
             */
            assert(0);
        }
    }
}


/// Latin-1 text produces exactly one byte per scalar.
unittest
{
    auto measured =
        measureId3v23EncodedText(
            "A\u00E9\u00FF",
            Id3v23TextEncoding.latin1
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        3
    );


    auto serialized =
        serializeId3v23EncodedText(
            "A\u00E9\u00FF",
            Id3v23TextEncoding.latin1
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x41,
            0xE9,
            0xFF
        ]
    );
}


/// Latin-1 cannot silently approximate wider Unicode.
unittest
{
    auto measured =
        measureId3v23EncodedText(
            "\u03A9",
            Id3v23TextEncoding.latin1
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
        0
    );


    assert(
        measured.error.value ==
        0x03A9
    );


    assert(
        measured.error.limit ==
        0xFF
    );
}


/// Non-empty UCS-2 uses a deterministic big-endian BOM.
unittest
{
    auto measured =
        measureId3v23EncodedText(
            "A\u03A9",
            Id3v23TextEncoding.utf16
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        6
    );


    auto serialized =
        serializeId3v23EncodedText(
            "A\u03A9",
            Id3v23TextEncoding.utf16
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0xFE, 0xFF,
            0x00, 0x41,
            0x03, 0xA9
        ]
    );
}


/// An empty UCS-2 text region needs no BOM.
unittest
{
    auto measured =
        measureId3v23EncodedText(
            "",
            Id3v23TextEncoding.utf16
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        0
    );


    auto serialized =
        serializeId3v23EncodedText(
            "",
            Id3v23TextEncoding.utf16
        );


    assert(
        serialized.hasValue
    );

    assert(
        serialized.value.length ==
        0
    );
}


/// Separate non-empty UCS-2 strings each receive their own BOM.
unittest
{
    auto first =
        serializeId3v23EncodedText(
            "A",
            Id3v23TextEncoding.utf16
        );


    auto second =
        serializeId3v23EncodedText(
            "B",
            Id3v23TextEncoding.utf16
        );


    assert(first.hasValue);
    assert(second.hasValue);


    assert(
        first.value ==
        [
            0xFE, 0xFF,
            0x00, 0x41
        ]
    );


    assert(
        second.value ==
        [
            0xFE, 0xFF,
            0x00, 0x42
        ]
    );
}


/// Supplementary Unicode is outside strict ID3v2.3 UCS-2.
unittest
{
    auto measured =
        measureId3v23EncodedText(
            "\U0001F600",
            Id3v23TextEncoding.utf16
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


/// Malformed UTF-8 is rejected before native encoding.
unittest
{
    const invalid =
        cast(string)
            [
                cast(char) 'A',
                cast(char) 0xC3
            ];


    auto measured =
        measureId3v23EncodedText(
            invalid,
            Id3v23TextEncoding.utf16
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


/// U+0000 is an encoded-text value here, not a delimiter policy.
unittest
{
    auto latin1 =
        serializeId3v23EncodedText(
            "A\0B",
            Id3v23TextEncoding.latin1
        );


    assert(
        latin1.hasValue
    );


    assert(
        latin1.value ==
        [
            0x41,
            0x00,
            0x42
        ]
    );


    auto unicode =
        serializeId3v23EncodedText(
            "A\0B",
            Id3v23TextEncoding.utf16
        );


    assert(
        unicode.hasValue
    );


    assert(
        unicode.value ==
        [
            0xFE, 0xFF,
            0x00, 0x41,
            0x00, 0x00,
            0x00, 0x42
        ]
    );
}


/// An invalid encoding enum produces a writer error, not an assertion.
unittest
{
    auto measured =
        measureId3v23EncodedText(
            "A",
            cast(Id3v23TextEncoding)
                0x7F
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
