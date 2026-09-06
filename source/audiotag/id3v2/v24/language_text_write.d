/++
ID3v2.4 language-qualified text payload serialization.

This payload shape is shared by frames such as `COMM` and `USLT`:

    $03 <3-byte language> <description UTF-8> $00 <text UTF-8>

Regenerated and newly created language-text frames use UTF-8
deterministically.

The language field is written as exactly three native bytes. The
description terminator is mandatory even when the description is empty.
The text occupies the remainder of the frame payload and therefore
receives no trailing terminator.

The canonical model stores description and text as UTF-8. Embedded
U+0000 is rejected in both strings so that it cannot introduce
ambiguous native separator semantics.

No frame header or frame-format transformation is emitted here.
+/
module audiotag.id3v2.v24.language_text_write;

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
Measures and validates one deterministic UTF-8 language-text payload.

Validation guarantees:

- `language` consists of exactly three native ASCII bytes;
- description and text contain valid UTF-8;
- description and text contain no U+0000;
- the mandatory description terminator fits;
- the complete payload fits the ID3v2.4 28-bit frame-size domain.

The returned size includes:

- the `$03` UTF-8 encoding marker;
- the three language bytes;
- description bytes;
- the one-byte description terminator;
- text bytes.

Params:
    language = Three-byte native ID3 language identifier.
    description = Content description or descriptor.
    text = Comment, lyrics or other language-qualified text.

Returns:
    Encoded payload size or a structured serialization error.
+/
SerializationResult!size_t
measureId3v24Utf8LanguageTextPayload(
    string language,
    string description,
    string text
)
    @safe
{
    size_t total = 1; // UTF-8 encoding marker.

    if (language.length != 3)
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.invalidValue,
                    total
                )
            );
    }

    foreach (
        byteIndex,
        ubyte languageByte;
        language
    )
    {
        if (languageByte > 0x7F)
        {
            return
                SerializationResult!size_t.failure(
                    SerializationError(
                        SerializationErrorCode
                            .unsupportedRepresentation,
                        total + byteIndex,
                        languageByte,
                        0x7F
                    )
                );
        }
    }

    total += 3;

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
     * COMM/USLT always require the encoded description terminator.
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

    const textValid =
        validLength(text);

    if (
        textValid !=
        text.length
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.invalidValue,
                    total + textValid
                )
            );
    }

    foreach (
        byteIndex,
        textByte;
        text
    )
    {
        if (textByte == '\0')
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
        text.length >
        maximumFrameDataSize - total
    )
    {
        return
            SerializationResult!size_t.failure(
                SerializationError(
                    SerializationErrorCode.valueOutOfRange,
                    0,
                    cast(ulong) total +
                        cast(ulong) text.length,
                    maximumFrameDataSize
                )
            );
    }

    total += text.length;

    return
        SerializationResult!size_t.success(
            total
        );
}


/++
Serializes one canonical language/description/text tuple as
deterministic UTF-8 frame data.

The resulting payload is:

    $03 <3-byte language> <description> $00 <text>

The output owns its bytes.

Params:
    language = Three-byte native ID3 language identifier.
    description = Content description or descriptor.
    text = Language-qualified text.

Returns:
    Encoded payload or the validation error reported by
    `measureId3v24Utf8LanguageTextPayload`.
+/
SerializationResult!(ubyte[])
serializeId3v24Utf8LanguageTextPayload(
    string language,
    string description,
    string text
)
    @safe
{
    auto measured =
        measureId3v24Utf8LanguageTextPayload(
            language,
            description,
            text
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

    foreach (languageByte; language)
    {
        output[position++] =
            cast(ubyte) languageByte;
    }

    foreach (descriptionByte; description)
    {
        output[position++] =
            cast(ubyte) descriptionByte;
    }

    output[position++] = 0x00;

    foreach (textByte; text)
    {
        output[position++] =
            cast(ubyte) textByte;
    }

    assert(position == output.length);

    return
        SerializationResult!(ubyte[])
            .success(output);
}


/// A normal UTF-8 language-text payload is serialized deterministically.
unittest
{
    auto measured =
        measureId3v24Utf8LanguageTextPayload(
            "eng",
            "note",
            "hello\nworld"
        );

    assert(measured.hasValue);
    assert(measured.value == 20);

    auto result =
        serializeId3v24Utf8LanguageTextPayload(
            "eng",
            "note",
            "hello\nworld"
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'e', 'n', 'g',
            'n', 'o', 't', 'e',
            0x00,
            'h', 'e', 'l', 'l', 'o',
            0x0A,
            'w', 'o', 'r', 'l', 'd'
        ]
    );
}


/// Empty description and text retain the mandatory description terminator.
unittest
{
    auto result =
        serializeId3v24Utf8LanguageTextPayload(
            "deu",
            "",
            ""
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'd', 'e', 'u',
            0x00
        ]
    );
}


/// Non-ASCII description and text are emitted as UTF-8.
unittest
{
    auto result =
        serializeId3v24Utf8LanguageTextPayload(
            "deu",
            "Größe",
            "Grüße"
        );

    assert(result.hasValue);

    assert(
        result.value ==
        [
            0x03,
            'd', 'e', 'u',

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


/// Native language identifiers must contain exactly three bytes.
unittest
{
    auto shortResult =
        measureId3v24Utf8LanguageTextPayload(
            "en",
            "",
            ""
        );

    assert(shortResult.hasError);

    assert(
        shortResult.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(shortResult.error.index == 1);

    auto longResult =
        measureId3v24Utf8LanguageTextPayload(
            "engl",
            "",
            ""
        );

    assert(longResult.hasError);

    assert(
        longResult.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(longResult.error.index == 1);
}


/// Native language bytes must remain in the ASCII domain.
unittest
{
    immutable(char)[] language =
        [
            cast(char) 0xE4,
            'n',
            'g'
        ];

    auto result =
        measureId3v24Utf8LanguageTextPayload(
            language,
            "",
            ""
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    assert(result.error.index == 1);
    assert(result.error.value == 0xE4);
    assert(result.error.limit == 0x7F);
}


/// Embedded NUL cannot terminate the description early.
unittest
{
    auto result =
        measureId3v24Utf8LanguageTextPayload(
            "eng",
            "a\0b",
            "text"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    /*
     * $03 + three language bytes + "a".
     */
    assert(result.error.index == 5);
}


/// Embedded NUL is rejected in the text body.
unittest
{
    auto result =
        measureId3v24Utf8LanguageTextPayload(
            "eng",
            "x",
            "a\0b"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );

    /*
     * $03 + language + "x" + $00 + "a".
     */
    assert(result.error.index == 7);
}


/// Malformed UTF-8 description is rejected at its payload-relative byte.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    auto result =
        measureId3v24Utf8LanguageTextPayload(
            "eng",
            malformed,
            "text"
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    assert(result.error.index == 4);
}


/// Malformed UTF-8 text is rejected after the description terminator.
unittest
{
    immutable(char)[] malformed =
        [
            cast(char) 0xC3,
            cast(char) 0x28
        ];

    auto result =
        measureId3v24Utf8LanguageTextPayload(
            "eng",
            "x",
            malformed
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode.invalidValue
    );

    /*
     * $03 + language + "x" + $00.
     */
    assert(result.error.index == 6);
}
