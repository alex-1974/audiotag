/++
Complete native semantic representation of one ID3v2.2 tag.

The strict structural parser already distinguishes two valid body states:

- an uncompressed frame sequence with optional trailing padding;
- an opaque whole-tag-compressed body whose representation is not standardized
  by ID3v2.2.

This module preserves that distinction.

For an uncompressed structure, every validated frame is decoded through
`native_sequence.d` while the complete structural representation remains
attached to the result.

For a compressed structure, no semantic frame decoding is attempted. The exact
opaque physical body remains available as `structure.envelope.body`.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.native_tag;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v22.native_sequence :
    Id3v22NativeFrameSequence,
    decodeId3v22NativeFrameSequence;

import audiotag.id3v2.v22.structure :
    Id3v22TagStructure,
    parseId3v22TagStructure;


/++
Complete provenance-preserving native representation of one ID3v2.2 tag.

`structure` always contains the complete validated structural tag.

When `hasFrameSequence` is true, `sequence` contains every decoded native
frame in source order.

When `compressedOpaque` is true, `sequence` remains default-initialized and
must not be interpreted. The exact opaque physical tag body is retained in
`structure.envelope.body`.
+/
struct Id3v22NativeTag
{
    /// Complete validated structural tag representation.
    Id3v22TagStructure structure;

    /// Decoded native frame sequence for uncompressed tags only.
    Id3v22NativeFrameSequence sequence;


    /// Whether this tag contains a decoded native frame sequence.
    @property
    bool hasFrameSequence() const
        @safe pure nothrow @nogc
    {
        return
            structure.hasFrameSequence;
    }


    /// Whether this tag body is preserved as opaque whole-tag-compressed data.
    @property
    bool compressedOpaque() const
        @safe pure nothrow @nogc
    {
        return
            structure.compressedOpaque;
    }


    /++
    Number of decoded native frames.

    Preconditions:
        `hasFrameSequence` must be true.
    +/
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        assert(hasFrameSequence);

        return
            sequence.frameCount;
    }


    /// Absolute source offset immediately following the complete tag.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            structure.endOffset;
    }
}


/++
Decodes one already validated ID3v2.2 tag structure into its native semantic
representation.

Uncompressed frame sequences are decoded through
`decodeId3v22NativeFrameSequence`, with the enclosing tag's whole-tag
unsynchronisation state forwarded unchanged.

Whole-tag-compressed structures remain successful native tags, but no frame
semantics are guessed. Their exact physical body remains available through the
retained structural representation.

Params:
    structure = Complete validated ID3v2.2 tag structure.

Returns:
    Complete native tag representation or a semantic frame decoding error.
+/
ParseResult!Id3v22NativeTag
decodeId3v22TagStructureToNative(
    Id3v22TagStructure structure
)
    @safe
{
    if (
        structure.compressedOpaque
    )
    {
        return
            ParseResult!Id3v22NativeTag
                .success(
                    Id3v22NativeTag(
                        structure,
                        Id3v22NativeFrameSequence.init
                    )
                );
    }


    auto sequenceResult =
        decodeId3v22NativeFrameSequence(
            structure.frames,
            structure.envelope.header
                .unsynchronisation
        );


    if (
        sequenceResult.hasError
    )
    {
        return
            ParseResult!Id3v22NativeTag
                .failure(
                    sequenceResult.error
                );
    }


    return
        ParseResult!Id3v22NativeTag
            .success(
                Id3v22NativeTag(
                    structure,
                    sequenceResult.value
                )
            );
}


/++
Strictly parses and natively decodes one complete ID3v2.2 tag.

Structural parsing and semantic frame decoding form one transaction. The
caller's cursor is updated only when the complete operation succeeds.

A valid whole-tag-compressed body succeeds without semantic frame decoding and
is retained exactly as opaque physical bytes.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.2 tag.

Returns:
    Complete native tag representation or a structured parsing/semantic error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22NativeTag
parseId3v22NativeTag(
    ref ByteCursor cursor
)
    @safe
{
    auto probe =
        cursor;


    auto structureResult =
        probe.parseId3v22TagStructure();


    if (
        structureResult.hasError
    )
    {
        return
            ParseResult!Id3v22NativeTag
                .failure(
                    structureResult.error
                );
    }


    auto nativeResult =
        decodeId3v22TagStructureToNative(
            structureResult.value
        );


    if (
        nativeResult.hasError
    )
    {
        return
            ParseResult!Id3v22NativeTag
                .failure(
                    nativeResult.error
                );
    }


    cursor =
        probe;


    return nativeResult;
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.native_frame :
        Id3v22UnknownFrame;

    import audiotag.id3v2.v22.text_information :
        Id3v22TextInformationFrame;

    import audiotag.id3v2.v22.unique_file_identifier :
        Id3v22UniqueFileIdentifierFrame;
}


