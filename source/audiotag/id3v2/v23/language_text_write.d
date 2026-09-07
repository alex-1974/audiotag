/++
ID3v2.3 language-qualified text payload serialization.

This payload shape is shared by `COMM` and `USLT`:

    <encoding marker>
    <three-byte language>
    <description according to encoding>
    <mandatory encoding-dependent description terminator>
    <text according to encoding>

Description and text share one ID3v2.3 text-encoding marker.

The writer chooses that common encoding deterministically:

- ISO-8859-1 when both strings are losslessly representable there;
- otherwise strict ID3v2.3 UCS-2 with BOM when both are representable;
- otherwise serialization fails.

For UCS-2 every non-empty string is serialized independently and
therefore receives its own BOM. Empty UCS-2 strings contain no BOM.

The three-byte language identifier is written exactly as supplied. New
serialization accepts exactly three ASCII bytes and does not normalize
case or otherwise rewrite the language identifier.

The description terminator is always present:

- one zero byte for ISO-8859-1;
- two zero bytes for UCS-2.

The text occupies the remainder of the bounded semantic payload and
does not receive a trailing terminator.

Embedded U+0000 is rejected in description and text because it would
introduce native string-boundary semantics not represented by the
canonical scalar model.

No frame header, frame-format additions or tag-level
unsynchronisation are emitted here.
+/
module audiotag.id3v2.v23.language_text_write;

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
Validates one native ID3v2.3 language identifier.

The identifier must consist of exactly three ASCII bytes. Case is
preserved and no language-code normalization is performed.

Params:
    language = Native three-byte language identifier.

Returns:
    Success or a structured serialization failure.
