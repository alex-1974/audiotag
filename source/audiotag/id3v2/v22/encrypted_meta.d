/++
ID3v2.2 encrypted-meta (`CRM`) frame decoding.

The logical payload contains:

- a non-empty null-terminated owner identifier;
- a null-terminated content/explanation string;
- the remaining bytes as an opaque encrypted datablock.

Both textual fields use the default ID3v2.2 single-byte text encoding because
`CRM` carries no text-encoding marker.

The v2.2 specification says that a `CRM` with an empty owner identifier should
be ignored and preferably removed. Strict native decoding therefore rejects an
empty owner, matching this project's existing `UFI` treatment of the same
normative wording.

The encrypted datablock is preserved exactly as source data. This codec does
not invoke an owner-specific plugin, does not decrypt the block, and does not
attempt to parse encrypted bytes as nested ID3v2 frames.

Whole-tag unsynchronisation is reversed only while traversing logical fields.
Raw spans retain the exact physical source representation, including inserted
stuffing bytes.

`CRM` is specific to ID3v2.2. It was deleted in ID3v2.3 when encryption moved
to frame-level mechanisms and encryption-method registration.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.encrypted_meta;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

import audiotag.id3v2.v22.text_decode :
    decodeId3v22TextSpan;

import audiotag.id3v2.v22.text_encoding :
    Id3v22TextEncoding;

import audiotag.id3v2.v22.text_segment :
    takeId3v22TerminatedTextSegment;


/++
Decoded native ID3v2.2 `CRM` frame.
+/
struct Id3v22EncryptedMetaFrame
{
    /// Absolute physical source offset of the frame header.
    size_t sourceOffset;

    /// Decoded non-empty owner identifier.
    string ownerIdentifier;

    /// Physical owner bytes excluding the terminator.
    ByteSpan rawOwnerIdentifier;

    /// Physical source offset of the owner terminator.
    size_t ownerTerminatorSourceOffset;

    /// Decoded content/explanation text. May be empty.
    string contentExplanation;

    /// Physical explanation bytes excluding the terminator.
    ByteSpan rawContentExplanation;

    /// Physical source offset of the explanation terminator.
    size_t contentExplanationTerminatorSourceOffset;

    /// Exact physical encrypted datablock extending to the frame boundary.
    ByteSpan rawEncryptedData;

    /// Encrypted datablock length after whole-tag unsynchronisation is removed.
    size_t logicalEncryptedDataLength;

    /// Whether ID3v2.2 whole-tag unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 encrypted-meta (`CRM`) frame.

The encrypted datablock remains opaque. In particular, a successful result
does not imply that the block can be decrypted or that it contains valid
nested ID3v2 frames.

An empty owner identifier is rejected in strict decoding because the v2.2
specification explicitly directs decoders to ignore/remove such a frame.

Duplicate-owner rules belong to tag-level validation.
+/
ParseResult!Id3v22EncryptedMetaFrame
decodeId3v22EncryptedMetaFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "CRM"
    )
    {
        return
            ParseResult!Id3v22EncryptedMetaFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );

    auto ownerSegmentResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (ownerSegmentResult.hasError)
    {
        return
            ParseResult!Id3v22EncryptedMetaFrame
                .failure(
                    ownerSegmentResult.error
                );
    }

    const ownerSegment =
        ownerSegmentResult.value;

    auto ownerResult =
        decodeId3v22TextSpan(
            ownerSegment.raw,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (ownerResult.hasError)
    {
        return
            ParseResult!Id3v22EncryptedMetaFrame
                .failure(
                    ownerResult.error
                );
    }

    if (
        ownerResult.value.length ==
        0
    )
    {
        return
            ParseResult!Id3v22EncryptedMetaFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        ownerSegment.terminatorSourceOffset,
                        1,
                        0
                    )
                );
    }

    auto explanationSegmentResult =
        payload.takeId3v22TerminatedTextSegment(
            Id3v22TextEncoding.latin1
        );

    if (explanationSegmentResult.hasError)
    {
        return
            ParseResult!Id3v22EncryptedMetaFrame
                .failure(
                    explanationSegmentResult.error
                );
    }

    const explanationSegment =
        explanationSegmentResult.value;

    auto explanationResult =
        decodeId3v22TextSpan(
            explanationSegment.raw,
            Id3v22TextEncoding.latin1,
            tagUnsynchronised
        );

    if (explanationResult.hasError)
    {
        return
            ParseResult!Id3v22EncryptedMetaFrame
                .failure(
                    explanationResult.error
                );
    }

    const rawEncryptedData =
        payload.remainingRaw;

    const consumedLogical =
        ownerSegment.logicalLength +
        1 +
        explanationSegment.logicalLength +
        1;

    assert(
        frame.header.size >=
        consumedLogical
    );

    const logicalEncryptedDataLength =
        cast(size_t) frame.header.size -
        consumedLogical;

    return
        ParseResult!Id3v22EncryptedMetaFrame
            .success(
                Id3v22EncryptedMetaFrame(
                    frame.header.sourceOffset,
                    ownerResult.value,
                    ownerSegment.raw,
                    ownerSegment.terminatorSourceOffset,
                    explanationResult.value,
                    explanationSegment.raw,
                    explanationSegment.terminatorSourceOffset,
                    rawEncryptedData,
                    logicalEncryptedDataLength,
                    tagUnsynchronised
                )
            );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}


