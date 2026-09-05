/++
ID3v2.4 text-information frame decoding.

This module decodes ordinary `T***` text-information frames, excluding
the structurally different `TXXX` frame.

Multiple values are represented as the null-separated list defined by
ID3v2.4.

Compressed or encrypted text frames remain structurally valid but
cannot yet be semantically decoded. Such frames return a successful
outcome describing the required transformation and preserving their
raw payload.
+/
module audiotag.id3v2.v24.text_information;

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
Semantic availability of a text-information frame.
+/
enum Id3v24TextInformationAvailability : ubyte
{
    /// Text values were decoded successfully.
    decoded,

    /// Payload must be decompressed before semantic decoding.
    requiresDecompression,

    /// Payload must be decrypted before semantic decoding.
    requiresDecryption,

    /// Payload requires both decryption and decompression.
    requiresDecryptionAndDecompression
}


/++
Decoded ordinary ID3v2.4 text-information frame.

This type represents `T***` frames except `TXXX`.
+/
struct Id3v24TextInformationFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Native four-character frame identifier.
    char[4] id;

    /// Text encoding declared by the frame.
    Id3v24TextEncoding encoding;

    /// Decoded text values in their native order.
    string[] values;

    /// Physical information bytes after the encoding marker.
    ByteSpan rawInformation;

    /// Whether unsynchronisation was effective for this frame.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic text-information decoding.

When `availability == decoded`, `text` contains the decoded frame.

Otherwise `rawPayload` preserves the still-transformed semantic
payload after structural frame-format fields have been removed.
+/
struct Id3v24TextInformationOutcome
{
    /// Semantic availability state.
    Id3v24TextInformationAvailability availability;

    /// Decoded text frame when available.
    Id3v24TextInformationFrame text;

    /// Raw semantic payload after structural format prefixes.
    ByteSpan rawPayload;

    /// Whether semantic text values are available.
    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24TextInformationAvailability.decoded;
    }
}


/++
Decodes an ordinary ID3v2.4 text-information frame.

The frame identifier must begin with `T` and must not be `TXXX`.

Grouping identity, Data Length Indicator and unsynchronisation are
handled by the lower structural layers.

Compressed or encrypted frames return a successful non-decoded
outcome because those transformations are valid ID3v2.4 features,
not malformed input.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level unsynchronisation applies.

Returns:
    A decoded or transformation-pending text-information outcome, or a
    structured error for malformed text data.
