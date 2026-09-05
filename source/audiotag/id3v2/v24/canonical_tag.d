/++
Whole-tag canonical projection for ID3v2.4.

The strict structural parser already provides the complete native tag
representation:

- validated tag envelope and header;
- bounded body;
- optional extended header;
- validated frame sequence;
- padding;
- optional footer.

This module does not duplicate that structural model. Instead it pairs
the existing `Id3v24TagStructure` with the provenance-preserving
canonical frame projection.

The resulting object therefore exposes both:

- the complete native structural representation needed for later
  roundtrip-aware writing;
- the format-independent canonical metadata view.

Semantic projection errors remain structured `ParseError` values.
The cursor-level parser is transactional across both structural parsing
and semantic projection.
+/
module audiotag.id3v2.v24.canonical_tag;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v24.canonical_projection :
    Id3v24CanonicalProjection;

import audiotag.id3v2.v24.canonical_sequence :
    projectId3v24FrameSequenceToCanonical;

import audiotag.id3v2.v24.structure :
    Id3v24TagStructure,
    parseId3v24TagStructure;


/++
Complete native-plus-canonical representation of one ID3v2.4 tag.

`structure` retains the complete validated structural tag view.

`projection` retains every native semantic frame in source order while
also exposing mapped canonical metadata.
+/
struct Id3v24CanonicalTag
{
    /// Complete validated native tag structure.
    Id3v24TagStructure structure;

    /// Provenance-preserving canonical frame projection.
    Id3v24CanonicalProjection projection;

    /++
    Returns the number of structurally validated native frames.
    +/
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        return structure.frameCount;
    }

    /++
    Returns the absolute source offset immediately following the tag.
    +/
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return structure.endOffset;
    }
}


/++
Projects one already validated ID3v2.4 tag structure into canonical
metadata.

The structural representation is retained unchanged. Tag-level
unsynchronisation from the validated header is forwarded to semantic
frame decoding.

Params:
    structure = Complete validated ID3v2.4 tag structure.

Returns:
    Native-plus-canonical tag representation, or a semantic codec error.
+/
ParseResult!Id3v24CanonicalTag
projectId3v24TagStructureToCanonical(
    Id3v24TagStructure structure
)
    @safe
{
    auto projectionResult =
        projectId3v24FrameSequenceToCanonical(
            structure.frames,
            structure.envelope.header
                .unsynchronisation
        );

    if (projectionResult.hasError)
    {
        return
            ParseResult!Id3v24CanonicalTag
                .failure(
                    projectionResult.error
                );
    }

    return
        ParseResult!Id3v24CanonicalTag
            .success(
                Id3v24CanonicalTag(
                    structure,
                    projectionResult.value
                )
            );
}


/++
Strictly parses and canonically projects one complete ID3v2.4 tag.

Both structural parsing and semantic projection form one transaction.
The caller's cursor is updated only when the complete native structure
and canonical projection both succeed.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.4 tag.

Returns:
    Complete native-plus-canonical tag representation, or a structured
    parsing/semantic error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v24CanonicalTag
parseId3v24CanonicalTag(
    ref ByteCursor cursor
)
    @safe
{
    auto probe =
        cursor;

    auto structureResult =
        probe.parseId3v24TagStructure();

    if (structureResult.hasError)
    {
        return
            ParseResult!Id3v24CanonicalTag
                .failure(
                    structureResult.error
                );
    }

    auto canonicalResult =
        projectId3v24TagStructureToCanonical(
            structureResult.value
        );

    if (canonicalResult.hasError)
    {
        return
            ParseResult!Id3v24CanonicalTag
                .failure(
                    canonicalResult.error
                );
    }

    cursor =
        probe;

    return canonicalResult;
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.canonical_mapping :
        Id3v24CanonicalMappingStatus;

    import audiotag.metadata.value :
        MetadataBinary;
}