/// Ordinary CRM metadata decodes while ciphertext remains opaque.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'M',
            0x00, 0x00, 0x12,

            'o', 'w', 'n', 'e', 'r',
            0x00,

            'p', 'r', 'e', 'm', 'i', 'u', 'm',
            0x00,

            0xDE, 0xAD, 0xBE, 0xEF
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame();

    assert(result.hasValue);

    const encrypted =
        result.value;

    assert(encrypted.sourceOffset == 100);
    assert(encrypted.ownerIdentifier == "owner");
    assert(encrypted.ownerTerminatorSourceOffset == 111);
    assert(encrypted.contentExplanation == "premium");
    assert(encrypted.contentExplanationTerminatorSourceOffset == 119);
    assert(encrypted.logicalEncryptedDataLength == 4);

    assert(
        encrypted.rawEncryptedData.data ==
        [
            0xDE, 0xAD, 0xBE, 0xEF
        ]
    );

    assert(encrypted.rawEncryptedData.sourceOffset == 120);
    assert(!encrypted.effectiveUnsynchronisation);
}


/// Empty explanation and empty encrypted block remain structurally representable.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'M',
            0x00, 0x00, 0x03,

            'x',
            0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                200
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame();

    assert(result.hasValue);
    assert(result.value.ownerIdentifier == "x");
    assert(result.value.contentExplanation.length == 0);
    assert(result.value.rawContentExplanation.empty);
    assert(result.value.rawEncryptedData.empty);
    assert(result.value.logicalEncryptedDataLength == 0);
}


/// Empty owner follows the v2.2 ignore/remove rule and is rejected strictly.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'M',
            0x00, 0x00, 0x02,

            0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 306);
}


/// Missing owner terminator is a bounded pattern failure.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'M',
            0x00, 0x00, 0x05,

            'o', 'w', 'n', 'e', 'r'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
}


/// Missing content/explanation terminator is rejected.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'M',
            0x00, 0x00, 0x05,

            'x',
            0x00,
            'w', 'h', 'y'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
}


/// Whole-tag unsynchronisation preserves ciphertext physical provenance.
unittest
{
    /*
     * Logical payload:
     *
     *   x 00
     *   why 00
     *   FF E1 55
     *
     * Physical ciphertext:
     *
     *   FF 00 E1 55
     */
    const ubyte[] bytes =
        [
            'C', 'R', 'M',
            0x00, 0x00, 0x09,

            'x',
            0x00,

            'w', 'h', 'y',
            0x00,

            0xFF, 0x00, 0xE1,
            0x55
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                600
            ),
            true
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 9);
    assert(frame.value.data.length == 10);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame(
                true
            );

    assert(result.hasValue);
    assert(result.value.ownerIdentifier == "x");
    assert(result.value.contentExplanation == "why");
    assert(result.value.logicalEncryptedDataLength == 3);
    assert(result.value.rawEncryptedData.length == 4);
    assert(result.value.effectiveUnsynchronisation);

    assert(
        result.value.rawEncryptedData.data ==
        [
            0xFF, 0x00, 0xE1, 0x55
        ]
    );
}


/// CRM rejects another native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x03,
            'x',
            0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );

    auto frame =
        cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value
            .decodeId3v22EncryptedMetaFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 800);
}
