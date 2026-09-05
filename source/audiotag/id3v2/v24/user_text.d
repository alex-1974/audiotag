/++
ID3v2.4 user-defined text-information frame decoding.

The `TXXX` frame consists of:

- one text-encoding marker;
- one terminated description;
- one value extending to the end of the frame.

Compressed or encrypted frames remain structurally valid but are not
semantically decoded until the required transformation is available.
+/
module audiotag.id3v2.v24.user_text;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v24.data_cursor :
    Id3v24DataCursor;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_data :
    parseId3v24FrameDataLayout;

import audiotag.id3v2.v24.text_decode :
    decodeId3v24TextSpan;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding,
    parseId3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/++
Semantic availability of a user-defined text frame.
+/
enum Id3v24UserTextAvailability : ubyte
{
    /// Description and value were decoded successfully.
    decoded,

    /// Payload must be decompressed before semantic decoding.
    requiresDecompression,

    /// Payload must be decrypted before semantic decoding.
    requiresDecryption,

    /// Payload requires both transformations.
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.4 `TXXX` frame.
+/
struct Id3v24UserTextFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Text encoding declared by the frame.
    Id3v24TextEncoding encoding;

    /// User-defined field description.
    string description;

    /// User-defined field value.
    string value;

    /// Physical description bytes, excluding its terminator.
    ByteSpan rawDescription;

    /// Physical value bytes extending to the frame boundary.
    ByteSpan rawValue;

    /// Whether unsynchronisation was effective for this frame.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic `TXXX` decoding.
+/
struct Id3v24UserTextOutcome
{
    /// Semantic availability state.
    Id3v24UserTextAvailability availability;

    /// Decoded frame when available.
    Id3v24UserTextFrame text;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;

    /// Whether semantic text is available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24UserTextAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 user-defined text-information (`TXXX`) frame.

The description is required to be terminated according to the selected
encoding. The value occupies the remainder of the bounded frame
payload.

For UTF-16 encoding `$01`, non-empty strings in the frame must use the
same byte order.

Compressed or encrypted frames return a successful transformation-
pending outcome rather than a malformed-input error.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level unsynchronisation applies.

Returns:
    A decoded or transformation-pending outcome, or a structured error.
+/
ParseResult!Id3v24UserTextOutcome
decodeId3v24UserTextFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "TXXX")
    {
        return ParseResult!Id3v24UserTextOutcome.failure(
            ParseError(
                ParseErrorCode.invalidSignature,
                frame.header.sourceOffset
            )
        );
    }

    auto layoutResult =
        frame.parseId3v24FrameDataLayout(
            tagUnsynchronised
        );

    if (layoutResult.hasError)
    {
        return ParseResult!Id3v24UserTextOutcome.failure(
            layoutResult.error
        );
    }

    const layout =
        layoutResult.value;

    if (
        frame.header.compressed ||
        frame.header.encrypted
    )
    {
        Id3v24UserTextAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24UserTextAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24UserTextAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24UserTextAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24UserTextOutcome.success(
            Id3v24UserTextOutcome(
                availability,
                Id3v24UserTextFrame.init,
                layout.rawPayload
            )
        );
    }

    auto payload =
        layout.payloadCursor();

    auto encodingResult =
        payload.parseId3v24TextEncoding();

    if (encodingResult.hasError)
    {
        return ParseResult!Id3v24UserTextOutcome.failure(
            encodingResult.error
        );
    }

    const encoding =
        encodingResult.value;

    auto descriptionResult =
        payload.takeId3v24TerminatedTextSegment(
            encoding
        );

    if (descriptionResult.hasError)
    {
        return ParseResult!Id3v24UserTextOutcome.failure(
            descriptionResult.error
        );
    }

    const descriptionSegment =
        descriptionResult.value;

    const rawValue =
        payload.remainingRaw;

    ubyte utf16ByteOrder;

    auto description =
        decodeUserTextPart(
            descriptionSegment.raw,
            encoding,
            layout.effectiveUnsynchronisation,
            utf16ByteOrder
        );

    if (description.hasError)
    {
        return ParseResult!Id3v24UserTextOutcome.failure(
            description.error
        );
    }

    auto value =
        decodeUserTextPart(
            rawValue,
            encoding,
            layout.effectiveUnsynchronisation,
            utf16ByteOrder
        );

    if (value.hasError)
    {
        return ParseResult!Id3v24UserTextOutcome.failure(
            value.error
        );
    }

    auto text =
        Id3v24UserTextFrame(
            frame.header.sourceOffset,
            encoding,
            description.value,
            value.value,
            descriptionSegment.raw,
            rawValue,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24UserTextOutcome.success(
        Id3v24UserTextOutcome(
            Id3v24UserTextAvailability.decoded,
            text,
            layout.rawPayload
        )
    );
}


/++
Decodes one TXXX text part and enforces consistent UTF-16 byte order.
+/
private ParseResult!string decodeUserTextPart(
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
        // The decoder above has already validated the BOM.
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


import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A UTF-8 TXXX frame decodes description and value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00,

            0x03,
            'k', 'e', 'y', 0x00,
            'v', 'a', 'l', 'u', 'e'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const text = result.value.text;

    assert(text.sourceOffset == 100);
    assert(text.encoding == Id3v24TextEncoding.utf8);
    assert(text.description == "key");
    assert(text.value == "value");

    assert(text.rawDescription.sourceOffset == 111);
    assert(text.rawDescription.data == ['k', 'e', 'y']);

    assert(text.rawValue.sourceOffset == 115);
    assert(text.rawValue.data == ['v', 'a', 'l', 'u', 'e']);
}


/// UTF-16 description and value may use little-endian encoding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x01,

            // Description "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // Value "B", little endian.
            0xFF, 0xFE,
            0x42, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.text.description == "A");
    assert(result.value.text.value == "B");
}


/// UTF-16 strings within one TXXX frame must share byte order.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x01,

            // Description "A", little endian.
            0xFF, 0xFE,
            0x41, 0x00,
            0x00, 0x00,

            // Value "B", big endian.
            0xFE, 0xFF,
            0x00, 0x42
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 317);
}


/// A missing description terminator is malformed.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x03,
            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// Description and value may both be empty.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.text.description.length == 0);
    assert(result.value.text.value.length == 0);
}


/// The TXXX codec rejects ordinary text-information frames.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x03,
            'A'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
    assert(result.error.offset == 600);
}


/// Compressed TXXX data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            // Required DLI.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 700));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24UserTextAvailability.requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Frame-level unsynchronisation is reversed for the TXXX value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x02,

            0x00,
            'x',
            0x00,
            0xFF, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UserTextFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.text.description == "x");
    assert(result.value.text.value == "\u00FF");

    assert(
        result.value.text.effectiveUnsynchronisation
    );

    // The raw span preserves the physical stuffing byte.
    assert(result.value.text.rawValue.data == [0xFF, 0x00]);
}
