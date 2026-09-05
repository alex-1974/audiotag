/++
ID3v2.4 writer preservation policy.

This module defines decisions that must be made before byte
serialization begins.

Native ID3v2.4 frames may carry status flags describing what should
happen when the enclosing tag or file is altered. Frames may also be
marked read-only.

The writer must additionally protect the library-level invariant that
metadata is not silently discarded. Therefore the default policy
rejects a write when an unsupported or otherwise non-regenerable frame
would have to be discarded because of its native preservation flags.

No bytes are emitted by this module.
+/
module audiotag.id3v2.v24.writer_policy;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;


/++
Describes which enclosing object is being altered by a write.

The two dimensions are independent because ID3v2.4 distinguishes tag
alteration from alteration of the containing file outside the tag.
+/
struct Id3v24WriteContext
{
    /// Whether the ID3 tag itself is being altered.
    bool tagAltered;

    /// Whether the containing file outside the tag is being altered.
    bool fileAltered;

    /++
    Constructs a context in which neither tag nor file content changes.
    +/
    static Id3v24WriteContext unchanged()
        @safe pure nothrow @nogc
    {
        return Id3v24WriteContext(
            false,
            false
        );
    }

    /++
    Constructs a tag-only alteration context.
    +/
    static Id3v24WriteContext tagOnly()
        @safe pure nothrow @nogc
    {
        return Id3v24WriteContext(
            true,
            false
        );
    }

    /++
    Constructs a file-only alteration context.
    +/
    static Id3v24WriteContext fileOnly()
        @safe pure nothrow @nogc
    {
        return Id3v24WriteContext(
            false,
            true
        );
    }