+/
private SerializationResult!bool
validateId3v23Language(
    string language
)
    @safe
{
    if (
        language.length !=
        3
    )
    {
        return
            SerializationResult!bool
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        0,
                        language.length,
                        3
                    )
                );
    }


    foreach (
        byteIndex,
        languageCharacter;
        language
    )
    {
        const languageByte =
            cast(ubyte)
                languageCharacter;


        if (
            languageByte >
            0x7F
        )
        {
            return
                SerializationResult!bool
                    .failure(
                        SerializationError(
                            SerializationErrorCode
                                .unsupportedRepresentation,
                            byteIndex,
                            languageByte,
                            0x7F
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
Validates the two canonical text strings used by COMM/USLT.

Malformed UTF-8 and embedded U+0000 are rejected before native
representation is selected.

Params:
    description = Content description or descriptor.
    text = Comment, lyrics or other language-qualified text.

Returns:
    Success or the first canonical-text validation failure.
+/
private SerializationResult!bool
validateId3v23LanguageTextStrings(
    string description,
    string text
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


    const textValid =
        validLength(
            text
        );


    if (
        textValid !=
        text.length
    )
    {
        return
            SerializationResult!bool
                .failure(
                    SerializationError(
                        SerializationErrorCode
                            .invalidValue,
                        textValid
                    )
                );
    }


    foreach (
        byteIndex,
        textByte;
        text
    )
    {
        if (
            textByte ==
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
Measures and validates one deterministic ID3v2.3 language-text payload.

The returned size includes:

- one encoding-marker byte;
- exactly three language bytes;
- encoded description bytes;
- the mandatory encoding-dependent description terminator;
- encoded text bytes.

The text receives no trailing terminator.

Params:
    language = Native three-byte language identifier.
    description = Content description or descriptor.
    text = Comment, lyrics or other language-qualified text.

Returns:
    Complete semantic payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v23LanguageTextPayload(
    string language,
    string description,
    string text
)
    @safe
{
    auto languageValid =
        validateId3v23Language(
            language
        );


    if (
        languageValid.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    languageValid.error
                );
    }


    auto stringsValid =
        validateId3v23LanguageTextStrings(
            description,
            text
        );


    if (
        stringsValid.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    stringsValid.error
                );
    }


    const(string)[] values =
        [
            description,
            text
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


    auto textSize =
        measureId3v23EncodedText(
            text,
            encoding
        );


    if (
        textSize.hasError
    )
    {
        return
            SerializationResult!size_t
                .failure(
                    textSize.error
                );
    }


    /*
     * Encoding marker + three native language bytes.
     */
    size_t total =
        4;


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
        textSize.value >
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
                                textSize.value,
                        maximumFrameDataSize
                    )
                );
    }


    total +=
        textSize.value;


    return
        SerializationResult!size_t
            .success(
                total
            );
}


/++
Serializes one canonical language/description/text tuple as deterministic
ID3v2.3 semantic frame data.

The output is either:

    $00 <language> <Latin-1 description> $00 <Latin-1 text>

or:

    $01 <language>
        <UCS-2 description with own BOM when non-empty>
        $00 $00
        <UCS-2 text with own BOM when non-empty>

Both non-empty UCS-2 strings use the deterministic big-endian BOM
emitted by `serializeId3v23EncodedText`.

Params:
    language = Native three-byte language identifier.
    description = Content description or descriptor.
    text = Language-qualified scalar text.

Returns:
    Owned semantic payload bytes or the validation error reported by
    `measureId3v23LanguageTextPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v23LanguageTextPayload(
    string language,
    string description,
    string text
)
    @safe
{
    auto measured =
        measureId3v23LanguageTextPayload(
            language,
            description,
            text
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
            text
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


    auto encodedText =
        serializeId3v23EncodedText(
            text,
            encoding
        );


    assert(
        encodedText.hasValue
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


    /*
     * The language field is independent of the text encoding.
     */
    foreach (
        languageCharacter;
        language
    )
    {
        output[
            position++
        ] =
            cast(ubyte)
                languageCharacter;
    }


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
     * COMM and USLT always require the description/descriptor
     * terminator.
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
        encodedText.value.length !=
        0
    )
    {
        output[
            position ..
            position +
                encodedText.value.length
        ] =
            encodedText.value[];


        position +=
            encodedText.value.length;
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


/// Normal COMM/USLT-compatible text uses compact Latin-1.
unittest
{
    auto measured =
        measureId3v23LanguageTextPayload(
            "eng",
            "note",
            "hello\nworld"
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        20
    );


    auto serialized =
        serializeId3v23LanguageTextPayload(
            "eng",
            "note",
            "hello\nworld"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x00,

            'e', 'n', 'g',

            'n', 'o', 't', 'e',
            0x00,

            'h', 'e', 'l', 'l', 'o',
            0x0A,
            'w', 'o', 'r', 'l', 'd'
        ]
    );
}


/// Empty description and text retain the mandatory separator.
unittest
{
    auto measured =
        measureId3v23LanguageTextPayload(
            "deu",
            "",
            ""
        );


    assert(
        measured.hasValue
    );

    assert(
        measured.value ==
        5
    );


    auto serialized =
        serializeId3v23LanguageTextPayload(
            "deu",
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
            'd', 'e', 'u',
            0x00
        ]
    );
}


/// Latin-1 non-ASCII description and text remain on marker $00.
unittest
{
    auto serialized =
        serializeId3v23LanguageTextPayload(
            "deu",
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

            'd', 'e', 'u',

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


/// Wider BMP description and text share UCS-2 but receive separate BOMs.
unittest
{
    auto serialized =
        serializeId3v23LanguageTextPayload(
            "eng",
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

            'e', 'n', 'g',

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
             * Text Ж with its own big-endian BOM.
             */
            0xFE, 0xFF,
            0x04, 0x16
        ]
    );
}


/// Wider text promotes an ASCII description to the common UCS-2 marker.
unittest
{
    auto serialized =
        serializeId3v23LanguageTextPayload(
            "eng",
            "note",
            "\u03A9"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value ==
        [
            0x01,

            'e', 'n', 'g',

            0xFE, 0xFF,
            0x00, 0x6E,
            0x00, 0x6F,
            0x00, 0x74,
            0x00, 0x65,

            0x00, 0x00,

            0xFE, 0xFF,
            0x03, 0xA9
        ]
    );
}


/// Empty UCS-2 description has no BOM, only the mandatory terminator.
unittest
{
    auto serialized =
        serializeId3v23LanguageTextPayload(
            "eng",
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

            'e', 'n', 'g',

            0x00, 0x00,

            0xFE, 0xFF,
            0x03, 0xA9
        ]
    );
}


/// Empty UCS-2 text emits neither a BOM nor a trailing terminator.
unittest
{
    auto serialized =
        serializeId3v23LanguageTextPayload(
            "eng",
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

            'e', 'n', 'g',

            0xFE, 0xFF,
            0x03, 0xA9,

            0x00, 0x00
        ]
    );
}


/// Exactly three language bytes are required.
unittest
{
    auto shortResult =
        measureId3v23LanguageTextPayload(
            "en",
            "",
            ""
        );


    assert(
        shortResult.hasError
    );

    assert(
        shortResult.error.code ==
        SerializationErrorCode
            .invalidValue
    );


    auto longResult =
        measureId3v23LanguageTextPayload(
            "engl",
            "",
            ""
        );


    assert(
        longResult.hasError
    );

    assert(
        longResult.error.code ==
        SerializationErrorCode
            .invalidValue
    );
}


/// Language bytes must remain inside the native ASCII domain.
unittest
{
    const invalidLanguage =
        cast(string)
            [
                cast(char) 0xE4,
                cast(char) 'n',
                cast(char) 'g'
            ];


    auto measured =
        measureId3v23LanguageTextPayload(
            invalidLanguage,
            "",
            ""
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
        0xE4
    );


    assert(
        measured.error.limit ==
        0x7F
    );
}


/// Language spelling and case are preserved exactly.
unittest
{
    auto serialized =
        serializeId3v23LanguageTextPayload(
            "ENG",
            "",
            "text"
        );


    assert(
        serialized.hasValue
    );


    assert(
        serialized.value[
            1 ..
            4
        ] ==
        cast(const(ubyte)[])
            "ENG"
    );
}


/// Embedded NUL cannot terminate the description early.
unittest
{
    auto measured =
        measureId3v23LanguageTextPayload(
            "eng",
            "a\0b",
            "text"
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


/// Embedded NUL remains unsupported in the scalar text body.
unittest
{
    auto measured =
        measureId3v23LanguageTextPayload(
            "eng",
            "desc",
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


/// Supplementary Unicode is outside strict ID3v2.3 UCS-2.
unittest
{
    auto measured =
        measureId3v23LanguageTextPayload(
            "eng",
            "",
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


/// Malformed UTF-8 description is rejected structurally.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 0xC3,
                cast(char) 0x28
            ];


    auto measured =
        measureId3v23LanguageTextPayload(
            "eng",
            malformed,
            "text"
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


/// Malformed UTF-8 text is rejected structurally.
unittest
{
    const malformed =
        cast(string)
            [
                cast(char) 'A',
                cast(char) 0xC3
            ];


    auto measured =
        measureId3v23LanguageTextPayload(
            "eng",
            "desc",
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
        measureId3v23LanguageTextPayload(
            "eng",
            "note",
            "hello"
        );


    auto latinSerialized =
        serializeId3v23LanguageTextPayload(
            "eng",
            "note",
            "hello"
        );


    assert(latinMeasured.hasValue);
    assert(latinSerialized.hasValue);

    assert(
        latinMeasured.value ==
        latinSerialized.value.length
    );


    auto unicodeMeasured =
        measureId3v23LanguageTextPayload(
            "deu",
            "",
            "\u03A9"
        );


    auto unicodeSerialized =
        serializeId3v23LanguageTextPayload(
            "deu",
            "",
            "\u03A9"
        );


    assert(unicodeMeasured.hasValue);
    assert(unicodeSerialized.hasValue);

    assert(
        unicodeMeasured.value ==
        unicodeSerialized.value.length
    );
}
