/++
ID3v2.4 frame-data structural partitioning.

This module separates the already bounded physical frame-data region
into optional frame-format fields and the remaining semantic payload.

Reads operate on the logical byte stream so tag-level or frame-level
unsynchronisation is reversed while format fields are parsed. The
remaining payload itself stays as a raw physical `ByteSpan`; its
effective unsynchronisation state is retained for later semantic
decoders.

No decryption, decompression or semantic frame decoding is performed
here.
+/
module audiotag.id3v2.v24.frame_data;

import audiotag.core.error : ParseError, ParseErrorCode;
import audiotag.core.result : ParseResult;
import audiotag.core.span : ByteSpan;
import audiotag.id3v2.v24.data_cursor : Id3v24DataCursor;
import audiotag.id3v2.v24.frame : Id3v24FrameEnvelope;


/++
Structural layout of one ID3v2.4 frame-data region.

Optional field values are meaningful only when their corresponding
`has...` property is true.

`rawPayload` preserves the physical source representation. When
`effectiveUnsynchronisation` is true, later decoders must traverse
that span through `Id3v24DataCursor` rather than interpreting the raw
bytes directly.
+/
struct Id3v24FrameDataLayout
{
    /// Whether tag-level or frame-level unsynchronisation applies.
    bool effectiveUnsynchronisation;

    /// Whether a grouping-identity byte was present.
    bool hasGroupingIdentity;

    /// Logical grouping-identity value when present.
    ubyte groupingIdentity;

    /// Physical source offset of the grouping byte when present.
    size_t groupingIdentityOffset;

    /// Whether an encryption-method byte was present.
    bool hasEncryptionMethod;

    /// Logical encryption-method value when present.
    ubyte encryptionMethod;

    /// Physical source offset of the encryption-method byte.
    size_t encryptionMethodOffset;

    /// Whether a Data Length Indicator was present.
    bool hasDataLengthIndicator;

    /// Decoded 28-bit Data Length Indicator value.
    uint dataLengthIndicator;

    /// Physical source offset of the first DLI byte.
    size_t dataLengthIndicatorOffset;

    /// Remaining physical frame bytes after all format fields.
    ByteSpan rawPayload;

    /++
    Constructs a logical cursor over the remaining semantic payload.

    The cursor automatically applies the same effective
    unsynchronisation state that was used while parsing the frame
    format fields.
    +/
    Id3v24DataCursor payloadCursor() const
        @safe pure nothrow @nogc
    {
        return Id3v24DataCursor(
            rawPayload,
            effectiveUnsynchronisation
        );
    }
}


/++
Partitions one bounded ID3v2.4 frame-data region.

`tagUnsynchronised` is the unsynchronisation flag from the enclosing
ID3v2.4 tag header. Effective unsynchronisation applies when either
that flag or the frame-level flag is set.

ID3v2.4 frame-format additions are consumed as follows:

- grouping identity, when present;
- Data Length Indicator before encryption when compression is set;
- encryption method, when present;
- Data Length Indicator after encryption when present without
  compression.

Compression itself adds no bytes beyond requiring a Data Length
Indicator. Decryption, decompression and semantic decoding are later
stages.

Params:
    frame = Previously validated and bounded ID3v2.4 frame.
    tagUnsynchronised = Whether the enclosing tag declares global
        frame unsynchronisation.

Returns:
    The structural frame-data layout or a structured parse error.