/// A complete text tag exposes both structural and canonical views.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x10,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x03,
            'T', 'i', 't', 'l', 'e',

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
        parseId3v24CanonicalTag(
            cursor
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.structure.envelope.header.sourceOffset == 100);
    assert(tag.structure.envelope.header.tagSize == 16);

    assert(tag.frameCount == 1);
    assert(tag.projection.frameCount == 1);

    assert(tag.projection.metadata.length == 1);

    assert(
        tag.projection.metadata[0].key.name ==
        "title"
    );

    assert(
        tag.projection.frames[0].status ==
        Id3v24CanonicalMappingStatus.mapped
    );

    assert(tag.endOffset == 126);

    assert(cursor.absoluteOffset == 126);
    assert(cursor.remaining == 1);
    assert(cursor.front == 0xAA);
}


/// Unknown frames survive whole-tag projection without canonical loss.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0B,

            'A', 'B', 'C', 'D',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00,
            0x55
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto result =
        parseId3v24CanonicalTag(
            cursor
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.frameCount == 1);
    assert(tag.projection.frameCount == 1);

    assert(tag.projection.metadata.empty);

    assert(
        tag.projection.frames[0].status ==
        Id3v24CanonicalMappingStatus
            .unsupportedFrame
    );

    assert(
        tag.projection.frames[0]
            .native.envelope.header.id[] ==
        "ABCD"
    );
}


/// Extended header and padding remain in the structural representation.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x40,
            0x00, 0x00, 0x00, 0x15,

            // Minimal six-byte extended header.
            0x00, 0x00, 0x00, 0x06,
            0x01,
            0x00,

            // TIT2 = UTF-8 "X".
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x03,
            'X',

            // Three padding bytes.
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
        parseId3v24CanonicalTag(
            cursor
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.structure.body.hasExtendedHeader);

    assert(
        tag.structure.body.extendedHeader
            .sourceOffset ==
        510
    );

    assert(
        tag.structure.body.extendedHeader
            .size ==
        6
    );

    assert(tag.structure.frames.padding.length == 3);

    assert(tag.projection.metadata.length == 1);

    assert(
        tag.projection.metadata[0].key.name ==
        "title"
    );
}


/// A footer remains part of the complete structural tag view.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x03,
            'X',

            '3', 'D', 'I',
            0x04, 0x00,
            0x10,
            0x00, 0x00, 0x00, 0x0C
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                700
            )
        );

    auto result =
        parseId3v24CanonicalTag(
            cursor
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(tag.structure.envelope.header.hasFooter);

    assert(
        tag.structure.envelope.footer.length ==
        10
    );

    assert(tag.structure.frames.padding.empty);

    assert(tag.projection.metadata.length == 1);

    assert(tag.endOffset == 732);
}


/// Tag-level unsynchronisation is forwarded to binary semantic mapping.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x80,
            0x00, 0x00, 0x00, 0x0F,

            'P', 'R', 'I', 'V',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x00,

            'o', 0x00,
            0xFF, 0x00, 0xE1
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );

    auto result =
        parseId3v24CanonicalTag(
            cursor
        );

    assert(result.hasValue);

    const tag =
        result.value;

    assert(
        tag.structure.envelope.header
            .unsynchronisation
    );

    assert(tag.projection.metadata.length == 1);

    const binaryMatches =
        tag.projection.metadata[0]
            .value
            .match!(
                (MetadataBinary binary) =>
                    binary.data ==
                        [0xFF, 0xE1],

                _ => false
            );

    assert(binaryMatches);
}


/// Semantic failure leaves the original whole-tag cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x04, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0C,

            // Structurally valid TIT2 with invalid encoding marker.
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x04,
            'X',

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
        parseId3v24CanonicalTag(
            cursor
        );

    assert(result.hasError);

    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );

    assert(
        result.error.offset ==
        1120
    );

    assert(cursor.position == 0);
    assert(cursor.absoluteOffset == 1100);
    assert(cursor.remaining == bytes.length);
}
