/++
Whole-tag native-plus-canonical representation for ID3v2.2.

ID3v2.2 has two valid native tag-body states:

- an uncompressed, decoded native frame sequence;
- a whole-tag-compressed opaque body whose compression representation is not
  standardized by ID3v2.2.

Canonical projection is therefore explicitly availability-aware.

For an uncompressed tag, `hasCanonicalProjection` is true and `projection`
contains the provenance-preserving canonical view of every decoded native
frame.

For a `compressedOpaque` tag, `hasCanonicalProjection` is false. The default
`projection` value must not be interpreted as "the tag contains no metadata";
the canonical semantics are unavailable because the opaque compressed body was
not decoded. The exact native body remains preserved in
`native.structure.envelope.body`.

This module does not guess a compression method and does not discard the native
representation.
+/
module audiotag.id3v2.v22.canonical_tag;

import audiotag.core.cursor :
    ByteCursor;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v22.canonical_projection :
    Id3v22CanonicalProjection;

import audiotag.id3v2.v22.canonical_sequence :
    projectId3v22NativeFrameSequenceToCanonical;

import audiotag.id3v2.v22.native_tag :
    Id3v22NativeTag,
    decodeId3v22TagStructureToNative,
    parseId3v22NativeTag;

import audiotag.id3v2.v22.structure :
    Id3v22TagStructure;


/++
Complete native-plus-canonical representation of one ID3v2.2 tag.

`native` always preserves the complete validated/native tag representation.

`projection` is meaningful only when `hasCanonicalProjection` is true.
A compressed opaque body intentionally leaves `projection` default-initialized
because its semantic frames are unknown.
+/
struct Id3v22CanonicalTag
{
    /// Complete provenance-preserving native tag.
    Id3v22NativeTag native;

    /// Canonical projection when `hasCanonicalProjection` is true.
    Id3v22CanonicalProjection projection;


    /++
    Whether canonical semantic projection is available.

    Whole-tag-compressed opaque bodies return false because no frame semantics
    were guessed or decoded.
    +/
    @property
    bool hasCanonicalProjection() const
        @safe pure nothrow @nogc
    {
        return
            native.hasFrameSequence;
    }


    /// Whether the tag body is retained as opaque compressed physical bytes.
    @property
    bool compressedOpaque() const
        @safe pure nothrow @nogc
    {
        return
            native.compressedOpaque;
    }


    /++
    Number of decoded native frames.

    Preconditions:
        `hasCanonicalProjection` must be true.
    +/
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        assert(
            hasCanonicalProjection
        );

        return
            native.frameCount;
    }


    /// Absolute source offset immediately following the complete tag.
    @property
    size_t endOffset() const
        @safe pure nothrow @nogc
    {
        return
            native.endOffset;
    }
}


/++
Projects one already decoded native ID3v2.2 tag to canonical metadata.

No bytes are reparsed and no semantic frame is decoded again.

Uncompressed tags project their existing native frame sequence.

Opaque compressed tags remain successful native-plus-canonical tag objects but
report `hasCanonicalProjection == false`; their canonical projection remains
default-initialized and must not be interpreted as semantic emptiness.

Params:
    native = Complete decoded/preserved native ID3v2.2 tag.

Returns:
    Native-plus-canonical tag representation.
+/
Id3v22CanonicalTag
projectId3v22NativeTagToCanonical(
    Id3v22NativeTag native
)
    @safe
{
    Id3v22CanonicalProjection projection;


    if (
        native.hasFrameSequence
    )
    {
        projection =
            projectId3v22NativeFrameSequenceToCanonical(
                native.sequence
            );
    }


    return
        Id3v22CanonicalTag(
            native,
            projection
        );
}


/++
Projects one already validated ID3v2.2 tag structure into native plus canonical
metadata.

Native semantic decoding is delegated to `decodeId3v22TagStructureToNative`.

For an opaque compressed structure the native decode succeeds without guessing
frame semantics, and the resulting canonical tag reports no available
projection.

Params:
    structure = Complete validated ID3v2.2 tag structure.

Returns:
    Native-plus-canonical tag representation or a semantic native-frame decode
    error.