+/
ParseResult!Id3v24FrameDataLayout parseId3v24FrameDataLayout(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    if (
        frame.header.compressed &&
        !frame.header.hasDataLengthIndicator
    )
    {
        return ParseResult!Id3v24FrameDataLayout.failure(
            ParseError(
                ParseErrorCode.inconsistentStructure,
                frame.header.sourceOffset + 9
            )
        );
    }

    const effectiveUnsynchronisation =
        tagUnsynchronised ||
        frame.header.unsynchronised;

    auto cursor =
        Id3v24DataCursor(
            frame.data,
            effectiveUnsynchronisation
        );

    bool hasGroupingIdentity = false;
    ubyte groupingIdentity = 0;
    size_t groupingIdentityOffset = 0;

    bool hasEncryptionMethod = false;
    ubyte encryptionMethod = 0;
    size_t encryptionMethodOffset = 0;

    bool hasDataLengthIndicator = false;
    uint dataLengthIndicator = 0;
    size_t dataLengthIndicatorOffset = 0;

    if (frame.header.hasGroupingIdentity)
    {
        auto result = cursor.takeByte();

        if (result.hasError)
        {
            return ParseResult!Id3v24FrameDataLayout.failure(
                result.error
            );
        }

        hasGroupingIdentity = true;
        groupingIdentity = result.value.value;
        groupingIdentityOffset =
            result.value.sourceOffset;
    }

    // Compression requires the DLI. The specification explicitly
    // places the decompressed-size field before an encryption-method
    // byte, so in this case the DLI is consumed here.
    if (frame.header.compressed)
    {
        dataLengthIndicatorOffset =
            cursor.absoluteOffset;

        auto result =
            cursor.takeSynchsafe32();

        if (result.hasError)
        {
            return ParseResult!Id3v24FrameDataLayout.failure(
                result.error
            );
        }

        hasDataLengthIndicator = true;
        dataLengthIndicator = result.value;
    }

    if (frame.header.encrypted)
    {
        auto result = cursor.takeByte();

        if (result.hasError)
        {
            return ParseResult!Id3v24FrameDataLayout.failure(
                result.error
            );
        }

        hasEncryptionMethod = true;
        encryptionMethod = result.value.value;
        encryptionMethodOffset =
            result.value.sourceOffset;
    }

    // Without compression the DLI is the independent `p` field and
    // therefore follows the earlier encryption flag.
    if (
        frame.header.hasDataLengthIndicator &&
        !frame.header.compressed
    )
    {
        dataLengthIndicatorOffset =
            cursor.absoluteOffset;

        auto result =
            cursor.takeSynchsafe32();

        if (result.hasError)
        {
            return ParseResult!Id3v24FrameDataLayout.failure(
                result.error
            );
        }

        hasDataLengthIndicator = true;
        dataLengthIndicator = result.value;
    }

    const layout = Id3v24FrameDataLayout(
        effectiveUnsynchronisation,

        hasGroupingIdentity,
        groupingIdentity,
        groupingIdentityOffset,

        hasEncryptionMethod,
        encryptionMethod,
        encryptionMethodOffset,

        hasDataLengthIndicator,
        dataLengthIndicator,
        dataLengthIndicatorOffset,

        cursor.remainingRaw
    );

    return ParseResult!Id3v24FrameDataLayout.success(layout);
}


import audiotag.core.cursor : ByteCursor;
import audiotag.id3v2.v24.frame : parseId3v24FrameEnvelope;


/// Without format flags, the complete frame data remains payload.
unittest
{
    const ubyte[] bytes =
        ['T', 'I', 'T', '2',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x00,

         0x11, 0x22, 0x33];

    auto cursor = ByteCursor(ByteSpan(bytes, 100));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(!layout.effectiveUnsynchronisation);
    assert(!layout.hasGroupingIdentity);
    assert(!layout.hasEncryptionMethod);
    assert(!layout.hasDataLengthIndicator);

    assert(layout.rawPayload.sourceOffset == 110);
    assert(layout.rawPayload.length == 3);
    assert(
        layout.rawPayload.data ==
        [0x11, 0x22, 0x33]
    );
}


/// Grouping identity is removed from the semantic payload.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x40,

         0x12,
         0xAA, 0xBB];

    auto cursor = ByteCursor(ByteSpan(bytes, 200));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(layout.hasGroupingIdentity);
    assert(layout.groupingIdentity == 0x12);
    assert(layout.groupingIdentityOffset == 210);

    assert(layout.rawPayload.sourceOffset == 211);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// Frame-level unsynchronisation applies while reading format fields.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x42,

         // Logical grouping ID $FF, physical stuffing zero,
         // then one payload byte.
         0xFF, 0x00,
         0xE1];

    auto cursor = ByteCursor(ByteSpan(bytes, 300));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(layout.effectiveUnsynchronisation);
    assert(layout.groupingIdentity == 0xFF);
    assert(layout.groupingIdentityOffset == 310);

    assert(layout.rawPayload.sourceOffset == 312);
    assert(layout.rawPayload.length == 1);
    assert(layout.rawPayload.data[0] == 0xE1);
}


