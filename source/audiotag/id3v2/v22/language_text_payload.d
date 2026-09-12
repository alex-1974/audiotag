/++
Shared decoding for ID3v2.2 language + descriptor + text payloads.

This payload shape is used by frames such as `COM` and `ULT`:

- one text-encoding marker;
- one three-byte language field;
- one terminated descriptor;
- one text field extending to the payload boundary.

This module contains only the shared binary/text decoding mechanics.
Frame-specific semantics remain in the individual codecs.

For ID3v2.2 encoding `$01`, descriptor and text are decoded independently.
Each may carry its own byte-order mark; BOM-less UCS-2 uses the deterministic
big-endian default implemented by `text_decode.d`.

ID3v2.2 whole-tag unsynchronisation is reversed while traversing the bounded
physical payload. Returned raw spans retain physical source provenance
including stuffing bytes.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.language_text_payload;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.text_decode :
    decodeId3v22TextSpan;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding,
    parseId3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;


/++
Decoded common ID3v2.2 language-text payload.
+/
struct Id3v22LanguageTextPayload
{
    /// Text encoding used by descriptor and text.
    Id3v22TextEncoding encoding;

    /// Three-byte language field as stored logically.
    char[3] language;

    /// Physical language bytes as stored.
    ByteSpan rawLanguage;

    /// Decoded terminated descriptor.
    string descriptor;

    /// Decoded text extending to the payload boundary.
    string text;

    /// Physical descriptor bytes, excluding its terminator.
    ByteSpan rawDescriptor;

    /// Physical text bytes extending to the payload boundary.
    ByteSpan rawText;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes a bounded ID3v2.2 language + descriptor + text payload.

The payload has the common form:

    Text encoding       $xx
    Language            $xx xx xx
    Descriptor          <text according to encoding> $00 (00)
    Text                <text according to encoding>

Exactly three logical language bytes are consumed. Their physical
representation may be longer when whole-tag unsynchronisation stuffing is
present; `rawLanguage` preserves those physical bytes.

The descriptor terminator is mandatory.

The text field occupies the remainder of the bounded payload and need not be
terminated.

Params:
    rawPayload = Physical payload bytes.
    unsynchronised = Whether ID3v2.2 whole-tag unsynchronisation applies.

Returns:
    Decoded payload or a structured parsing/text-decoding error.
+/
ParseResult!Id3v22LanguageTextPayload
decodeId3v22LanguageTextPayload(
    ByteSpan rawPayload,
    bool unsynchronised = false
)
    @safe
{
    auto payload =
        Id3v22DataCursor(
            rawPayload,
            unsynchronised
        );


    auto encodingResult =
        payload.parseId3v22TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v22LanguageTextPayload
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * Preserve physical provenance while reading exactly three logical
     * language bytes.
     */
    const languageStart =
        payload.remainingRaw;

    char[3] language;

    foreach (
        i;
        0 .. 3
    )
    {
        auto byteResult =
            payload.takeByte();

        if (
            byteResult.hasError
        )
        {
            return
                ParseResult!Id3v22LanguageTextPayload
                    .failure(
                        byteResult.error
                    );
        }

        language[i] =
            cast(char)
                byteResult.value.value;
    }

    const languagePhysicalLength =
        languageStart.length -
        payload.remainingRaw.length;

    const rawLanguage =
        languageStart.subspan(
            0,
            languagePhysicalLength
        );


    /*
     * The descriptor is the only structurally terminated textual field.
     */
    auto descriptorResult =
        payload.takeId3v22TerminatedTextSegment(
            encoding
        );

    if (
        descriptorResult.hasError
    )
    {
        return
            ParseResult!Id3v22LanguageTextPayload
                .failure(
                    descriptorResult.error
                );
    }

    const descriptorSegment =
        descriptorResult.value;


    /*
     * Everything after the descriptor terminator belongs to the final text
     * field.
     */
    const rawText =
        payload.remainingRaw;


    /*
     * Decode descriptor and text independently.
     */
    auto descriptor =
        decodeId3v22TextSpan(
            descriptorSegment.raw,
            encoding,
            unsynchronised
        );

    if (
        descriptor.hasError
    )
    {
        return
            ParseResult!Id3v22LanguageTextPayload
                .failure(
                    descriptor.error
                );
    }


    auto text =
        decodeId3v22TextSpan(
            rawText,
            encoding,
            unsynchronised
        );

    if (
        text.hasError
    )
    {
        return
            ParseResult!Id3v22LanguageTextPayload
                .failure(
                    text.error
                );
    }


    return
        ParseResult!Id3v22LanguageTextPayload
            .success(
                Id3v22LanguageTextPayload(
                    encoding,
                    language,
                    rawLanguage,
                    descriptor.value,
                    text.value,
                    descriptorSegment.raw,
                    rawText,
                    unsynchronised
                )
            );
}


version (unittest)
{
    import audiotag.core.error :
        ParseErrorCode;
}


/// A Latin-1 language-text payload is decoded end to end.
unittest
{
    const ubyte[] bytes =
        [
            0x00,

            'e', 'n', 'g',

            'n', 'o', 't', 'e',
            0x00,

            'h', 'e', 'l', 'l', 'o'
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                100
            )
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(
        payload.encoding ==
        Id3v22TextEncoding.latin1
    );

    assert(payload.language[] == "eng");
    assert(payload.descriptor == "note");
    assert(payload.text == "hello");

    assert(payload.rawLanguage.sourceOffset == 101);

    assert(
        payload.rawLanguage.data ==
        ['e', 'n', 'g']
    );

    assert(payload.rawDescriptor.sourceOffset == 104);

    assert(
        payload.rawDescriptor.data ==
        ['n', 'o', 't', 'e']
    );

    assert(payload.rawText.sourceOffset == 109);

    assert(
        payload.rawText.data ==
        ['h', 'e', 'l', 'l', 'o']
    );

    assert(!payload.effectiveUnsynchronisation);
}


/// BOM-less UCS-2 descriptor and text use the v2.2 big-endian default.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            0x00, 0x41,
            0x00, 0x00,

