/++
Provenance-preserving canonical projection of native ID3v2.2 frames.

Canonical metadata is a semantic view of native metadata. It does not replace
the native representation.

Every projected native frame is therefore retained in original order,
including frames that:

- map successfully to canonical metadata;
- are currently unsupported;
- contain valid semantics that cannot yet be represented canonically.

The canonical tree contains mapped semantic fields. Each native-frame record
stores the contiguous canonical field range associated with that frame.

Canonical ranges are not required to be disjoint or monotonic in native frame
order. Several native frames may intentionally point to the same canonical
field when their semantics were combined many-to-one, for example
`TYE`/`TDA`/`TIM` -> `recordingDate`.

Native frames contain bounded source spans and therefore retain the lifetime
requirements of their underlying byte source.
+/
module audiotag.id3v2.v22.canonical_projection;

import audiotag.id3v2.v22.canonical_mapping :
    Id3v22CanonicalMappingResult,
    Id3v22CanonicalMappingStatus;

import audiotag.id3v2.v22.native_frame :
    Id3v22NativeFrame;

import audiotag.metadata.tree :
    MetadataTree;


/++
Relationship between one preserved native frame and its canonical projection.

`canonicalStart` is the first canonical field associated with this native
frame. For an ordinary one-to-one mapping it is the insertion position. For a
many-to-one mapping it may point to a field inserted by an earlier native
frame, so ranges may overlap and may be non-monotonic.

When `canonicalCount == 0`, no canonical field is associated with the native
frame. The stored position still records where ordinary projection had reached
when that frame was encountered.
+/
struct Id3v22CanonicalFrameRecord
{
    /// Complete native frame, including its structural envelope.
    Id3v22NativeFrame native;

    /// Canonical mapping outcome for this frame.
    Id3v22CanonicalMappingStatus status;

    /// First canonical field index associated with this frame.
    size_t canonicalStart;

    /// Number of consecutive canonical fields associated with this frame.
    size_t canonicalCount;


    /// Whether this frame is associated with canonical metadata.
    @property
    bool mapped() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v22CanonicalMappingStatus.mapped;
    }
}


/++
Ordered projection of native ID3v2.2 frames into canonical metadata.

Native frames and mapping records remain in original source order. Canonical
fields remain in canonical insertion order. Appending never discards a native
frame.
+/
struct Id3v22CanonicalProjection
{
private:
    MetadataTree _metadata;
    Id3v22CanonicalFrameRecord[] _frames;

public:
    /// Canonical semantic metadata tree.
    @property
    const(MetadataTree) metadata() const
        @safe pure nothrow @nogc
    {
        return
            _metadata;
    }


    /// All native-frame projection records in source order.
    @property
    const(Id3v22CanonicalFrameRecord)[] frames() const
        @safe pure nothrow @nogc
    {
        return
            _frames;
    }


    /// Number of preserved native frames.
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        return
            _frames.length;
    }


    /// Whether no native frames have been projected.
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return
            _frames.length ==
            0;
    }


    /++
    Appends one native frame and its canonical mapping result.

    The native frame is retained regardless of mapping status. A successful
    mapping appends the produced field to the canonical tree. Other mapping
    outcomes append no canonical field but remain visible through their frame
    record.
    +/
    void append(
        Id3v22NativeFrame native,
        Id3v22CanonicalMappingResult mapping
    )
        @safe
    {
        const canonicalStart =
            _metadata.length;

        size_t canonicalCount =
            0;

        if (
            mapping.mapped
        )
        {
            _metadata.append(
                mapping.field
            );

            canonicalCount =
                1;
        }

        _frames ~=
            Id3v22CanonicalFrameRecord(
                native,
                mapping.status,
                canonicalStart,
                canonicalCount
            );
    }


    /++
    Appends a native frame linked to canonical metadata already present in the
    projection.

    This supports many-to-one mappings where several native frames jointly
    contribute to the same canonical field. The linked range may therefore
    overlap another frame's range and may point to an earlier canonical
    position. No canonical field is appended by this operation.
    +/
    void appendLinkedMapped(
        Id3v22NativeFrame native,
        size_t canonicalStart,
        size_t canonicalCount = 1
    )
        @safe
    {
        assert(
            canonicalCount !=
            0
        );

        assert(
            canonicalStart <=
            _metadata.length
        );

        assert(
            canonicalCount <=
            _metadata.length -
                canonicalStart
        );

        _frames ~=
            Id3v22CanonicalFrameRecord(
                native,
                Id3v22CanonicalMappingStatus.mapped,
                canonicalStart,
                canonicalCount
            );
    }
}