/// A complete uncompressed text tag exposes structural and native views.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            /*
             * One twelve-byte TT2 frame.
             */
            0x00, 0x00, 0x00, 0x0C,

            'T', 'T', '2',
            0x00, 0x00, 0x06,
            0x00,
            'T', 'i', 't', 'l', 'e',

            /*
             * Outside the tag.
             */
            0xAA
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );


    auto result =
        parseId3v22NativeTag(
            cursor
        );


    assert(result.hasValue);


    const tag =
        result.value;


    assert(tag.hasFrameSequence);
    assert(!tag.compressedOpaque);

    assert(tag.frameCount == 1);
    assert(tag.sequence.frameCount == 1);

    assert(
        tag.structure.envelope.header
            .sourceOffset ==
        100
    );

    assert(
        tag.structure.envelope.header
            .tagSize ==
        12
    );

    const titleDecoded =
        tag.sequence.frames[0]
            .content.match!(
                (Id3v22TextInformationFrame text) =>
                    text.id[] == "TT2" &&
                    text.value == "Title",

                _ =>
                    false
            );

    assert(titleDecoded);

    assert(tag.endOffset == 122);

    assert(cursor.absoluteOffset == 122);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0xAA);
}


/// Unknown frames remain native and provenance-preserving at whole-tag level.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x09,

            'Z', 'Z', 'Z',
            0x00, 0x00, 0x03,
            0x11, 0x22, 0x33
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );


    auto result =
        parseId3v22NativeTag(
            cursor
        );


    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.frameCount == 1);

    const unknown =
        tag.sequence.frames[0]
            .content.match!(
                (Id3v22UnknownFrame value) =>
                    true,

                _ =>
                    false
            );

    assert(unknown);

    assert(
        tag.sequence.frames[0]
            .envelope.header.id[] ==
        "ZZZ"
    );

    assert(
        tag.sequence.frames[0]
            .envelope.data.data ==
        [0x11, 0x22, 0x33]
    );
}


/// Trailing padding remains available in the retained structural/native layout.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            /*
             * Eight-byte TAL frame plus three bytes of padding.
             */
            0x00, 0x00, 0x00, 0x0B,

            'T', 'A', 'L',
            0x00, 0x00, 0x02,
            0x00,
            'A',

            0x00, 0x00, 0x00
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );


    auto result =
        parseId3v22NativeTag(
            cursor
        );


    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.frameCount == 1);

    assert(
        tag.structure.frames.padding.data ==
        [0x00, 0x00, 0x00]
    );

    assert(
        tag.sequence.layout.padding.data ==
        [0x00, 0x00, 0x00]
    );

    assert(tag.sequence.layout.padding.sourceOffset == 518);
}


/// Whole-tag unsynchronisation reaches every semantic frame decoder.
unittest
{
    /*
     * Logical UFI data:
     *
     *   x 00 FF E0
     *
     * Physical UFI data:
     *
     *   x 00 FF 00 E0
     *
     * The header frame size remains four logical bytes, while the tag-size
     * field counts the eleven physical body bytes.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x80,

            0x00, 0x00, 0x00, 0x0B,

            'U', 'F', 'I',
            0x00, 0x00, 0x04,

            'x',
            0x00,
            0xFF, 0x00,
            0xE0
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );


    auto result =
        parseId3v22NativeTag(
            cursor
        );


    assert(result.hasValue);

    const tag =
        result.value;

    assert(
        tag.structure.envelope.header
            .unsynchronisation
    );

    assert(tag.frameCount == 1);

    const preserved =
        tag.sequence.frames[0]
            .content.match!(
                (Id3v22UniqueFileIdentifierFrame identifier) =>
                    identifier.effectiveUnsynchronisation &&
                    identifier.ownerIdentifier == "x" &&
                    identifier.logicalIdentifierLength == 2 &&
                    identifier.rawIdentifier.data ==
                        [
                            0xFF, 0x00,
                            0xE0
                        ],

                _ =>
                    false
            );

    assert(preserved);

    assert(tag.endOffset == 721);
}


/// Whole-tag compression remains a successful opaque native body.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x01,

            /*
             * Whole-tag compression.
             */
            0x40,

            0x00, 0x00, 0x00, 0x04,

            0xDE, 0xAD, 0xBE, 0xEF,

            /*
             * Outside the tag.
             */
            0x55
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );


    auto result =
        parseId3v22NativeTag(
            cursor
        );


    assert(result.hasValue);

    const tag =
        result.value;

    assert(!tag.hasFrameSequence);
    assert(tag.compressedOpaque);

    assert(
        tag.structure.envelope.body.data ==
        [0xDE, 0xAD, 0xBE, 0xEF]
    );

    assert(
        tag.structure.envelope.body.sourceOffset ==
        910
    );

    /*
     * No guessed frame interpretation is introduced for compressed bodies.
     */
    assert(tag.sequence.frames.length == 0);
    assert(tag.sequence.layout.frameCount == 0);

    assert(tag.endOffset == 914);

    assert(cursor.absoluteOffset == 914);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0x55);
}


/// A semantic failure leaves the caller's whole-tag cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            /*
             * One seven-byte TT2 frame.
             */
            0x00, 0x00, 0x00, 0x07,

            'T', 'T', '2',
            0x00, 0x00, 0x01,

            /*
             * Invalid ID3v2.2 text encoding marker.
             */
            0x02,

            0xAA
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1100
            )
        );


    auto result =
        parseId3v22NativeTag(
            cursor
        );


    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(result.error.offset == 1116);

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 1100);
    assert(cursor.remaining == bytes.length);
}
