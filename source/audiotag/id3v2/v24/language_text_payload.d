/++
Shared decoding for ID3v2.4 language + descriptor + text payloads.

This payload shape is used by frames such as `COMM` and `USLT`:

- one text-encoding marker;
- one three-byte language field;
- one terminated descriptor;
- one text field extending to the payload boundary.

This module contains only the shared binary/text decoding mechanics.
Frame-specific semantics remain in the individual codecs.
+/
module audiotag.id3v2.v24.language_text_payload;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v24.data_cursor :
    Id3v24DataCursor;

import audiotag.id3v2.v24.text_decode :
    decodeId3v24TextSpan;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding,
    parseId3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/++
Decoded common language-text payload.
+/
struct Id3v24LanguageTextPayload
{
    /// Text encoding used by descriptor and text.
    Id3v24TextEncoding encoding;

    /// Three-byte language field as stored.
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

    /// Whether ID3 byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes a bounded language + descriptor + text payload.

For encoding `$01`, non-empty strings within the payload must use the
same UTF-16 byte order.

Params:
    rawPayload = Physical semantic payload bytes.
    unsynchronised = Whether ID3 byte unsynchronisation applies.

Returns:
    Decoded payload or a structured parsing/text-decoding error.
+/
ParseResult!Id3v24LanguageTextPayload
decodeId3v24LanguageTextPayload(
    ByteSpan rawPayload,
    bool unsynchronised = false
)
    @safe
{
    auto payload =
        Id3v24DataCursor(
            rawPayload,
            unsynchronised
        );

    auto encodingResult =
        payload.parseId3v24TextEncoding();

    if (encodingResult.hasError)
    {
        return ParseResult!Id3v24LanguageTextPayload.failure(
            encodingResult.error
        );
    }

    const encoding =
        encodingResult.value;

    const languageStart =
        payload.remainingRaw;

    char[3] language;

    foreach (i; 0 .. 3)
    {
        auto byteResult =
            payload.takeByte();

        if (byteResult.hasError)
        {
            return ParseResult!Id3v24LanguageTextPayload.failure(
                byteResult.error
            );
        }

        language[i] =
            cast(char) byteResult.value.value;
    }

    const languagePhysicalLength =
        languageStart.length -
        payload.remainingRaw.length;

    const rawLanguage =
        languageStart.subspan(
            0,
            languagePhysicalLength
        );

    auto descriptorResult =
        payload.takeId3v24TerminatedTextSegment(
            encoding
        );

    if (descriptorResult.hasError)
    {
        return ParseResult!Id3v24LanguageTextPayload.failure(
            descriptorResult.error
        );
    }

    const descriptorSegment =
        descriptorResult.value;

    const rawText =
        payload.remainingRaw;

    ubyte utf16ByteOrder;

    auto descriptor =
        decodeTextPart(
            descriptorSegment.raw,
            encoding,
            unsynchronised,
            utf16ByteOrder
        );

    if (descriptor.hasError)
    {
        return ParseResult!Id3v24LanguageTextPayload.failure(
            descriptor.error
        );
    }

    auto text =
        decodeTextPart(
            rawText,
            encoding,
            unsynchronised,
            utf16ByteOrder
        );

    if (text.hasError)
    {
        return ParseResult!Id3v24LanguageTextPayload.failure(
            text.error
        );
    }

    return ParseResult!Id3v24LanguageTextPayload.success(
        Id3v24LanguageTextPayload(
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


/++
Decodes one text part and enforces consistent UTF-16 byte order.
+/
private ParseResult!string decodeTextPart(
    ByteSpan raw,
    Id3v24TextEncoding encoding,
    bool unsynchronised,
    ref ubyte utf16ByteOrder
)
    @safe
{
    auto decoded =
        decodeId3v24TextSpan(
            raw,
            encoding,
            unsynchronised
        );

    if (decoded.hasError)
        return decoded;

    if (
        encoding != Id3v24TextEncoding.utf16 ||
        raw.empty
    )
    {
        return decoded;
    }

    auto cursor =
        Id3v24DataCursor(
            raw,
            unsynchronised
        );

    auto firstResult =
        cursor.takeByte();

    assert(firstResult.hasValue);

    auto secondResult =
        cursor.takeByte();

    assert(secondResult.hasValue);

    const first =
        firstResult.value;

    const second =
        secondResult.value;

    ubyte byteOrder;

    if (
        first.value == 0xFE &&
        second.value == 0xFF
    )
    {
        byteOrder = 1;
    }
    else
    {
        // The text decoder already validated the BOM.
        assert(
            first.value == 0xFF &&
            second.value == 0xFE
        );

        byteOrder = 2;
    }

    if (utf16ByteOrder == 0)
    {
        utf16ByteOrder = byteOrder;
    }
    else if (utf16ByteOrder != byteOrder)
    {
        return ParseResult!string.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                first.sourceOffset
            )
        );
    }

    return decoded;
}


/// UTF-8 language-text payload is decoded end to end.
unittest
{
    const ubyte[] bytes =
        [
            0x03,
            'e', 'n', 'g',
            'n', 'o', 't', 'e',
            0x00,
            'h', 'e', 'l', 'l', 'o'
        ];

    auto result =
        decodeId3v24LanguageTextPayload(
            ByteSpan(bytes, 100)
        );

    assert(result.hasValue);

    const payload =
        result.value;

    assert(payload.encoding == Id3v24TextEncoding.utf8);
    assert(payload.language[] == "eng");
    assert(payload.descriptor == "note");
    assert(payload.text == "hello");

    assert(payload.rawLanguage.sourceOffset == 101);
    assert(payload.rawDescriptor.sourceOffset == 104);
    assert(payload.rawText.sourceOffset == 109);
}


/// UTF-16 text parts must use a consistent byte order.
unittest
{
    const ubyte[] bytes =
        [
            0x01,
            'e', 'n', 'g',

            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            0xFE, 0xFF,
            0x00, 0x42
        ];

    auto result =
        decodeId3v24LanguageTextPayload(
            ByteSpan(bytes, 200)
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 210);
}


/// A truncated language field remains a structured end-of-span error.
unittest
{
    const ubyte[] bytes =
        [
            0x03,
            'e', 'n'
        ];

    auto result =
        decodeId3v24LanguageTextPayload(
            ByteSpan(bytes, 300)
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.endOfSpan
    );

    assert(result.error.offset == 303);
}
