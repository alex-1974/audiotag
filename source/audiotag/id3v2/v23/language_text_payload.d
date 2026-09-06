/++
Shared decoding for ID3v2.3 language + descriptor + text payloads.

This payload shape is used by frames such as `COMM` and `USLT`:

- one text-encoding marker;
- one three-byte language field;
- one terminated descriptor;
- one text field extending to the payload boundary.

This module contains only the shared binary/text decoding mechanics.
Frame-specific semantics remain in the individual codecs.

For ID3v2.3 encoding `$01`, each non-empty Unicode string carries its
own byte-order mark. Descriptor and text are therefore decoded
independently and may use different byte orders.

ID3v2.3 whole-tag unsynchronisation is reversed while traversing the
bounded physical semantic payload. Returned raw spans retain physical
source provenance including stuffing bytes.
+/
module audiotag.id3v2.v23.language_text_payload;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v23.data_cursor :
    Id3v23DataCursor;

import audiotag.id3v2.v23.text_decode :
    decodeId3v23TextSpan;

import audiotag.id3v2.v23.text_encoding :
    Id3v23TextEncoding,
    parseId3v23TextEncoding;

import audiotag.id3v2.v23.text_segment :
    takeId3v23TerminatedTextSegment;


/++
Decoded common ID3v2.3 language-text payload.
+/
struct Id3v23LanguageTextPayload
{
    /// Text encoding used by descriptor and text.
    Id3v23TextEncoding encoding;

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

    /// Whether ID3v2.3 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes a bounded ID3v2.3 language + descriptor + text payload.

The payload has the common form:

    Text encoding       $xx
    Language            $xx xx xx
    Descriptor          <text according to encoding> $00 (00)
    Text                <text according to encoding>

Exactly three logical language bytes are consumed. Their physical
representation may be longer when tag-level unsynchronisation stuffing
is present; `rawLanguage` preserves those physical bytes.

The descriptor terminator is mandatory.

The text field occupies the remainder of the bounded payload and need
not be terminated.

For encoding `$01`, every non-empty Unicode string is decoded according
to its own BOM. ID3v2.3 does not impose a shared byte order between the
descriptor and text fields.

Params:
    rawPayload = Physical semantic payload bytes.
    unsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applies.

Returns:
    Decoded payload or a structured parsing/text-decoding error.
+/
ParseResult!Id3v23LanguageTextPayload
decodeId3v23LanguageTextPayload(
    ByteSpan rawPayload,
    bool unsynchronised = false
)
    @safe
{
    auto payload =
        Id3v23DataCursor(
            rawPayload,
            unsynchronised
        );


    /*
     * The first logical byte selects the encoding used by both textual
     * fields. Only the ID3v2.3 markers $00 and $01 are accepted by the
     * lower encoding parser.
     */
    auto encodingResult =
        payload.parseId3v23TextEncoding();

    if (
        encodingResult.hasError
    )
    {
        return
            ParseResult!Id3v23LanguageTextPayload
                .failure(
                    encodingResult.error
                );
    }

    const encoding =
        encodingResult.value;


    /*
     * Preserve physical provenance for the language field while reading
     * exactly three logical bytes.
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
                ParseResult!Id3v23LanguageTextPayload
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
     * The descriptor is the only terminated textual field in this
     * shared payload shape.
     */
    auto descriptorResult =
        payload.takeId3v23TerminatedTextSegment(
            encoding
        );

    if (
        descriptorResult.hasError
    )
    {
        return
            ParseResult!Id3v23LanguageTextPayload
                .failure(
                    descriptorResult.error
                );
    }

    const descriptorSegment =
        descriptorResult.value;


    /*
     * Everything after the descriptor terminator belongs to the final
     * text field.
     */
    const rawText =
        payload.remainingRaw;


    /*
     * Decode the two strings independently.
     *
     * This intentionally differs from the v2.4 helper. ID3v2.3 Unicode
     * strings carry their own BOM and are not required to share one byte
     * order within a COMM/USLT-style payload.
     */
    auto descriptor =
        decodeId3v23TextSpan(
            descriptorSegment.raw,
            encoding,
            unsynchronised
        );

    if (
        descriptor.hasError
    )
    {
        return
            ParseResult!Id3v23LanguageTextPayload
                .failure(
                    descriptor.error
                );
    }


    auto text =
        decodeId3v23TextSpan(
            rawText,
            encoding,
            unsynchronised
        );

    if (
        text.hasError
    )
    {
        return
            ParseResult!Id3v23LanguageTextPayload
                .failure(
                    text.error
                );
    }


    return
        ParseResult!Id3v23LanguageTextPayload
            .success(
                Id3v23LanguageTextPayload(
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
        decodeId3v23LanguageTextPayload(
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
        Id3v23TextEncoding.latin1
    );

    assert(
        payload.language[] ==
        "eng"
    );

    assert(
        payload.descriptor ==
        "note"
    );

    assert(
        payload.text ==
        "hello"
    );

    assert(
        payload.rawLanguage.sourceOffset ==
        101
    );

    assert(
        payload.rawLanguage.data ==
        ['e', 'n', 'g']
    );

    assert(
        payload.rawDescriptor.sourceOffset ==
        104
    );

    assert(
        payload.rawDescriptor.data ==
        ['n', 'o', 't', 'e']
    );

    assert(
        payload.rawText.sourceOffset ==
        109
    );

    assert(
        payload.rawText.data ==
        ['h', 'e', 'l', 'l', 'o']
    );

    assert(
        !payload.effectiveUnsynchronisation
    );
}


/// UTF-16 descriptor and text may both use little-endian UCS-2.
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

            /*
             * Descriptor terminator.
             */
            0x00, 0x00,

            /*
             * Text "B", little endian.
             */
            0xFF, 0xFE,
            0x42, 0x00
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
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
        Id3v23TextEncoding.utf16
    );

    assert(
        payload.language[] ==
        "eng"
    );

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
            0xFF, 0xFE,
            0x42, 0x00
        ]
    );
}


