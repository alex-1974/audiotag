/++
ID3v2.4 private-frame decoding.

A `PRIV` frame contains:

- one null-terminated ISO-8859-1 owner identifier;
- private binary data extending to the frame boundary.

The binary payload is preserved exactly as stored. Effective ID3 byte
unsynchronisation is retained separately so callers can later obtain
the logical byte stream without losing physical provenance.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.private_frame;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_data :
    parseId3v24FrameDataLayout;

import audiotag.id3v2.v24.text_decode :
    decodeId3v24TextSpan;

import audiotag.id3v2.v24.text_encoding :
    Id3v24TextEncoding;

import audiotag.id3v2.v24.text_segment :
    takeId3v24TerminatedTextSegment;


/++
Semantic availability of a private frame.
+/
enum Id3v24PrivateAvailability : ubyte
{
    decoded,
    requiresDecompression,
    requiresDecryption,
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.4 `PRIV` frame.
+/
struct Id3v24PrivateFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Decoded owner identifier.
    string ownerIdentifier;

    /// Physical owner bytes excluding the null terminator.
    ByteSpan rawOwnerIdentifier;

    /// Physical private data extending to the frame boundary.
    ByteSpan rawPrivateData;

    /// Whether ID3 byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic PRIV decoding.
+/
struct Id3v24PrivateOutcome
{
    Id3v24PrivateAvailability availability;
    Id3v24PrivateFrame privateFrame;
    ByteSpan rawPayload;

    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return availability == Id3v24PrivateAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 private (`PRIV`) frame.

The owner identifier is interpreted as ISO-8859-1 and must be
null-terminated. All bytes after the terminator belong to the private
binary payload and are preserved exactly as stored.

Compressed or encrypted frames return a successful transformation-
pending outcome.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level byte unsynchronisation applies.

Returns:
    Decoded or transformation-pending PRIV outcome, or a structured
    parsing/text error.
+/
ParseResult!Id3v24PrivateOutcome
decodeId3v24PrivateFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "PRIV")
    {
        return ParseResult!Id3v24PrivateOutcome.failure(
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
        return ParseResult!Id3v24PrivateOutcome.failure(
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
        Id3v24PrivateAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24PrivateAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24PrivateAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24PrivateAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24PrivateOutcome.success(
            Id3v24PrivateOutcome(
                availability,
                Id3v24PrivateFrame.init,
                layout.rawPayload
            )
        );
    }

    auto payload =
        layout.payloadCursor();

    auto ownerResult =
        payload.takeId3v24TerminatedTextSegment(
            Id3v24TextEncoding.latin1
        );

    if (ownerResult.hasError)
    {
        return ParseResult!Id3v24PrivateOutcome.failure(
            ownerResult.error
        );
    }

    const ownerSegment =
        ownerResult.value;

    auto owner =
        decodeId3v24TextSpan(
            ownerSegment.raw,
            Id3v24TextEncoding.latin1,
            layout.effectiveUnsynchronisation
        );

    if (owner.hasError)
    {
        return ParseResult!Id3v24PrivateOutcome.failure(
            owner.error
        );
    }

    const rawPrivateData =
        payload.remainingRaw;

    auto privateFrame =
        Id3v24PrivateFrame(
            frame.header.sourceOffset,
            owner.value,
            ownerSegment.raw,
            rawPrivateData,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24PrivateOutcome.success(
        Id3v24PrivateOutcome(
            Id3v24PrivateAvailability.decoded,
            privateFrame,
            layout.rawPayload
        )
    );
}


import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A normal PRIV frame preserves owner and binary data.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x10,
            0x00, 0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm',
            0x00,

            0x01, 0x02, 0xFE, 0xFF
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const privateFrame =
        result.value.privateFrame;

    assert(privateFrame.sourceOffset == 100);
    assert(privateFrame.ownerIdentifier == "example.com");

    assert(
        privateFrame.rawOwnerIdentifier.sourceOffset ==
        110
    );

    assert(
        privateFrame.rawOwnerIdentifier.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'c', 'o', 'm'
        ]
    );

    assert(
        privateFrame.rawPrivateData.sourceOffset ==
        122
    );

    assert(
        privateFrame.rawPrivateData.data ==
        [0x01, 0x02, 0xFE, 0xFF]
    );

    assert(!privateFrame.effectiveUnsynchronisation);
}


/// Empty private data is valid.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            'x',
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 200));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.privateFrame.ownerIdentifier ==
        "x"
    );

    assert(
        result.value.privateFrame.rawPrivateData.length ==
        0
    );
}


/// The owner identifier must be terminated inside the frame.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24PrivateFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The PRIV codec rejects another frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24PrivateFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 400);
}


/// Compressed private data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24PrivateFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24PrivateAvailability
            .requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}


/// Physical private-data provenance retains unsynchronisation stuffing.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x02,

            'x',
            0x00,

            0xFF, 0x00, 0xE0
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24PrivateFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const privateFrame =
        result.value.privateFrame;

    assert(privateFrame.effectiveUnsynchronisation);

    assert(
        privateFrame.rawPrivateData.data ==
        [0xFF, 0x00, 0xE0]
    );
}
