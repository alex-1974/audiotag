/++
ID3v2.4 unique-file-identifier frame decoding.

A `UFID` frame contains:

- one non-empty, null-terminated ISO-8859-1 owner identifier;
- zero to 64 bytes of opaque identifier data.

The 64-byte limit applies to the logical identifier after ID3 byte
unsynchronisation has been removed. Physical identifier bytes are
preserved exactly as stored for provenance.

Compressed or encrypted frames remain structurally valid but cannot
yet be semantically decoded.
+/
module audiotag.id3v2.v24.unique_file_identifier;

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
Semantic availability of a unique-file-identifier frame.
+/
enum Id3v24UniqueFileIdentifierAvailability : ubyte
{
    decoded,
    requiresDecompression,
    requiresDecryption,
    requiresDecryptionAndDecompression
}


/++
Decoded ID3v2.4 `UFID` frame.
+/
struct Id3v24UniqueFileIdentifierFrame
{
    /// Absolute source offset of the frame header.
    size_t sourceOffset;

    /// Decoded non-empty owner identifier.
    string ownerIdentifier;

    /// Physical owner bytes excluding the null terminator.
    ByteSpan rawOwnerIdentifier;

    /// Physical identifier bytes extending to the frame boundary.
    ByteSpan rawIdentifier;

    /// Identifier length after byte unsynchronisation is removed.
    size_t logicalIdentifierLength;

    /// Whether ID3 byte unsynchronisation was effective.
    bool effectiveUnsynchronisation;
}


/++
Outcome of attempting semantic UFID decoding.
+/
struct Id3v24UniqueFileIdentifierOutcome
{
    Id3v24UniqueFileIdentifierAvailability availability;
    Id3v24UniqueFileIdentifierFrame uniqueFileIdentifier;
    ByteSpan rawPayload;

    @property
    bool decoded() const
        @safe pure nothrow @nogc
    {
        return
            availability ==
            Id3v24UniqueFileIdentifierAvailability.decoded;
    }
}


/++
Decodes an ID3v2.4 unique-file-identifier (`UFID`) frame.

The owner identifier is interpreted as ISO-8859-1 and must be
non-empty and null-terminated.

The opaque identifier may contain at most 64 logical bytes. The
physical representation may be longer when ID3 byte
unsynchronisation stuffing is present.

Compressed or encrypted frames return a successful transformation-
pending outcome.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether tag-level byte unsynchronisation applies.

Returns:
    Decoded or transformation-pending UFID outcome, or a structured
    parsing/text error.
+/
ParseResult!Id3v24UniqueFileIdentifierOutcome
decodeId3v24UniqueFileIdentifierFrame(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "UFID")
    {
        return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
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
        return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
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
        Id3v24UniqueFileIdentifierAvailability availability;

        if (
            frame.header.compressed &&
            frame.header.encrypted
        )
        {
            availability =
                Id3v24UniqueFileIdentifierAvailability
                    .requiresDecryptionAndDecompression;
        }
        else if (frame.header.compressed)
        {
            availability =
                Id3v24UniqueFileIdentifierAvailability
                    .requiresDecompression;
        }
        else
        {
            availability =
                Id3v24UniqueFileIdentifierAvailability
                    .requiresDecryption;
        }

        return ParseResult!Id3v24UniqueFileIdentifierOutcome.success(
            Id3v24UniqueFileIdentifierOutcome(
                availability,
                Id3v24UniqueFileIdentifierFrame.init,
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
        return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
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
        return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
            owner.error
        );
    }

    if (owner.value.length == 0)
    {
        return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
            ParseError(
                ParseErrorCode.invalidLength,
                ownerSegment.terminatorSourceOffset,
                1,
                0
            )
        );
    }

    const rawIdentifier =
        payload.remainingRaw;

    auto identifierCursor =
        payload;

    size_t logicalIdentifierLength;

    while (!identifierCursor.empty)
    {
        auto byteResult =
            identifierCursor.takeByte();

        if (byteResult.hasError)
        {
            return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
                byteResult.error
            );
        }

        ++logicalIdentifierLength;

        if (logicalIdentifierLength > 64)
        {
            return ParseResult!Id3v24UniqueFileIdentifierOutcome.failure(
                ParseError(
                    ParseErrorCode.invalidLength,
                    byteResult.value.sourceOffset,
                    logicalIdentifierLength,
                    64
                )
            );
        }
    }

    auto uniqueFileIdentifier =
        Id3v24UniqueFileIdentifierFrame(
            frame.header.sourceOffset,
            owner.value,
            ownerSegment.raw,
            rawIdentifier,
            logicalIdentifierLength,
            layout.effectiveUnsynchronisation
        );

    return ParseResult!Id3v24UniqueFileIdentifierOutcome.success(
        Id3v24UniqueFileIdentifierOutcome(
            Id3v24UniqueFileIdentifierAvailability.decoded,
            uniqueFileIdentifier,
            layout.rawPayload
        )
    );
}