/// Tag-level unsynchronisation has the same effect on frame data.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x40,

         0xFF, 0x00,
         0x42];

    auto cursor = ByteCursor(ByteSpan(bytes, 400));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout(true);

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(layout.effectiveUnsynchronisation);
    assert(layout.groupingIdentity == 0xFF);
    assert(layout.groupingIdentityOffset == 410);

    assert(layout.rawPayload.sourceOffset == 412);
    assert(layout.rawPayload.data == [0x42]);
}


/// Compression places its required DLI before the encryption method.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x08,
         0x00, 0x4D,

         // Grouping identity.
         0x12,

         // DLI = 2.
         0x00, 0x00, 0x00, 0x02,

         // Encryption method.
         0x34,

         // Opaque compressed/encrypted payload.
         0xAA, 0xBB];

    auto cursor = ByteCursor(ByteSpan(bytes, 500));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(layout.hasGroupingIdentity);
    assert(layout.groupingIdentity == 0x12);
    assert(layout.groupingIdentityOffset == 510);

    assert(layout.hasDataLengthIndicator);
    assert(layout.dataLengthIndicator == 2);
    assert(layout.dataLengthIndicatorOffset == 511);

    assert(layout.hasEncryptionMethod);
    assert(layout.encryptionMethod == 0x34);
    assert(layout.encryptionMethodOffset == 515);

    assert(layout.rawPayload.sourceOffset == 516);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// A DLI without compression follows the encryption-method field.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x07,
         0x00, 0x05,

         // Encryption method.
         0x23,

         // Independent DLI = 2.
         0x00, 0x00, 0x00, 0x02,

         0xAA, 0xBB];

    auto cursor = ByteCursor(ByteSpan(bytes, 600));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(layout.hasEncryptionMethod);
    assert(layout.encryptionMethod == 0x23);
    assert(layout.encryptionMethodOffset == 610);

    assert(layout.hasDataLengthIndicator);
    assert(layout.dataLengthIndicator == 2);
    assert(layout.dataLengthIndicatorOffset == 611);

    assert(layout.rawPayload.sourceOffset == 615);
    assert(layout.rawPayload.data == [0xAA, 0xBB]);
}


/// Truncated required DLI data fails at the physical frame boundary.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x09,

         0x00, 0x00, 0x00];

    auto cursor = ByteCursor(ByteSpan(bytes, 700));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasError);
    assert(
        layoutResult.error.code ==
        ParseErrorCode.endOfSpan
    );
    assert(layoutResult.error.offset == 713);
    assert(layoutResult.error.requested == 1);
    assert(layoutResult.error.available == 0);
}


/// Invalid DLI synchsafe bytes retain their physical source offset.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x05,
         0x00, 0x09,

         0x00, 0x00, 0x80, 0x01,
         0x55];

    auto cursor = ByteCursor(ByteSpan(bytes, 800));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasError);
    assert(
        layoutResult.error.code ==
        ParseErrorCode.invalidSynchsafeInteger
    );
    assert(layoutResult.error.offset == 812);
}


/// Format fields may consume all frame data at this structural layer.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x01,
         0x00, 0x04,

         0x23];

    auto cursor = ByteCursor(ByteSpan(bytes, 900));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    const layout = layoutResult.value;

    assert(layout.hasEncryptionMethod);
    assert(layout.encryptionMethod == 0x23);

    assert(layout.rawPayload.empty);
    assert(layout.rawPayload.sourceOffset == 911);
}


/// The payload cursor retains effective unsynchronisation semantics.
unittest
{
    const ubyte[] bytes =
        ['A', 'B', 'C', '1',
         0x00, 0x00, 0x00, 0x03,
         0x00, 0x02,

         0xFF, 0x00, 0xE1];

    auto cursor = ByteCursor(ByteSpan(bytes, 1000));

    auto frameResult =
        cursor.parseId3v24FrameEnvelope();

    assert(frameResult.hasValue);

    auto layoutResult =
        frameResult.value
            .parseId3v24FrameDataLayout();

    assert(layoutResult.hasValue);

    auto payload =
        layoutResult.value.payloadCursor();

    auto first = payload.takeByte();
    auto second = payload.takeByte();

    assert(first.hasValue);
    assert(first.value.value == 0xFF);
    assert(first.value.sourceOffset == 1010);

    assert(second.hasValue);
    assert(second.value.value == 0xE1);
    assert(second.value.sourceOffset == 1012);

    assert(payload.empty);
}
