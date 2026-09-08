/++
Whole-tag canonical projection for ID3v2.3.

The strict structural parser already provides the complete native tag
representation:

- validated tag envelope and header;
- bounded physical body;
- optional extended header;
- validated frame sequence;
- padding;
- tag-level unsynchronisation state.

This module does not duplicate that structural model. Instead it pairs
the existing `Id3v23TagStructure` with the provenance-preserving
canonical frame projection.

The resulting object therefore exposes both:

- the complete native structural representation needed for later
  roundtrip-aware writing;
- the format-independent canonical metadata view.

ID3v2.3 has no tag footer. Whole-tag unsynchronisation remains part of
the validated structural state and is forwarded to semantic frame
projection.

Semantic projection errors remain structured `ParseError` values.
The cursor-level parser is transactional across both structural parsing
and semantic projection.
+/
module audiotag.id3v2.v23.canonical_tag;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v23.canonical_projection :
    Id3v23CanonicalProjection;

import audiotag.id3v2.v23.canonical_sequence :
    projectId3v23FrameSequenceToCanonical;

import audiotag.id3v2.v23.crc_validation :
    Id3v23CrcValidationResult,
    validateId3v23TagCrc;

import audiotag.id3v2.v23.structure :
    Id3v23TagStructure,
    parseId3v23TagStructure;


/++
Complete native-plus-canonical representation of one ID3v2.3 tag.

`structure` retains the complete validated structural tag view.

`projection` retains every native semantic frame in source order while
also exposing mapped canonical metadata.
+/
struct Id3v23CanonicalTag
{
    /// Complete validated native tag structure.
    Id3v23TagStructure structure;

    /// Provenance-preserving canonical frame projection.
    Id3v23CanonicalProjection projection;


    /++
    Returns the number of structurally validated native frames.
    +/
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        return
            structure.frameCount;
    }


    /++
    Returns the absolute source offset immediately following the tag.
    +/
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            structure.endOffset;
    }


    /++
    Validates the optional ID3v2.3 extended-header CRC.

    CRC integrity remains independent of structural parsing and semantic
    projection. A mismatch therefore returns a validation result rather
    than invalidating this already parsed canonical tag.

    This operation traverses the complete logical/native frame sequence
    and is intentionally a method rather than a property.
    +/
    Id3v23CrcValidationResult
    validateCrc() const
        @safe pure nothrow @nogc
    {
        return
            validateId3v23TagCrc(
                structure
            );
    }
}


/++
Projects one already validated ID3v2.3 tag structure into canonical
metadata.

The structural representation is retained unchanged.

Tag-level unsynchronisation from the validated header is forwarded to
semantic frame decoding through the frame-sequence projector.

Params:
    structure = Complete validated ID3v2.3 tag structure.

Returns:
    Native-plus-canonical tag representation, or a semantic codec error.
+/
ParseResult!Id3v23CanonicalTag
projectId3v23TagStructureToCanonical(
    Id3v23TagStructure structure
)
    @safe
{
    auto projectionResult =
        projectId3v23FrameSequenceToCanonical(
            structure.frames,
            structure.envelope.header
                .unsynchronisation
        );


    if (
        projectionResult.hasError
    )
    {
        return
            ParseResult!Id3v23CanonicalTag
                .failure(
                    projectionResult.error
                );
    }


    return
        ParseResult!Id3v23CanonicalTag
            .success(
                Id3v23CanonicalTag(
                    structure,
                    projectionResult.value
                )
            );
}


/++
Strictly parses and canonically projects one complete ID3v2.3 tag.

Both structural parsing and semantic projection form one transaction.
The caller's cursor is updated only when the complete native structure
and canonical projection both succeed.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.3 tag.

Returns:
    Complete native-plus-canonical tag representation, or a structured
    parsing/semantic error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v23CanonicalTag