version (unittest)
{
    import audiotag.id3v2.v22.frame :
        Id3v22FrameEnvelope;

    import audiotag.id3v2.v22.native_frame :
        Id3v22NativeFrameContent,
        Id3v22UnknownFrame;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;


    private Id3v22NativeFrame
    testNative()
        @safe
    {
        Id3v22NativeFrameContent content =
            Id3v22UnknownFrame();

        return
            Id3v22NativeFrame(
                Id3v22FrameEnvelope.init,
                content
            );
    }


    private Id3v22CanonicalMappingResult
    testMapped(
        string key,
        string value
    )
        @safe
    {
        return
            Id3v22CanonicalMappingResult
                .success(
                    MetadataField(
                        MetadataKey(
                            key
                        ),
                        MetadataValue(
                            MetadataText(
                                value
                            )
                        )
                    )
                );
    }
}


/// A new projection contains neither native nor canonical metadata.
unittest
{
    const projection =
        Id3v22CanonicalProjection.init;

    assert(
        projection.empty
    );

    assert(
        projection.frameCount ==
        0
    );

    assert(
        projection.frames.length ==
        0
    );

    assert(
        projection.metadata.empty
    );

    assert(
        projection.metadata.length ==
        0
    );
}


/// A mapped frame is preserved and contributes one canonical field.
unittest
{
    auto projection =
        Id3v22CanonicalProjection.init;

    projection.append(
        testNative(),
        testMapped(
            "title",
            "Example"
        )
    );

    assert(
        !projection.empty
    );

    assert(
        projection.frameCount ==
        1
    );

    assert(
        projection.metadata.length ==
        1
    );

    assert(
        projection.metadata[0]
            .key.name ==
        "title"
    );

    const record =
        projection.frames[0];

    assert(
        record.mapped
    );

    assert(
        record.status ==
        Id3v22CanonicalMappingStatus.mapped
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


/// Unsupported native frames remain preserved without canonical fields.
unittest
{
    auto projection =
        Id3v22CanonicalProjection.init;

    projection.append(
        testNative(),
        Id3v22CanonicalMappingResult
            .unsupported()
    );

    assert(
        projection.frameCount ==
        1
    );

    assert(
        projection.metadata.empty
    );

    const record =
        projection.frames[0];

    assert(
        !record.mapped
    );

    assert(
        record.status ==
        Id3v22CanonicalMappingStatus
            .unsupportedFrame
    );

    assert(
        record.canonicalStart ==
        0
    );

    assert(
        record.canonicalCount ==
        0
    );
}


/// Native ordering remains visible across mapped and unmapped frames.
unittest
{
    auto projection =
        Id3v22CanonicalProjection.init;

    projection.append(
        testNative(),
        testMapped(
            "title",
            "Title"
        )
    );

    projection.append(
        testNative(),
        Id3v22CanonicalMappingResult
            .unsupported()
    );

    projection.append(
        testNative(),
        testMapped(
            "artist",
            "Artist"
        )
    );

    assert(
        projection.frameCount ==
        3
    );

    assert(
        projection.metadata.length ==
        2
    );

    assert(
        projection.metadata[0]
            .key.name ==
        "title"
    );

    assert(
        projection.metadata[1]
            .key.name ==
        "artist"
    );

    assert(
        projection.frames[0]
            .canonicalStart ==
        0
    );

    assert(
        projection.frames[0]
            .canonicalCount ==
        1
    );

    /*
     * The unsupported native frame occurred after canonical field 0 and before
     * canonical field 1.
     */
    assert(
        projection.frames[1]
            .canonicalStart ==
        1
    );

    assert(
        projection.frames[1]
            .canonicalCount ==
        0
    );

    assert(
        projection.frames[2]
            .canonicalStart ==
        1
    );

    assert(
        projection.frames[2]
            .canonicalCount ==
        1
    );
}


/// Unrepresentable native semantics remain preserved explicitly.
unittest
{
    auto projection =
        Id3v22CanonicalProjection.init;

    projection.append(
        testNative(),
        Id3v22CanonicalMappingResult
            .unrepresentable()
    );

    assert(
        projection.frameCount ==
        1
    );

    assert(
        projection.metadata.empty
    );

    assert(
        projection.frames[0]
            .status ==
        Id3v22CanonicalMappingStatus
            .unrepresentableValueShape
    );

    assert(
        projection.frames[0]
            .canonicalStart ==
        0
    );

    assert(
        projection.frames[0]
            .canonicalCount ==
        0
    );
}


/// Multiple native frames may link to the same canonical field.
unittest
{
    auto projection =
        Id3v22CanonicalProjection.init;

    projection.append(
        testNative(),
        testMapped(
            "title",
            "Example"
        )
    );

    projection.appendLinkedMapped(
        testNative(),
        0
    );

    assert(
        projection.frameCount ==
        2
    );

    assert(
        projection.metadata.length ==
        1
    );

    assert(
        projection.frames[0]
            .mapped
    );

    assert(
        projection.frames[0]
            .canonicalStart ==
        0
    );

    assert(
        projection.frames[0]
            .canonicalCount ==
        1
    );

    assert(
        projection.frames[1]
            .mapped
    );

    assert(
        projection.frames[1]
            .canonicalStart ==
        0
    );

    assert(
        projection.frames[1]
            .canonicalCount ==
        1
    );
}