    /++
    Constructs a context in which both tag and containing file change.
    +/
    static Id3v24WriteContext tagAndFile()
        @safe pure nothrow @nogc
    {
        return Id3v24WriteContext(
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
enum Id3v24RequiredDiscardPolicy : ubyte
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
struct Id3v24WriterPolicy
{
    /// Behavior when an unregenerable frame is required to be discarded.
    Id3v24RequiredDiscardPolicy requiredDiscard =
        Id3v24RequiredDiscardPolicy.rejectWrite;
}


/++
Action for an unsupported or otherwise non-regenerable native frame.

Such a frame cannot currently be reconstructed from canonical metadata,
so the writer can only preserve its original physical bytes, discard it
when permitted by policy, or reject the write.
+/
enum Id3v24UnregenerableFrameAction : ubyte
{
    preserveOriginal,
    discard,
    rejectWrite
}


/++
Determines how an unsupported or otherwise non-regenerable native frame
must be handled in the given write context.

The ID3v2.4 tag-alter and file-alter preservation flags are consulted
only because the caller has already determined that this frame cannot
be safely regenerated.

When neither applicable preservation flag requires discarding the
frame, its exact original bytes are retained.

If discarding is required, the writer policy decides whether the write
must fail or whether the loss is explicitly permitted.

Params:
    header = Native frame header carrying preservation flags.
    context = Enclosing tag/file alteration state.
    policy = Writer preservation policy.

Returns:
    Required preservation action.
+/
Id3v24UnregenerableFrameAction
decideId3v24UnregenerableFrameAction(
    Id3v24FrameHeader header,
    Id3v24WriteContext context,
    Id3v24WriterPolicy policy =
        Id3v24WriterPolicy.init
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

    if (!discardRequired)
    {
        return
            Id3v24UnregenerableFrameAction
                .preserveOriginal;
    }

    final switch (policy.requiredDiscard)
    {
        case Id3v24RequiredDiscardPolicy.rejectWrite:
            return
                Id3v24UnregenerableFrameAction
                    .rejectWrite;

        case Id3v24RequiredDiscardPolicy.discard:
            return
                Id3v24UnregenerableFrameAction
                    .discard;
    }
}


/++
Action when a mapped native frame is requested to be regenerated from
modified canonical metadata.
+/
enum Id3v24MappedFrameModificationAction : ubyte
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
Id3v24MappedFrameModificationAction
decideId3v24MappedFrameModificationAction(
    Id3v24FrameHeader header
)
    @safe pure nothrow @nogc
{
    if (header.readOnly)
    {
        return
            Id3v24MappedFrameModificationAction
                .rejectWrite;
    }

    return
        Id3v24MappedFrameModificationAction
            .regenerate;
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame_header :
        parseId3v24FrameHeader;


    private Id3v24FrameHeader testHeader(
        ubyte statusFlags
    )
        @safe
    {
        const ubyte[] bytes =
            [
                'A', 'B', 'C', '1',
                0x00, 0x00, 0x00, 0x01,
                statusFlags,
                0x00
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto result =
            cursor.parseId3v24FrameHeader();

        assert(result.hasValue);
        assert(cursor.empty);

        return result.value;
    }
}


/// An unchanged enclosing object preserves an unregenerable frame.
unittest
{
    const header =
        testHeader(0x70);

    const action =
        decideId3v24UnregenerableFrameAction(
            header,
            Id3v24WriteContext.unchanged()
        );

    assert(
        action ==
        Id3v24UnregenerableFrameAction
            .preserveOriginal
    );
}


/// An ordinary unknown frame without discard flags remains preserved.
unittest
{
    const header =
        testHeader(0x00);

    const action =
        decideId3v24UnregenerableFrameAction(
            header,
            Id3v24WriteContext.tagAndFile()
        );

    assert(
        action ==
        Id3v24UnregenerableFrameAction
            .preserveOriginal
    );
}


/// Tag alteration requiring discard rejects loss by default.
unittest
{
    const header =
        testHeader(0x40);

    const action =
        decideId3v24UnregenerableFrameAction(
            header,
            Id3v24WriteContext.tagOnly()
        );

    assert(
        action ==
        Id3v24UnregenerableFrameAction
            .rejectWrite
    );
}


/// File alteration requiring discard likewise rejects loss by default.
unittest
{
    const header =
        testHeader(0x20);

    const action =
        decideId3v24UnregenerableFrameAction(
            header,
            Id3v24WriteContext.fileOnly()
        );

    assert(
        action ==
        Id3v24UnregenerableFrameAction
            .rejectWrite
    );
}


/// Explicit caller policy may permit a required native-frame discard.
unittest
{
    const header =
        testHeader(0x40);

    auto policy =
        Id3v24WriterPolicy.init;

    policy.requiredDiscard =
        Id3v24RequiredDiscardPolicy.discard;

    const action =
        decideId3v24UnregenerableFrameAction(
            header,
            Id3v24WriteContext.tagOnly(),
            policy
        );

    assert(
        action ==
        Id3v24UnregenerableFrameAction
            .discard
    );
}


/// Tag-alter and file-alter preservation flags remain independent.
unittest
{
    const tagSensitive =
        testHeader(0x40);

    assert(
        decideId3v24UnregenerableFrameAction(
            tagSensitive,
            Id3v24WriteContext.fileOnly()
        ) ==
        Id3v24UnregenerableFrameAction
            .preserveOriginal
    );

    const fileSensitive =
        testHeader(0x20);

    assert(
        decideId3v24UnregenerableFrameAction(
            fileSensitive,
            Id3v24WriteContext.tagOnly()
        ) ==
        Id3v24UnregenerableFrameAction
            .preserveOriginal
    );
}


/// A writable mapped frame may be regenerated.
unittest
{
    const header =
        testHeader(0x00);

    assert(
        decideId3v24MappedFrameModificationAction(
            header
        ) ==
        Id3v24MappedFrameModificationAction
            .regenerate
    );
}


/// A native read-only frame rejects canonical modification.
unittest
{
    const header =
        testHeader(0x10);

    assert(header.readOnly);

    assert(
        decideId3v24MappedFrameModificationAction(
            header
        ) ==
        Id3v24MappedFrameModificationAction
            .rejectWrite
    );
}