            0x00, 0x42
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                200
            )
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(
        payload.encoding ==
        Id3v22TextEncoding.utf16
    );

    assert(payload.language[] == "eng");
    assert(payload.descriptor == "A");
    assert(payload.text == "B");
}


/// Descriptor and text may explicitly carry different byte-order marks.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * Descriptor "A", little endian.
             */
            0xFF, 0xFE,
            0x41, 0x00,

            0x00, 0x00,

            /*
             * Text "B", big endian.
             */
            0xFE, 0xFF,
            0x00, 0x42
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                300
            )
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(payload.descriptor == "A");
    assert(payload.text == "B");

    assert(
        payload.rawDescriptor.data ==
        [
            0xFF, 0xFE,
            0x41, 0x00
        ]
    );

    assert(
        payload.rawText.data ==
        [
            0xFE, 0xFF,
            0x00, 0x42
        ]
    );
}


/// Empty descriptor and text are valid.
unittest
{
    const ubyte[] bytes =
        [
            0x00,

            'd', 'e', 'u',

            0x00
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                400
            )
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(payload.language[] == "deu");
    assert(payload.descriptor.length == 0);
    assert(payload.text.length == 0);

    assert(payload.rawDescriptor.empty);
    assert(payload.rawDescriptor.sourceOffset == 404);

    assert(payload.rawText.empty);
    assert(payload.rawText.sourceOffset == 405);
}


/// A truncated three-byte language field remains an end-of-span error.
unittest
{
    const ubyte[] bytes =
        [
            0x00,
            'e', 'n'
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                500
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 503);
}


/// A missing descriptor terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            0x00,

            'e', 'n', 'g',

            'a', 'b', 'c'
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                600
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );

    assert(result.error.offset == 604);
}


/// Undefined encoding markers are rejected before language traversal.
unittest
{
    const ubyte[] bytes =
        [
            0x02,

            'e', 'n', 'g',
            0x00
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                700
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 700);
}


/// Whole-tag unsynchronisation preserves physical provenance.
unittest
{
    /*
     * Logical payload:
     *
     *   00
     *   e n g
     *   FF
     *   00
     *   FF
     *
     * Physical payload:
     *
     *   00
     *   e n g
     *   FF 00
     *   00
     *   FF 00
     */
    const ubyte[] bytes =
        [
            0x00,

            'e', 'n', 'g',

            0xFF, 0x00,
            0x00,

            0xFF, 0x00
        ];

    auto result =
        decodeId3v22LanguageTextPayload(
            ByteSpan(
                bytes,
                800
            ),
            true
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(payload.effectiveUnsynchronisation);
    assert(payload.language[] == "eng");
    assert(payload.descriptor == "\u00FF");
    assert(payload.text == "\u00FF");

    assert(
        payload.rawDescriptor.data ==
        [0xFF, 0x00]
    );

    assert(
        payload.rawText.data ==
        [0xFF, 0x00]
    );
}
