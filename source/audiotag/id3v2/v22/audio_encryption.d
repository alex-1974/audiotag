/++
ID3v2.2 audio-encryption (`CRA`) frame decoding.

The logical payload contains:

- a null-terminated owner identifier;
- preview start as unsigned 16-bit big-endian audio-frame count;
- preview length as unsigned 16-bit big-endian audio-frame count;
- optional opaque encryption-specific data.

ID3v2.2 does not carry a text-encoding marker in this frame. The owner
identifier is therefore decoded as the single-byte legacy text used by its
v2.3/v2.4 `AENC` successor.

An empty owner identifier is retained rather than rejected. The v2.2
specification says that an encrypted audio file with an empty owner may be
considered useless, but does not define that byte sequence as structurally
malformed.

No cryptographic algorithm is selected or executed by this codec.

Whole-tag unsynchronisation is reversed during logical traversal. Raw spans
retain the exact physical source representation, including inserted stuffing
bytes.

This module performs no canonical metadata mapping.

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
module audiotag.id3v2.v22.audio_encryption;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.audio_encryption :
    Id3v2AudioEncryptionMetadata;

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
Decoded native ID3v2.2 `CRA` frame.
+/
struct Id3v22AudioEncryptionFrame
{
    size_t sourceOffset;

    Id3v2AudioEncryptionMetadata metadata;

    /// Physical owner bytes excluding the terminating logical zero.
    ByteSpan rawOwnerIdentifier;

    /// Physical source offset of the owner terminator.
    size_t ownerTerminatorSourceOffset;

    /// Physical bytes corresponding to the two logical preview-start bytes.
    ByteSpan rawPreviewStart;

    /// Physical bytes corresponding to the two logical preview-length bytes.
    ByteSpan rawPreviewLength;

    /// Exact physical encryption-specific tail.
    ByteSpan rawEncryptionInfo;

    /// Logical byte length of `rawEncryptionInfo`.
    size_t logicalEncryptionInfoLength;

    bool effectiveUnsynchronisation;
}


/++
Decodes one ID3v2.2 audio-encryption (`CRA`) frame.

The frame is only described. `rawEncryptionInfo` is never interpreted,
decrypted, copied into a plugin, or executed.

Duplicate-owner rules belong to tag-level validation.
+/
ParseResult!Id3v22AudioEncryptionFrame
decodeId3v22AudioEncryptionFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (
        frame.header.id[] !=
        "CRA"
    )
    {
        return
            ParseResult!Id3v22AudioEncryptionFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    /*
     * Empty owner + terminator + two U16 values is the smallest complete
     * structure allowed by the field grammar.
     */
    if (frame.header.size < 5)
    {
        return
            ParseResult!Id3v22AudioEncryptionFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset,
                        5,
                        frame.header.size
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
            ParseResult!Id3v22AudioEncryptionFrame
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
            ParseResult!Id3v22AudioEncryptionFrame
                .failure(
                    ownerResult.error
                );
    }

    const previewStartRaw =
        payload.remainingRaw;

    auto previewStartResult =
        payload.takeU16BE();

    if (previewStartResult.hasError)
    {
        return
            ParseResult!Id3v22AudioEncryptionFrame
                .failure(
                    previewStartResult.error
                );
    }

    const rawPreviewStart =
        previewStartRaw.subspan(
            0,
            previewStartRaw.length -
                payload.remainingRaw.length
        );

    const previewLengthRaw =
        payload.remainingRaw;

    auto previewLengthResult =
        payload.takeU16BE();

    if (previewLengthResult.hasError)
    {
        return
            ParseResult!Id3v22AudioEncryptionFrame
                .failure(
                    previewLengthResult.error
                );
    }

    const rawPreviewLength =
        previewLengthRaw.subspan(
            0,
            previewLengthRaw.length -
                payload.remainingRaw.length
        );

    const rawEncryptionInfo =
        payload.remainingRaw;

    const consumedLogical =
        ownerSegment.logicalLength +
        1 +
        2 +
        2;

    if (
        consumedLogical >
        frame.header.size
    )
    {
        return
            ParseResult!Id3v22AudioEncryptionFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset,
                        consumedLogical,
                        frame.header.size
                    )
                );
    }

    const logicalEncryptionInfoLength =
        cast(size_t) frame.header.size -
        consumedLogical;

    return
        ParseResult!Id3v22AudioEncryptionFrame
            .success(
                Id3v22AudioEncryptionFrame(
                    frame.header.sourceOffset,
                    Id3v2AudioEncryptionMetadata(
                        ownerResult.value,
                        previewStartResult.value,
                        previewLengthResult.value
                    ),
                    ownerSegment.raw,
                    ownerSegment.terminatorSourceOffset,
                    rawPreviewStart,
                    rawPreviewLength,
                    rawEncryptionInfo,
                    logicalEncryptionInfoLength,
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


/// Ordinary CRA metadata and opaque encryption info decode correctly.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x0F,

            'o', 'w', 'n', 'e', 'r',
            0x00,

            0x00, 0x78,
            0x00, 0xF0,

            0xDE, 0xAD, 0xBE, 0xEF, 0x01
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

    auto result =
        frame.value
            .decodeId3v22AudioEncryptionFrame();

    assert(result.hasValue);

    const encryption =
        result.value;

    assert(encryption.sourceOffset == 100);
    assert(encryption.metadata.ownerIdentifier == "owner");
    assert(encryption.metadata.previewStartFrames == 120);
    assert(encryption.metadata.previewLengthFrames == 240);
    assert(encryption.ownerTerminatorSourceOffset == 111);
    assert(encryption.logicalEncryptionInfoLength == 5);

    assert(
        encryption.rawEncryptionInfo.data ==
        [
            0xDE, 0xAD, 0xBE, 0xEF, 0x01
        ]
    );

    assert(!encryption.effectiveUnsynchronisation);
}


/// Encryption-specific data is optional.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x06,

            'x',
            0x00,

            0x00, 0x00,
            0x00, 0x00
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
            .decodeId3v22AudioEncryptionFrame();

    assert(result.hasValue);
    assert(result.value.metadata.ownerIdentifier == "x");
    assert(result.value.metadata.previewStartFrames == 0);
    assert(result.value.metadata.previewLengthFrames == 0);
    assert(result.value.rawEncryptionInfo.empty);
    assert(result.value.logicalEncryptionInfoLength == 0);
}