/// ID3v2.3 Unicode descriptor and text may use different byte orders.
unittest
{
    /*
     * This is deliberately valid in v2.3.
     *
     * Each non-empty Unicode string carries its own BOM.
     */
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
        decodeId3v23LanguageTextPayload(
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
        payload.rawDescriptor.sourceOffset ==
        304
    );

    assert(
        payload.rawText.sourceOffset ==
        310
    );

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


/// Empty Unicode descriptor and text are valid.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * Empty descriptor terminator.
             */
            0x00, 0x00
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                400
            )
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(
        payload.descriptor.length ==
        0
    );

    assert(
        payload.text.length ==
        0
    );

    assert(payload.rawDescriptor.empty);

    assert(
        payload.rawDescriptor.sourceOffset ==
        404
    );

    assert(payload.rawText.empty);

    assert(
        payload.rawText.sourceOffset ==
        406
    );
}


/// A BOM-prefixed empty Unicode descriptor is accepted.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * Descriptor consists of a BOM followed by Unicode NULL.
             */
            0xFF, 0xFE,
            0x00, 0x00
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                450
            )
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(
        payload.descriptor.length ==
        0
    );

    assert(
        payload.text.length ==
        0
    );

    assert(
        payload.rawDescriptor.data ==
        [0xFF, 0xFE]
    );

    assert(
        payload.rawText.empty
    );
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
        decodeId3v23LanguageTextPayload(
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

    /*
     * Encoding at 500; language bytes at 501 and 502. The third
     * requested logical language byte begins at the physical end.
     */
    assert(
        result.error.offset ==
        503
    );
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
        decodeId3v23LanguageTextPayload(
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

    assert(
        result.error.offset ==
        604
    );
}


/// ID3v2.4-only encoding markers remain invalid.
unittest
{
    const ubyte[] bytes =
        [
            /*
             * UTF-8 marker is undefined in ID3v2.3.
             */
            0x03,

            'e', 'n', 'g',
            0x00
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
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

    assert(
        result.error.offset ==
        700
    );
}


/// A non-empty Unicode descriptor requires its own BOM.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * "A" without a BOM.
             */
            0x00, 0x41,

            /*
             * Descriptor terminator.
             */
            0x00, 0x00
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                800
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );

    assert(
        result.error.offset ==
        804
    );
}


/// A non-empty Unicode text field requires its own BOM.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * Empty descriptor.
             */
            0x00, 0x00,

            /*
             * Text "A" without a BOM.
             */
            0x00, 0x41
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                900
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidByteOrderMark
    );

    assert(
        result.error.offset ==
        906
    );
}


