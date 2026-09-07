/++
Format-independent ID3v2 writer preservation policy.

ID3v2 revisions decode their native frame status bits into semantic
frame-header properties such as:

- `discardOnTagAlter`
- `discardOnFileAlter`
- `readOnly`

Writer policy operates only on those semantic properties and therefore
does not depend on revision-specific raw flag positions.

No bytes are emitted here.
+/
module audiotag.id3v2.common.writer_policy;


/++
Describes which enclosing object is being altered by a write.

Tag alteration and alteration of the containing file are independent
policy dimensions.
+/
struct Id3v2WriteContext
{
    /// Whether the ID3v2 tag itself is being altered.
    bool tagAltered;

    /// Whether the containing file outside the tag is being altered.
    bool fileAltered;


    /// Constructs a context in which neither tag nor file content changes.
    static Id3v2WriteContext unchanged()
        @safe pure nothrow @nogc
    {
        return
            Id3v2WriteContext(
                false,
                false
            );
    }


    /// Constructs a tag-only alteration context.
    static Id3v2WriteContext tagOnly()
        @safe pure nothrow @nogc
    {
        return
            Id3v2WriteContext(
                true,
                false
            );
    }


    /// Constructs a file-only alteration context.
    static Id3v2WriteContext fileOnly()
        @safe pure nothrow @nogc
    {
        return
            Id3v2WriteContext(
                false,
                true
            );
    }


    /// Constructs a context in which both tag and containing file change.
    static Id3v2WriteContext tagAndFile()
        @safe pure nothrow @nogc
    {
        return
            Id3v2WriteContext(
                true,
                true
            );
    }
}


/++
Policy applied when native frame flags require discarding a frame that
cannot be regenerated safely.
+/
enum Id3v2RequiredDiscardPolicy : ubyte
{
    /// Reject rather than silently lose native metadata.
    rejectWrite,

    /// Explicitly permit the required discard.
    discard
}


/++
Writer preservation policy for existing ID3v2 native frames.
+/
struct Id3v2WriterPolicy
{
    Id3v2RequiredDiscardPolicy requiredDiscard =
        Id3v2RequiredDiscardPolicy.rejectWrite;
}


/++
Action for an unsupported or otherwise non-regenerable existing frame.
+/
enum Id3v2UnregenerableFrameAction : ubyte
{
    preserveOriginal,
    discard,
    rejectWrite
}


/++
Determines how a non-regenerable native frame must be handled.

`Header` must expose the semantic boolean properties
`discardOnTagAlter` and `discardOnFileAlter`.
+/
Id3v2UnregenerableFrameAction
decideId3v2UnregenerableFrameAction(Header)(
    const(Header) header,
    Id3v2WriteContext context,
    Id3v2WriterPolicy policy =
        Id3v2WriterPolicy.init
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
            Id3v2UnregenerableFrameAction
                .preserveOriginal;
    }

    final switch (policy.requiredDiscard)
    {
        case Id3v2RequiredDiscardPolicy.rejectWrite:
            return
                Id3v2UnregenerableFrameAction
                    .rejectWrite;

        case Id3v2RequiredDiscardPolicy.discard:
            return
                Id3v2UnregenerableFrameAction
                    .discard;
    }
}


/++
Action allowed when a mapped canonical field requires modification of
its existing native frame.
+/
enum Id3v2MappedFrameModificationAction : ubyte
{
    regenerate,
    rejectWrite
}


/++
Determines whether an existing mapped frame may be regenerated.

`Header` must expose the semantic boolean property `readOnly`.
+/
Id3v2MappedFrameModificationAction
decideId3v2MappedFrameModificationAction(Header)(
    const(Header) header
)
    @safe pure nothrow @nogc
{
    if (header.readOnly)
    {
        return
            Id3v2MappedFrameModificationAction
                .rejectWrite;
    }

    return
        Id3v2MappedFrameModificationAction
            .regenerate;
}