/// An empty owner is structurally retained rather than rejected.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x05,

            0x00,
            0x00, 0x01,
            0x00, 0x02
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
            .decodeId3v22AudioEncryptionFrame();

    assert(result.hasValue);
    assert(result.value.metadata.ownerIdentifier.length == 0);
    assert(result.value.metadata.previewStartFrames == 1);
    assert(result.value.metadata.previewLengthFrames == 2);
}


/// Payloads too short for owner terminator plus both preview values fail.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x04,

            0x00,
            0x00, 0x01,
            0x00
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
            .decodeId3v22AudioEncryptionFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
}


/// An inconsistent caller-constructed envelope returns a structured error.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x06,

            'x',
            0x00,

            0x00, 0x00,
            0x00, 0x00
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto frameResult =
        cursor.parseId3v22FrameEnvelope();

    assert(frameResult.hasValue);

    auto frame =
        frameResult.value;

    /*
     * Preserve six physical/logical data bytes but forge the public envelope
     * metadata to claim only five. The decoder must report the inconsistency,
     * never terminate through an assertion.
     */
    frame.header.size = 5;

    auto result =
        frame.decodeId3v22AudioEncryptionFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.offset == 906);
}


/// A missing owner terminator is rejected as a bounded pattern failure.
unittest
{
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x07,

            'o', 'w', 'n',
            0x01, 0x02,
            0x03, 0x04
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
            .decodeId3v22AudioEncryptionFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.patternNotFound);
}


/// Whole-tag unsynchronisation is logical while all raw fields stay physical.
unittest
{
    /*
     * Logical payload:
     *
     *   x 00
     *   FF E1
     *   00 02
     *   FF E2
     *
     * Physical stuffing adds one zero after each FF.
     */
    const ubyte[] bytes =
        [
            'C', 'R', 'A',
            0x00, 0x00, 0x08,

            'x',
            0x00,

            0xFF, 0x00, 0xE1,
            0x00, 0x02,

            0xFF, 0x00, 0xE2
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
    assert(frame.value.header.size == 8);
    assert(frame.value.data.length == 10);
    assert(cursor.empty);

    auto result =
        frame.value
            .decodeId3v22AudioEncryptionFrame(
                true
            );

    assert(result.hasValue);

    assert(
        result.value.metadata.previewStartFrames ==
        0xFF_E1
    );

    assert(
        result.value.metadata.previewLengthFrames ==
        2
    );

    assert(result.value.logicalEncryptionInfoLength == 2);
    assert(result.value.rawPreviewStart.length == 3);
    assert(result.value.rawEncryptionInfo.length == 3);
    assert(result.value.effectiveUnsynchronisation);

    assert(
        result.value.rawEncryptionInfo.data ==
        [
            0xFF, 0x00, 0xE2
        ]
    );
}


/// CRA rejects another native frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'M', 'C', 'I',
            0x00, 0x00, 0x05,
            0x00,
            0x00, 0x01,
            0x00, 0x02
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
            .decodeId3v22AudioEncryptionFrame();

    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 800);
}
