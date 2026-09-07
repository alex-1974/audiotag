/++
ID3v2.3 writer preservation policy.

This module defines decisions that must be made before byte
serialization begins.

Native ID3v2.3 frames may carry status flags describing what should
happen when the enclosing tag or file is altered. Frames may also be
marked read-only.

The writer additionally protects the library-level invariant that
metadata is not silently discarded. Therefore the default policy
rejects a write when an unsupported or otherwise non-regenerable frame
would have to be discarded because of its native preservation flags.

The raw ID3v2.3 status-bit positions differ from ID3v2.4. This module
does not interpret those bits directly; it consumes the semantic
properties exposed by `Id3v23FrameHeader`.

No bytes are emitted by this module.
+/
module audiotag.id3v2.v23.writer_policy;

import audiotag.id3v2.v23.frame_header :
    Id3v23FrameHeader;


/++
Describes which enclosing object is being altered by a write.

The two dimensions are independent because ID3v2.3 distinguishes tag
alteration from alteration of the containing audio file.
+/
struct Id3v23WriteContext
{
    /// Whether the ID3 tag itself is being altered.
    bool tagAltered;

    /// Whether the containing file outside the tag is being altered.
    bool fileAltered;


    /++
    Constructs a context in which neither tag nor file content changes.
    +/
    static Id3v23WriteContext unchanged()
        @safe pure nothrow @nogc
    {
        return
            Id3v23WriteContext(
                false,
                false
            );
    }


    /++
    Constructs a tag-only alteration context.
    +/
    static Id3v23WriteContext tagOnly()
        @safe pure nothrow @nogc
    {
        return
            Id3v23WriteContext(
                true,
                false
            );
    }


    /++
    Constructs a file-only alteration context.
    +/
    static Id3v23WriteContext fileOnly()
        @safe pure nothrow @nogc
    {
        return
            Id3v23WriteContext(
                false,
                true
            );
    }


    /++
    Constructs a context in which both tag and containing file change.
    +/
    static Id3v23WriteContext tagAndFile()
        @safe pure nothrow @nogc
    {
        return
            Id3v23WriteContext(
                true,
                true
            );
    }
}


/++
Policy applied when native preservation flags require an otherwise
non-regenerable frame to be discarded.

`rejectWrite` is deliberately the default value. A caller must opt in
explicitly before such data may be discarded.
+/
enum Id3v23RequiredDiscardPolicy : ubyte
{
    /// Reject the write rather than lose native metadata.
    rejectWrite,

    /// Permit the frame to be discarded as required by its native flag.
    discard
}


/++
Writer preservation policy.

Further writer policies may be added as serialization support grows.
+/
struct Id3v23WriterPolicy
{
    /// Behavior when an unregenerable frame is required to be discarded.
    Id3v23RequiredDiscardPolicy requiredDiscard =
        Id3v23RequiredDiscardPolicy.rejectWrite;
}


/++
Action for an unsupported or otherwise non-regenerable native frame.

Such a frame cannot currently be reconstructed from canonical metadata,
so the writer can only preserve its original physical bytes, discard it
when explicitly permitted, or reject the write.
+/
enum Id3v23UnregenerableFrameAction : ubyte
{
    preserveOriginal,
    discard,
    rejectWrite
}


/++
Determines how an unsupported or otherwise non-regenerable native frame
must be handled in the given write context.

The ID3v2.3 tag-alter and file-alter preservation properties are
consulted only because the caller has already determined that this frame
cannot safely be regenerated.

When neither applicable preservation flag requires discarding the
frame, its exact original physical bytes are retained.

If discarding is required, the writer policy decides whether the write
must fail or whether the loss is explicitly permitted.

Params:
    header = Native frame header carrying preservation flags.
    context = Enclosing tag/file alteration state.
    policy = Writer preservation policy.

Returns:
    Required preservation action.
+/
Id3v23UnregenerableFrameAction
decideId3v23UnregenerableFrameAction(
    const(Id3v23FrameHeader) header,
    Id3v23WriteContext context,
    Id3v23WriterPolicy policy =
        Id3v23WriterPolicy.init
)
    @safe pure nothrow @nogc
{
    const discardRequired =
        (
            context.tagAltered &&
            header.discardOnTagAlter
        ) ||
        (
            context.fileAltered &&
            header.discardOnFileAlter
        );


    if (
        !discardRequired
    )
    {
        return
            Id3v23UnregenerableFrameAction
                .preserveOriginal;
    }


    final switch (
        policy.requiredDiscard
    )
    {
        case Id3v23RequiredDiscardPolicy.rejectWrite:
            return
                Id3v23UnregenerableFrameAction
                    .rejectWrite;

        case Id3v23RequiredDiscardPolicy.discard:
            return
                Id3v23UnregenerableFrameAction
                    .discard;
    }
}


