/++
Provenance-preserving canonical projection of native ID3v2.3 frames.

Canonical metadata is a semantic view of native metadata. It does not
replace the native representation.

Every projected native frame is therefore retained in original order,
including frames that:

- map successfully to canonical metadata;
- are currently unsupported;
- require decompression or decryption;
- contain valid semantics that cannot yet be represented canonically.

The canonical tree contains the mapped semantic fields. Each native
frame record stores the contiguous canonical field range produced by
that frame.

At present one native ID3v2.3 frame produces at most one canonical
field. The range representation deliberately permits future mappers to
produce more than one field without changing this preservation model.

Native frames contain bounded source spans and therefore retain the
lifetime requirements of their underlying byte source.
+/
module audiotag.id3v2.v23.canonical_projection;

import audiotag.id3v2.v23.canonical_mapping :
    Id3v23CanonicalMappingResult,
    Id3v23CanonicalMappingStatus;

import audiotag.id3v2.v23.native_frame :
    Id3v23NativeFrame;

import audiotag.metadata.tree :
    MetadataTree;


/++
Relationship between one preserved native frame and its canonical
projection.

`canonicalStart` is the canonical insertion position at which this
native frame was projected.

When `canonicalCount == 0`, no canonical field was produced but the
insertion position is still retained. This preserves the native
frame's location relative to surrounding mapped fields.
+/
struct Id3v23CanonicalFrameRecord
{
    /// Complete native frame, including its structural envelope.
    Id3v23NativeFrame native;

    /// Canonical mapping outcome for this frame.
    Id3v23CanonicalMappingStatus status;

    /// First canonical field index produced by this frame.
    size_t canonicalStart;

    /// Number of consecutive canonical fields produced by this frame.
    size_t canonicalCount;


    /++
    Returns whether this frame produced canonical metadata.
    +/
    @property
    bool mapped() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v23CanonicalMappingStatus.mapped;
    }
}


/++
Ordered projection of native ID3v2.3 frames into canonical metadata.

Native frames and mapping records remain in original frame order.
Canonical fields remain in canonical insertion order.

Appending never discards a native frame.
+/
struct Id3v23CanonicalProjection
{
private:
    MetadataTree _metadata;
    Id3v23CanonicalFrameRecord[] _frames;

public:
    /++
    Returns the canonical semantic metadata tree.
    +/
    @property
    const(MetadataTree) metadata() const
        @safe pure nothrow @nogc
    {
        return
            _metadata;
    }


    /++
    Returns all native-frame projection records in source order.
    +/
    @property
    const(Id3v23CanonicalFrameRecord)[] frames() const
        @safe pure nothrow @nogc
    {
        return
            _frames;
    }


    /++
    Returns the number of preserved native frames.
    +/
    @property
    size_t frameCount() const
        @safe pure nothrow @nogc
    {
        return
            _frames.length;
    }


    /++
    Returns whether no native frames have been projected.
    +/
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

    The native frame is retained regardless of mapping status.

    A successful mapping appends the produced field to the canonical
    tree. Other mapping outcomes append no canonical field but remain
    visible through their frame record.

    Params:
        native = Complete provenance-preserving native frame.
        mapping = Canonical mapping result for that exact frame.
    +/
    void append(
        Id3v23NativeFrame native,
        Id3v23CanonicalMappingResult mapping
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
            Id3v23CanonicalFrameRecord(
                native,
                mapping.status,
                canonicalStart,
                canonicalCount
            );
    }
}


version (unittest)
{
    import audiotag.id3v2.v23.frame :
        Id3v23FrameEnvelope;

    import audiotag.id3v2.v23.native_frame :
        Id3v23NativeFrameContent,
        Id3v23UnknownFrame;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;


    private Id3v23NativeFrame testNative()
        @safe
    {
        Id3v23NativeFrameContent content =
            Id3v23UnknownFrame();


        return
            Id3v23NativeFrame(
                Id3v23FrameEnvelope.init,
                content
            );
    }


    private Id3v23CanonicalMappingResult testMapped(
        string key,
        string value
    )
        @safe
    {
        return
            Id3v23CanonicalMappingResult
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
        Id3v23CanonicalProjection.init;


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
        Id3v23CanonicalProjection.init;


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
        Id3v23CanonicalMappingStatus.mapped
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
        Id3v23CanonicalProjection.init;


    projection.append(
        testNative(),
        Id3v23CanonicalMappingResult
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
        Id3v23CanonicalMappingStatus
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


/// Pending transformations remain explicit and preserve the native frame.
unittest
{
    auto projection =
        Id3v23CanonicalProjection.init;


    projection.append(
        testNative(),
        Id3v23CanonicalMappingResult
            .transformationRequired()
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
        Id3v23CanonicalMappingStatus
            .requiresTransformation
    );


    assert(
        projection.frames[0]
            .canonicalCount ==
        0
    );
}


/// Native ordering remains visible across mapped and unmapped frames.
unittest
{
    auto projection =
        Id3v23CanonicalProjection.init;


    projection.append(
        testNative(),
        testMapped(
            "title",
            "Title"
        )
    );


    projection.append(
        testNative(),
        Id3v23CanonicalMappingResult
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
     * The unsupported native frame occurred after canonical field 0
     * and before canonical field 1.
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
        Id3v23CanonicalProjection.init;


    projection.append(
        testNative(),
        Id3v23CanonicalMappingResult
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
        Id3v23CanonicalMappingStatus
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