/// Whole-tag unsynchronisation applies across all logical payload fields.
unittest
{
    /*
     * Logical payload:
     *
     *   encoding     = 00
     *   language     = e FF g
     *   descriptor   = d FF
     *   terminator   = 00
     *   text         = t FF E1
     *
     * Physical payload:
     *
     *   00
     *   e FF 00 g
     *   d FF 00 00
     *   t FF 00 E1
     */
    const ubyte[] bytes =
        [
            0x00,

            /*
             * Three logical language bytes, four physical bytes.
             */
            'e',
            0xFF, 0x00,
            'g',

            /*
             * Descriptor "d FF" followed by its logical terminator.
             */
            'd',
            0xFF, 0x00,
            0x00,

            /*
             * Text "t FF E1".
             */
            't',
            0xFF, 0x00,
            0xE1
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                1000
            ),
            true
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(
        payload.language[0] ==
        'e'
    );

    assert(
        cast(ubyte) payload.language[1] ==
        0xFF
    );

    assert(
        payload.language[2] ==
        'g'
    );

    assert(
        payload.descriptor ==
        "d\u00FF"
    );

    assert(
        payload.text ==
        "t\u00FF\u00E1"
    );

    assert(
        payload.effectiveUnsynchronisation
    );

    /*
     * Physical provenance retains stuffing.
     */
    assert(
        payload.rawLanguage.data ==
        [
            'e',
            0xFF, 0x00,
            'g'
        ]
    );

    assert(
        payload.rawLanguage.sourceOffset ==
        1001
    );

    assert(
        payload.rawDescriptor.data ==
        [
            'd',
            0xFF, 0x00
        ]
    );

    assert(
        payload.rawDescriptor.sourceOffset ==
        1005
    );

    assert(
        payload.rawText.data ==
        [
            't',
            0xFF, 0x00,
            0xE1
        ]
    );

    assert(
        payload.rawText.sourceOffset ==
        1009
    );
}


/// Unsynchronisation inside Unicode BOMs is reversed independently.
unittest
{
    /*
     * Logical payload:
     *
     *   01
     *   eng
     *   FF FE 41 00
     *   00 00
     *   FE FF 00 42
     *
     * Description uses little endian; text uses big endian.
     *
     * Both BOMs need stuffing:
     *
     *   FF FE  -> FF 00 FE
     *
     * and the text BOM's final FF is followed by logical 00:
     *
     *   FE FF 00 42 -> FE FF 00 00 42
     */
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * Little-endian description BOM with stuffing.
             */
            0xFF, 0x00,
            0xFE,

            0x41, 0x00,

            /*
             * Descriptor terminator.
             */
            0x00, 0x00,

            /*
             * Big-endian text BOM with stuffing before the first
             * logical code-unit byte 00.
             */
            0xFE,
            0xFF, 0x00,

            0x00, 0x42
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                1100
            ),
            true
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(
        payload.descriptor ==
        "A"
    );

    assert(
        payload.text ==
        "B"
    );

    assert(
        payload.rawDescriptor.data ==
        [
            0xFF, 0x00,
            0xFE,
            0x41, 0x00
        ]
    );

    assert(
        payload.rawDescriptor.sourceOffset ==
        1104
    );

    assert(
        payload.rawText.data ==
        [
            0xFE,
            0xFF, 0x00,
            0x00, 0x42
        ]
    );

    assert(
        payload.rawText.sourceOffset ==
        1111
    );
}


/// Incomplete Unicode text remains a structured length error.
unittest
{
    const ubyte[] bytes =
        [
            0x01,

            'e', 'n', 'g',

            /*
             * Empty descriptor.
             */
            0x00, 0x00,

            /*
             * Valid BOM followed by one incomplete code-unit byte.
             */
            0xFE, 0xFF,
            0x41
        ];

    auto result =
        decodeId3v23LanguageTextPayload(
            ByteSpan(
                bytes,
                1200
            )
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidUnicodeSequence
    );

    assert(
        result.error.offset ==
        1208
    );

    assert(
        result.error.requested ==
        2
    );

    assert(
        result.error.available ==
        1
    );
}