import audiotag.core.cursor :
    ByteCursor;

import audiotag.id3v2.v24.frame :
    parseId3v24FrameEnvelope;


/// A normal UFID frame preserves owner and binary identifier.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x11,
            0x00, 0x00,

            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'o', 'r', 'g',
            0x00,

            0x01, 0x02, 0xFE, 0xFF, 0x10
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 100));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(identifier.sourceOffset == 100);
    assert(identifier.ownerIdentifier == "example.org");

    assert(
        identifier.rawOwnerIdentifier.sourceOffset ==
        110
    );

    assert(
        identifier.rawOwnerIdentifier.data ==
        [
            'e', 'x', 'a', 'm', 'p', 'l', 'e',
            '.', 'o', 'r', 'g'
        ]
    );

    assert(identifier.rawIdentifier.sourceOffset == 122);

    assert(
        identifier.rawIdentifier.data ==
        [0x01, 0x02, 0xFE, 0xFF, 0x10]
    );

    assert(identifier.logicalIdentifierLength == 5);
    assert(!identifier.effectiveUnsynchronisation);
}


/// An empty binary identifier is valid.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
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
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(identifier.ownerIdentifier == "x");
    assert(identifier.rawIdentifier.length == 0);
    assert(identifier.logicalIdentifierLength == 0);
}


/// The owner identifier must not be empty.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 300));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 310);
    assert(result.error.requested == 1);
    assert(result.error.available == 0);
}


/// Exactly 64 identifier bytes are valid.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x42,
            0x00, 0x00,

            'x',
            0x00
        ];

    foreach (i; 0 .. 64)
        bytes ~= cast(ubyte) i;

    auto cursor =
        ByteCursor(ByteSpan(bytes, 400));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    assert(
        result.value.uniqueFileIdentifier
            .logicalIdentifierLength == 64
    );

    assert(
        result.value.uniqueFileIdentifier
            .rawIdentifier.length == 64
    );
}


/// A 65-byte logical identifier is rejected at its first excess byte.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x43,
            0x00, 0x00,

            'x',
            0x00
        ];

    foreach (i; 0 .. 65)
        bytes ~= cast(ubyte) i;

    auto cursor =
        ByteCursor(ByteSpan(bytes, 500));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidLength
    );

    assert(result.error.offset == 576);
    assert(result.error.requested == 65);
    assert(result.error.available == 64);
}


/// The 64-byte limit applies after unsynchronisation removal.
unittest
{
    ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x43,
            0x00, 0x02,

            'x',
            0x00,

            0xFF, 0x00
        ];

    foreach (_; 0 .. 63)
        bytes ~= 0x11;

    auto cursor =
        ByteCursor(ByteSpan(bytes, 600));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(result.value.decoded);

    const identifier =
        result.value.uniqueFileIdentifier;

    assert(identifier.effectiveUnsynchronisation);
    assert(identifier.logicalIdentifierLength == 64);

    // One unsynchronisation stuffing byte remains in provenance.
    assert(identifier.rawIdentifier.length == 65);

    assert(
        identifier.rawIdentifier.data[0 .. 2] ==
        [0xFF, 0x00]
    );
}


/// The owner identifier must be terminated inside the frame.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x00,

            'a', 'b', 'c'
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 700));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.patternNotFound
    );
}


/// The UFID codec rejects another frame identifier.
unittest
{
    const ubyte[] bytes =
        [
            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x00
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 800));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidSignature
    );

    assert(result.error.offset == 800);
}


/// Compressed UFID data remains valid but pending transformation.
unittest
{
    const ubyte[] bytes =
        [
            'U', 'F', 'I', 'D',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            0x00, 0x00, 0x00, 0x01,
            0xAA
        ];

    auto cursor =
        ByteCursor(ByteSpan(bytes, 900));

    auto frame =
        cursor.parseId3v24FrameEnvelope();

    assert(frame.hasValue);

    auto result =
        frame.value.decodeId3v24UniqueFileIdentifierFrame();

    assert(result.hasValue);
    assert(!result.value.decoded);

    assert(
        result.value.availability ==
        Id3v24UniqueFileIdentifierAvailability
            .requiresDecompression
    );

    assert(result.value.rawPayload.data == [0xAA]);
}