+/
ParseResult!Id3v24TextInformationOutcome
decodeId3v24TextInformationFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[0] != 'T' ||
        frame.header.id[] == "TXXX"
    )
    {
        return ParseResult!Id3v24TextInformationOutcome.failure(
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
        return ParseResult!Id3v24TextInformationOutcome.failure(
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
        Id3v24TextInformationAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24TextInformationAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24TextInformationAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24TextInformationAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24TextInformationOutcome.success(
            Id3v24TextInformationOutcome(
                availability,
                Id3v24TextInformationFrame.init,
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
        return ParseResult!Id3v24TextInformationOutcome.failure(
            encodingResult.error
        );
    }

    const encoding =
        encodingResult.value;

    const rawInformation =
        payload.remainingRaw;

    string[] values;

    // ID3v2.4 encoding $01 requires all strings in one frame to use
    // the same byte order.
    ubyte utf16ByteOrder = 0;

    if (payload.empty)
    {
        auto decoded =
            decodeTextValue(
                payload.remainingRaw,
                encoding,
                layout.effectiveUnsynchronisation,
                utf16ByteOrder
            );

        if (decoded.hasError)
        {
            return ParseResult!Id3v24TextInformationOutcome.failure(
                decoded.error
            );
        }

        values ~= decoded.value;
    }
    else
    {
        while (!payload.empty)
        {
            auto segmentResult =
                payload.takeId3v24TerminatedTextSegment(
                    encoding
                );

            if (segmentResult.hasValue)
            {
                auto decoded =
                    decodeTextValue(
                        segmentResult.value.raw,
                        encoding,
                        layout.effectiveUnsynchronisation,
                        utf16ByteOrder
                    );

                if (decoded.hasError)
                {
                    return ParseResult!Id3v24TextInformationOutcome.failure(
                        decoded.error
                    );
                }

                values ~= decoded.value;

                continue;
            }

            if (
                segmentResult.error.code !=
                ParseErrorCode.patternNotFound
            )
            {
                return ParseResult!Id3v24TextInformationOutcome.failure(
                    segmentResult.error
                );
            }

            // No terminator remains. The enclosing frame boundary
            // defines the extent of the final text value.
            auto decoded =
                decodeTextValue(
                    payload.remainingRaw,
                    encoding,
                    layout.effectiveUnsynchronisation,
                    utf16ByteOrder
                );

            if (decoded.hasError)
            {
                return ParseResult!Id3v24TextInformationOutcome.failure(
                    decoded.error
                );
            }

            values ~= decoded.value;

            break;
        }
    }

    auto text =
        Id3v24TextInformationFrame(
            frame.header.sourceOffset,
            frame.header.id,
            encoding,
            values,
            rawInformation,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24TextInformationOutcome.success(
        Id3v24TextInformationOutcome(
            Id3v24TextInformationAvailability.decoded,
            text,
            layout.rawPayload
        )
    );
}


/++
Decodes one bounded value and enforces consistent UTF-16 byte order
across all `$01` strings in the same frame.
+/
private ParseResult!string decodeTextValue(
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

    const first = firstResult.value;
    const second = secondResult.value;

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
        // decodeId3v24TextSpan() already validated the BOM.
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


/// A normal UTF-8 TIT2 frame decodes one value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            0x03,
            'T', 'i', 't', 'l', 'e'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const text = result.value.text;

    assert(text.sourceOffset == 100);
    assert(text.id[] == "TIT2");
    assert(text.encoding == Id3v24TextEncoding.utf8);

    assert(text.values.length == 1);
    assert(text.values[0] == "Title");

    assert(text.rawInformation.sourceOffset == 111);
    assert(text.rawInformation.length == 5);
}


/// Multiple UTF-8 strings are decoded from their null-separated list.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x00,

            0x03,
            'A', 0x00, 'B'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.text.values.length == 2);
    assert(result.value.text.values[0] == "A");
    assert(result.value.text.values[1] == "B");
}


/// A final terminator does not manufacture an additional value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'A', 'L', 'B',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            0x03,
            'A',
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.text.values.length == 1);
    assert(result.value.text.values[0] == "A");
}


/// An encoding marker without information represents one empty value.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'C', 'O', 'N',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,

            0x03
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.text.values.length == 1);
    assert(result.value.text.values[0].length == 0);
}


/// UTF-16BE multiple values use aligned two-byte separators.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x07,
            0x00, 0x00,

            0x02,

            0x00, 0x41,
            0x00, 0x00,
            0x00, 0x42
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);

    assert(result.value.text.values.length == 2);
    assert(result.value.text.values[0] == "A");
    assert(result.value.text.values[1] == "B");
}


/// UTF-16 strings in one frame must use the same byte order.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'P', 'E', '1',
            0x00, 0x00, 0x00, 0x0B,
            0x00, 0x00,

            0x01,

            // Big-endian "A".
            0xFE, 0xFF,
            0x00, 0x41,
            0x00, 0x00,

            // Little-endian "B".
            0xFF, 0xFE,
            0x42, 0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.inconsistentStructure
    );

    assert(result.error.offset == 617);
}


/// TXXX is deliberately excluded from the generic T*** decoder.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'X', 'X', 'X',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x03
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 700));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
    assert(result.error.offset == 700);
}


/// Non-text frames are rejected by this semantic codec.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasError);
    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );
}


/// Compressed text remains valid but is not decoded yet.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            // Required DLI.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 900));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24TextInformationAvailability
            .requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Encrypted text remains valid but is not decoded yet.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x04,

            // Encryption method followed by opaque ciphertext.
            0x23,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 1000));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24TextInformationAvailability
            .requiresDecryption
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Frame-level unsynchronisation is reversed before text decoding.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x02,

            0x00,
            0xFF, 0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 1100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24TextInformationFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(result.value.text.values.length == 1);
    assert(result.value.text.values[0] == "\u00FF");

    assert(
        result.value.text.effectiveUnsynchronisation
    );
}