parseId3v23CanonicalTag(
    ref ByteCursor cursor
)
    @safe
{
    auto probe =
        cursor;


    auto structureResult =
        probe.parseId3v23TagStructure();


    if (
        structureResult.hasError
    )
    {
        return
            ParseResult!Id3v23CanonicalTag
                .failure(
                    structureResult.error
                );
    }


    auto canonicalResult =
        projectId3v23TagStructureToCanonical(
            structureResult.value
        );


    if (
        canonicalResult.hasError
    )
    {
        return
            ParseResult!Id3v23CanonicalTag
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
    import audiotag.id3v2.v23.crc_validation :
        Id3v23CrcValidationStatus;

    import std.sumtype :
        match;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.canonical_mapping :
        Id3v23CanonicalMappingStatus;

    import audiotag.metadata.value :
        MetadataBinary;
}


/// A complete text tag exposes both structural and canonical views.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * One sixteen-byte TIT2 frame.
             */
            0x00, 0x00, 0x00, 0x10,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,

            /*
             * ID3v2.3 Latin-1 encoding marker.
             */
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
        parseId3v23CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.structure.envelope.header
            .sourceOffset ==
        100
    );


    assert(
        tag.structure.envelope.header
            .tagSize ==
        16
    );


    assert(
        tag.frameCount ==
        1
    );


    assert(
        tag.projection.frameCount ==
        1
    );


    assert(
        tag.projection.metadata.length ==
        1
    );


    assert(
        tag.projection.metadata[0]
            .key.name ==
        "title"
    );


    assert(
        tag.projection.frames[0]
            .status ==
        Id3v23CanonicalMappingStatus.mapped
    );


    assert(
        tag.endOffset ==
        126
    );


    assert(
        cursor.absoluteOffset ==
        126
    );


    assert(
        cursor.remaining ==
        1
    );


    assert(
        cursor.front ==
        0xAA
    );
}


/// Unknown frames survive whole-tag projection without canonical loss.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
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
        parseId3v23CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.frameCount ==
        1
    );


    assert(
        tag.projection.frameCount ==
        1
    );


    assert(
        tag.projection.metadata.empty
    );


    assert(
        tag.projection.frames[0]
            .status ==
        Id3v23CanonicalMappingStatus
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
            0x03, 0x00,

            /*
             * Extended-header flag.
             */
            0x40,

            /*
             * Physical body:
             *
             *   10-byte extended header
             *   12-byte TIT2 frame
             *    3-byte padding
             *
             * Total = 25.
             */
            0x00, 0x00, 0x00, 0x19,

            /*
             * ID3v2.3 extended-header size = 6.
             */
            0x00, 0x00, 0x00, 0x06,

            /*
             * No CRC.
             */
            0x00, 0x00,

            /*
             * Declared padding size = 3.
             */
            0x00, 0x00, 0x00, 0x03,

            /*
             * TIT2 = Latin-1 "X".
             */
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00,
            'X',

            /*
             * Padding.
             */
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
        parseId3v23CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.structure.body
            .hasExtendedHeader
    );


    assert(
        tag.structure.body
            .extendedHeader
            .sourceOffset ==
        510
    );


    assert(
        tag.structure.body
            .extendedHeader
            .size ==
        6
    );


    assert(
        tag.structure.body
            .extendedHeader
            .paddingSize ==
        3
    );


    assert(
        tag.structure.frames
            .padding.length ==
        3
    );


    assert(
        tag.projection.metadata.length ==
        1
    );


    assert(
        tag.projection.metadata[0]
            .key.name ==
        "title"
    );
}