+/
ParseResult!Id3v22CanonicalTag
projectId3v22TagStructureToCanonical(
    Id3v22TagStructure structure
)
    @safe
{
    auto nativeResult =
        decodeId3v22TagStructureToNative(
            structure
        );


    if (
        nativeResult.hasError
    )
    {
        return
            ParseResult!Id3v22CanonicalTag
                .failure(
                    nativeResult.error
                );
    }


    return
        ParseResult!Id3v22CanonicalTag
            .success(
                projectId3v22NativeTagToCanonical(
                    nativeResult.value
                )
            );
}


/++
Strictly parses, natively decodes and canonically projects one complete
ID3v2.2 tag.

The operation is transactional. The caller's cursor advances only after
structural parsing and native semantic decoding succeed.

Canonical projection of an already decoded native tag cannot introduce a new
parse failure.

A valid opaque compressed tag also succeeds, advances the cursor normally and
reports `hasCanonicalProjection == false`.

Params:
    cursor = Cursor positioned at the first byte of an ID3v2.2 tag.

Returns:
    Complete native-plus-canonical tag representation or a structured
    parsing/native-semantic error.

Error semantics:
    Any failure leaves `cursor` unchanged.
+/
ParseResult!Id3v22CanonicalTag
parseId3v22CanonicalTag(
    ref ByteCursor cursor
)
    @safe
{
    auto probe =
        cursor;


    auto nativeResult =
        parseId3v22NativeTag(
            probe
        );


    if (
        nativeResult.hasError
    )
    {
        return
            ParseResult!Id3v22CanonicalTag
                .failure(
                    nativeResult.error
                );
    }


    auto canonical =
        projectId3v22NativeTagToCanonical(
            nativeResult.value
        );


    cursor =
        probe;


    return
        ParseResult!Id3v22CanonicalTag
            .success(
                canonical
            );
}


version (unittest)
{
    import std.sumtype :
        match;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v22.canonical_mapping :
        Id3v22CanonicalMappingStatus;

    import audiotag.metadata.value :
        MetadataBinary,
        MetadataDateTimeList,
        MetadataText;
}


/// A complete uncompressed text tag exposes native and canonical views.
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
        parseId3v22CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.hasCanonicalProjection
    );


    assert(
        !tag.compressedOpaque
    );


    assert(
        tag.frameCount ==
        1
    );


    assert(
        tag.native.structure.envelope.header
            .sourceOffset ==
        100
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
        Id3v22CanonicalMappingStatus.mapped
    );


    assert(
        tag.projection.metadata[0]
            .value.match!(
                (MetadataText text) =>
                    text.value ==
                    "Title",

                _ =>
                    false
            )
    );


    assert(
        tag.endOffset ==
        122
    );


    assert(
        cursor.absoluteOffset ==
        122
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


/// Unknown frames survive whole-tag projection as native-only metadata.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x07,

            'Z', 'Z', 'Z',
            0x00, 0x00, 0x01,

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
        parseId3v22CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.hasCanonicalProjection
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
        tag.projection.metadata.empty
    );


    assert(
        tag.projection.frames[0]
            .status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );


    assert(
        tag.projection.frames[0]
            .native.envelope.header.id[] ==
        "ZZZ"
    );


    assert(
        tag.projection.frames[0]
            .native.envelope.data.data ==
        [0x55]
    );
}


/// Legacy recording time aggregates at whole-tag level.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            /*
             * Three eleven-byte frames = 33-byte tag body.
             */
            0x00, 0x00, 0x00, 0x21,


            'T', 'Y', 'E',
            0x00, 0x00, 0x05,

            0x00,
            '2', '0', '0', '0',


            'T', 'D', 'A',
            0x00, 0x00, 0x05,

            0x00,
            '2', '9', '0', '2',


            'T', 'I', 'M',
            0x00, 0x00, 0x05,

            0x00,
            '2', '3', '5', '9'
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                500
            )
        );


    auto result =
        parseId3v22CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.hasCanonicalProjection
    );


    assert(
        tag.frameCount ==
        3
    );


    assert(
        tag.projection.frameCount ==
        3
    );


    assert(
        tag.projection.metadata.length ==
        1
    );


    assert(
        tag.projection.metadata[0]
            .key.name ==
        "recordingDate"
    );


    assert(
        tag.projection.metadata[0]
            .provenance.length ==
        3
    );


    assert(
        tag.projection.metadata[0]
            .value.match!(
                (const(MetadataDateTimeList) list) =>
                    list.values.length == 1 &&
                    list.values[0].hasYear &&
                    list.values[0].year == 2000 &&
                    list.values[0].hasMonth &&
                    list.values[0].month == 2 &&
                    list.values[0].hasDay &&
                    list.values[0].day == 29 &&
                    list.values[0].hasHour &&
                    list.values[0].hour == 23 &&
                    list.values[0].hasMinute &&
                    list.values[0].minute == 59,

                _ =>
                    false
            )
    );


    foreach (
        record;
        tag.projection.frames
    )
    {
        assert(
            record.mapped
        );


        assert(
            record.canonicalStart ==
            0
        );


        assert(
            record.canonicalCount ==
            1
        );
    }
}


