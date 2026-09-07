/++
Deterministic ID3v2.3 text-encoding selection for newly serialized text.

ID3v2.3 offers only two selectable text encodings:

- ISO-8859-1 (`$00`);
- 16-bit Unicode / UCS-2 with BOM (`$01`).

The writer uses the following deterministic preference:

1. choose ISO-8859-1 when every participating string is losslessly
   representable in Latin-1;
2. otherwise choose UCS-2 when every participating string is losslessly
   representable there;
3. otherwise reject the representation.

This is a writer policy rather than a property of the ID3v2.3 format
itself. Preferring Latin-1 keeps ASCII and Latin-1 metadata compact and
avoids unnecessary Unicode encoding, while UCS-2 provides the wider
representation available in ID3v2.3.

One frame may contain multiple text strings controlled by a single
encoding marker. Therefore selection operates over a set of strings,
not merely one value. Examples include TXXX, WXXX, COMM and USLT.

This module considers character-encoding representability only.

It deliberately does not enforce:

- string-terminator restrictions such as embedded U+0000;
- frame-specific separators;
- TPE1 slash-list semantics;
- complete frame-payload size;
- frame headers;
- tag-level unsynchronisation.

Those constraints belong to the corresponding payload or frame writer.
+/
module audiotag.id3v2.v23.text_encoding_policy;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v2.v23.text_encode :
    measureId3v23EncodedText;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding;


/++
Chooses one lossless native ID3v2.3 encoding for all supplied strings.

At least one logical string must participate in the choice. Individual
strings may themselves be empty.

Latin-1 is preferred whenever every value can be represented by it.
Otherwise every value is tested against strict ID3v2.3 UCS-2.

Params:
    values = Canonical UTF-8 strings controlled by one native encoding
        marker.

Returns:
    Selected native encoding or the first structured serialization
    failure encountered while establishing the wider UCS-2
    representation.

Notes:
    Embedded U+0000 remains representable at this layer. A later payload
    codec must reject it wherever it would become a native delimiter.
+/
SerializationResult!Id3v23TextEncoding
chooseId3v23TextEncoding(
    const(string)[] values
)
    @safe
{
    if (
        values.length ==
        0
    )
    {
        return
            SerializationResult!Id3v23TextEncoding
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        0
                    )
                );
    }


    bool allLatin1 =
        true;


    foreach (
        value;
        values
    )
    {
        auto measured =
            measureId3v23EncodedText(
                value,
                Id3v23TextEncoding.latin1
            );


        if (
            measured.hasError
        )
        {
            /*
             * Malformed UTF-8 cannot become valid by selecting UCS-2.
             */
            if (
                measured.error.code ==
                SerializationErrorCode.invalidValue
            )
            {
                return
                    SerializationResult!Id3v23TextEncoding
                        .failure(
                            measured.error
                        );
            }


            /*
             * A value already exceeding the v2.3 frame-size domain in
             * one-byte Latin-1 cannot become smaller in UCS-2.
             */
            if (
                measured.error.code ==
                SerializationErrorCode.valueOutOfRange
            )
            {
                return
                    SerializationResult!Id3v23TextEncoding
                        .failure(
                            measured.error
                        );
            }


            allLatin1 =
                false;

            break;
        }
    }


    if (
        allLatin1
    )
    {
        return
            SerializationResult!Id3v23TextEncoding
                .success(
                    Id3v23TextEncoding.latin1
                );
    }


    /*
     * At least one value needs wider character representation.
     *
     * Validate every participating string under strict ID3v2.3 UCS-2.
     * `measureId3v23EncodedText` rejects supplementary Unicode rather
     * than silently generating UTF-16 surrogate pairs.
     */
    foreach (
        value;
        values
    )
    {
        auto measured =
            measureId3v23EncodedText(
                value,
                Id3v23TextEncoding.utf16
            );


        if (
            measured.hasError
        )
        {
            return
                SerializationResult!Id3v23TextEncoding
                    .failure(
                        measured.error
                    );
        }
    }


    return
        SerializationResult!Id3v23TextEncoding
            .success(
                Id3v23TextEncoding.utf16
            );
}


/// Plain ASCII prefers the compact Latin-1 representation.
unittest
{
    const(string)[] values =
        [
            "Title"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.latin1
    );
}


/// The complete Latin-1 character range remains on encoding $00.
unittest
{
    const(string)[] values =
        [
            "Gr\u00F6\u00DFe",
            "\u00FF"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.latin1
    );
}


/// One wider BMP value promotes the complete native frame to UCS-2.
unittest
{
    const(string)[] values =
        [
            "ASCII",
            "\u03A9"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.utf16
    );
}


/// Multiple BMP strings share one UCS-2 encoding decision.
unittest
{
    const(string)[] values =
        [
            "\u03A9",
            "value",
            "\u0416"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.utf16
    );
}


/// Empty strings are valid participants and do not force Unicode.
unittest
{
    const(string)[] values =
        [
            "",
            ""
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.latin1
    );
}


/// An empty set has no meaningful native encoding decision.
unittest
{
    const(string)[] values = [];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );
}


/// Supplementary Unicode cannot be represented by strict v2.3 UCS-2.
unittest
{
    const(string)[] values =
        [
            "prefix",
            "\U0001F600"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );


    assert(
        result.error.value ==
        0x1F600
    );


    assert(
        result.error.limit ==
        0xFFFF
    );
}


/// Malformed UTF-8 is rejected rather than treated as an encoding choice.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 'A',
                cast(char) 0xC3
            ];


    const(string)[] values =
        [
            malformed
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );


    assert(
        result.error.index ==
        1
    );
}


/// Embedded NUL is still an encoding-representable scalar at this layer.
unittest
{
    const(string)[] values =
        [
            "A\0B"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.latin1
    );
}


/// A wider value promotes even empty companion strings to one UCS-2 marker.
unittest
{
    const(string)[] values =
        [
            "",
            "\u03A9"
        ];


    auto result =
        chooseId3v23TextEncoding(
            values
        );


    assert(
        result.hasValue
    );


    assert(
        result.value ==
        Id3v23TextEncoding.utf16
    );
}