/// Tag-level unsynchronisation reaches binary semantic projection.
unittest
{
    /*
     * Logical PRIV frame data:
     *
     *   o 00 FF E1
     *
     * Four logical bytes.
     *
     * Physical frame data:
     *
     *   o 00 FF 00 E1
     *
     * Five physical bytes.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            /*
             * Whole-tag unsynchronisation.
             */
            0x80,

            /*
             * Physical body size:
             * ten-byte frame header + five physical data bytes.
             */
            0x00, 0x00, 0x00, 0x0F,

            'P', 'R', 'I', 'V',

            /*
             * Four logical frame-data bytes.
             */
            0x00, 0x00, 0x00, 0x04,

            0x00, 0x00,

            'o',
            0x00,

            0xFF,
            0x00,
            0xE1
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                900
            )
        );


    auto result =
        parseId3v23CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.structure.envelope.header
            .unsynchronisation
    );


    assert(
        tag.structure.frames
            .frameBytes.length ==
        15
    );


    assert(
        tag.projection.metadata.length ==
        1
    );


    assert(
        tag.projection.metadata[0]
            .key.name ==
        "privateData"
    );


    const binaryMatches =
        tag.projection.metadata[0]
            .value
            .match!(
                (MetadataBinary binary) =>
                    binary.data ==
                        [
                            0xFF,
                            0xE1
                        ],

                _ =>
                    false
            );


    assert(
        binaryMatches
    );


    /*
     * Provenance retains the complete physical PRIV frame,
     * including the stuffing byte.
     */
    assert(
        tag.projection.metadata[0]
            .provenance[0]
            .sourceLength ==
        15
    );


    assert(
        tag.endOffset ==
        925
    );


    assert(
        cursor.absoluteOffset ==
        925
    );
}


/// Semantic failure leaves the original whole-tag cursor unchanged.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,

            /*
             * Twelve-byte frame.
             */
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            /*
             * UTF-8 marker is not valid for ID3v2.3.
             */
            0x03,
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
        parseId3v23CanonicalTag(
            cursor
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        ParseErrorCode
            .invalidEncodingMarker
    );


    assert(
        result.error.offset ==
        1120
    );


    /*
     * Structural parsing succeeded on the probe cursor, but semantic
     * projection failed. The caller remains entirely unchanged.
     */
    assert(
        cursor.position ==
        0
    );


    assert(
        cursor.absoluteOffset ==
        1100
    );


    assert(
        cursor.remaining ==
        bytes.length
    );
}



/// Canonical tags expose CRC validation without changing parse semantics.
unittest
{
    /*
     * One twelve-byte, semantically valid TIT2 frame whose CRC-32 is
     * 3854B80B.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,

            // Extended header.
            0x40,

            // 14-byte extended header + 12-byte frame.
            0x00, 0x00, 0x00, 0x1A,

            // Extended-header size = 10.
            0x00, 0x00, 0x00, 0x0A,

            // CRC present.
            0x80, 0x00,

            // No padding.
            0x00, 0x00, 0x00, 0x00,

            // CRC-32 over the logical frame sequence.
            0x38, 0x54, 0xB8, 0x0B,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            // Latin-1 encoding marker + one-character title.
            0x00, 'U'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto parsed =
        parseId3v23CanonicalTag(
            cursor
        );

    assert(parsed.hasValue);
    assert(cursor.empty);

    const validation =
        parsed.value.validateCrc();

    assert(validation.hasCrc);
    assert(validation.verified);
    assert(validation.storedCrc32 == 0x3854_B80B);
    assert(validation.computedCrc32 == 0x3854_B80B);
}


/// CRC mismatch remains observable on an otherwise valid canonical tag.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x40,

            0x00, 0x00, 0x00, 0x1A,

            0x00, 0x00, 0x00, 0x0A,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00,

            // Deliberately stale CRC.
            0x12, 0x34, 0x56, 0x78,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            // Latin-1 encoding marker + one-character title.
            0x00, 'U'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto parsed =
        parseId3v23CanonicalTag(
            cursor
        );

    /*
     * CRC integrity is deliberately not part of parse success.
     */
    assert(parsed.hasValue);
    assert(cursor.empty);

    const validation =
        parsed.value.validateCrc();

    assert(validation.hasCrc);
    assert(!validation.verified);

    assert(
        validation.status ==
        Id3v23CrcValidationStatus.mismatch
    );

    assert(validation.storedCrc32 == 0x1234_5678);
    assert(validation.computedCrc32 == 0x3854_B80B);
}