/// Whole-tag unsynchronisation reaches canonical binary semantics.
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
     * The frame header declares four logical bytes; the body contains eleven
     * physical bytes including the six-byte frame header.
     */
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,

            /*
             * Whole-tag unsynchronisation.
             */
            0x80,

            0x00, 0x00, 0x00, 0x0B,

            'U', 'F', 'I',
            0x00, 0x00, 0x04,

            'x',
            0x00,

            0xFF,
            0x00,
            0xE0
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                800
            )
        );


    auto result =
        parseId3v22CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        tag.hasCanonicalProjection
    );


    assert(
        tag.projection.metadata.length ==
        1
    );


    assert(
        tag.projection.metadata[0]
            .key.name ==
        "uniqueFileIdentifier"
    );


    assert(
        tag.projection.metadata[0]
            .value.match!(
                (MetadataBinary binary) =>
                    binary.data ==
                        [
                            0xFF,
                            0xE0
                        ],

                _ =>
                    false
            )
    );


    /*
     * Canonical provenance retains the physical frame, including the stuffing
     * zero.
     */
    assert(
        tag.projection.metadata[0]
            .provenance[0]
            .sourceLength ==
        11
    );


    assert(
        tag.projection.frames[0]
            .native.sourceLength ==
        11
    );
}


/// Opaque whole-tag compression is valid but has no canonical projection.
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
                1000
            )
        );


    auto result =
        parseId3v22CanonicalTag(
            cursor
        );


    assert(
        result.hasValue
    );


    const tag =
        result.value;


    assert(
        !tag.hasCanonicalProjection
    );


    assert(
        tag.compressedOpaque
    );


    assert(
        tag.projection.empty
    );


    assert(
        tag.projection.metadata.empty
    );


    assert(
        tag.native.sequence.frames.length ==
        0
    );


    assert(
        tag.native.structure.envelope.body.data ==
        [0xDE, 0xAD, 0xBE, 0xEF]
    );


    assert(
        tag.native.structure.envelope.body.sourceOffset ==
        1010
    );


    assert(
        tag.endOffset ==
        1014
    );


    assert(
        cursor.absoluteOffset ==
        1014
    );


    assert(
        cursor.remaining ==
        1
    );


    assert(
        cursor.front ==
        0x55
    );
}


/// Projection of an already native tag does not reparse or re-decode bytes.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x02, 0x00,
            0x00,

            0x00, 0x00, 0x00, 0x08,

            'T', 'A', 'L',
            0x00, 0x00, 0x02,

            0x00,
            'A'
        ];


    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                1200
            )
        );


    auto nativeResult =
        parseId3v22NativeTag(
            cursor
        );


    assert(
        nativeResult.hasValue
    );


    const tag =
        projectId3v22NativeTagToCanonical(
            nativeResult.value
        );


    assert(
        tag.hasCanonicalProjection
    );


    assert(
        tag.projection.metadata.length ==
        1
    );


    assert(
        tag.projection.metadata[0]
            .key.name ==
        "album"
    );


    assert(
        tag.projection.metadata[0]
            .value.match!(
                (MetadataText text) =>
                    text.value ==
                    "A",

                _ =>
                    false
            )
    );
}


/// Semantic native-decoding failure leaves the whole-tag cursor unchanged.
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
                1500
            )
        );


    auto result =
        parseId3v22CanonicalTag(
            cursor
        );


    assert(
        result.hasError
    );


    assert(
        result.error.code ==
        ParseErrorCode.invalidEncodingMarker
    );


    assert(
        result.error.offset ==
        1516
    );


    assert(
        cursor.position ==
        0
    );


    assert(
        cursor.absoluteOffset ==
        1500
    );


    assert(
        cursor.remaining ==
        bytes.length
    );
}