/++
Action when a mapped native frame is requested to be regenerated from
modified canonical metadata.
+/
enum Id3v23MappedFrameModificationAction : ubyte
{
    regenerate,
    rejectWrite
}


/++
Determines whether a mapped native frame may be regenerated after its
canonical metadata has been modified.

A native read-only frame is not silently overwritten. Until an explicit
ownership/override mechanism exists, modifying such a frame rejects the
write.

Params:
    header = Native frame header.

Returns:
    `regenerate` for a writable frame, otherwise `rejectWrite`.
+/
Id3v23MappedFrameModificationAction
decideId3v23MappedFrameModificationAction(
    const(Id3v23FrameHeader) header
)
    @safe pure nothrow @nogc
{
    if (
        header.readOnly
    )
    {
        return
            Id3v23MappedFrameModificationAction
                .rejectWrite;
    }


    return
        Id3v23MappedFrameModificationAction
            .regenerate;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.frame_header :
        parseId3v23FrameHeader;


    private Id3v23FrameHeader testHeader(
        ubyte statusFlags
    )
        @safe
    {
        const ubyte[] bytes =
            [
                'A', 'B', 'C', '1',

                /*
                 * One byte of frame data. ID3v2.3 frame sizes are
                 * ordinary U32BE values.
                 */
                0x00, 0x00, 0x00, 0x01,

                statusFlags,
                0x00
            ];


        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );


        auto result =
            cursor.parseId3v23FrameHeader();


        assert(
            result.hasValue
        );


        assert(
            cursor.empty
        );


        return
            result.value;
    }
}


/// An unchanged enclosing object preserves an unregenerable frame.
unittest
{
    const header =
        testHeader(
            0xE0
        );


    const action =
        decideId3v23UnregenerableFrameAction(
            header,
            Id3v23WriteContext.unchanged()
        );


    assert(
        action ==
        Id3v23UnregenerableFrameAction
            .preserveOriginal
    );
}


/// An ordinary unknown frame without discard flags remains preserved.
unittest
{
    const header =
        testHeader(
            0x00
        );


    const action =
        decideId3v23UnregenerableFrameAction(
            header,
            Id3v23WriteContext.tagAndFile()
        );


    assert(
        action ==
        Id3v23UnregenerableFrameAction
            .preserveOriginal
    );
}


/// Tag alteration requiring discard rejects loss by default.
unittest
{
    const header =
        testHeader(
            0x80
        );


    const action =
        decideId3v23UnregenerableFrameAction(
            header,
            Id3v23WriteContext.tagOnly()
        );


    assert(
        action ==
        Id3v23UnregenerableFrameAction
            .rejectWrite
    );
}


/// File alteration requiring discard likewise rejects loss by default.
unittest
{
    const header =
        testHeader(
            0x40
        );


    const action =
        decideId3v23UnregenerableFrameAction(
            header,
            Id3v23WriteContext.fileOnly()
        );


    assert(
        action ==
        Id3v23UnregenerableFrameAction
            .rejectWrite
    );
}


/// Explicit caller policy may permit a required native-frame discard.
unittest
{
    const header =
        testHeader(
            0x80
        );


    auto policy =
        Id3v23WriterPolicy.init;


    policy.requiredDiscard =
        Id3v23RequiredDiscardPolicy.discard;


    const action =
        decideId3v23UnregenerableFrameAction(
            header,
            Id3v23WriteContext.tagOnly(),
            policy
        );


    assert(
        action ==
        Id3v23UnregenerableFrameAction
            .discard
    );
}


/// Tag-alter and file-alter preservation flags remain independent.
unittest
{
    const tagSensitive =
        testHeader(
            0x80
        );


    assert(
        decideId3v23UnregenerableFrameAction(
            tagSensitive,
            Id3v23WriteContext.fileOnly()
        ) ==
        Id3v23UnregenerableFrameAction
            .preserveOriginal
    );


    const fileSensitive =
        testHeader(
            0x40
        );


    assert(
        decideId3v23UnregenerableFrameAction(
            fileSensitive,
            Id3v23WriteContext.tagOnly()
        ) ==
        Id3v23UnregenerableFrameAction
            .preserveOriginal
    );
}


/// A writable mapped frame may be regenerated.
unittest
{
    const header =
        testHeader(
            0x00
        );


    assert(
        decideId3v23MappedFrameModificationAction(
            header
        ) ==
        Id3v23MappedFrameModificationAction
            .regenerate
    );
}


/// A native read-only frame rejects canonical modification.
unittest
{
    const header =
        testHeader(
            0x20
        );


    assert(
        header.readOnly
    );


    assert(
        decideId3v23MappedFrameModificationAction(
            header
        ) ==
        Id3v23MappedFrameModificationAction
            .rejectWrite
    );
}
