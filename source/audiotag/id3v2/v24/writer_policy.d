/++
ID3v2.4 bindings for the common ID3v2 writer preservation policy.

ID3v2.4 native status-bit positions are interpreted by the revision-
specific frame header. Writer policy consumes only the resulting
semantic header properties.

No bytes are emitted here.
+/
module audiotag.id3v2.v24.writer_policy;

import audiotag.id3v2.common.writer_policy :
    Id3v2MappedFrameModificationAction,
    Id3v2RequiredDiscardPolicy,
    Id3v2UnregenerableFrameAction,
    Id3v2WriteContext,
    Id3v2WriterPolicy,
    decideId3v2MappedFrameModificationAction,
    decideId3v2UnregenerableFrameAction;

import audiotag.id3v2.v24.frame_header :
    Id3v24FrameHeader;


/++
Revision-specific public name for the common ID3v2 write context.
+/
alias Id3v24WriteContext =
    Id3v2WriteContext;


/++
Revision-specific public name for the common required-discard policy.
+/
alias Id3v24RequiredDiscardPolicy =
    Id3v2RequiredDiscardPolicy;


/++
Revision-specific public name for the common ID3v2 writer policy.
+/
alias Id3v24WriterPolicy =
    Id3v2WriterPolicy;


/++
Revision-specific public name for the common non-regenerable-frame
action.
+/
alias Id3v24UnregenerableFrameAction =
    Id3v2UnregenerableFrameAction;


/++
Determines how an ID3v2.4 non-regenerable native frame must be handled.
+/
Id3v24UnregenerableFrameAction
decideId3v24UnregenerableFrameAction(
    const(Id3v24FrameHeader) header,
    Id3v24WriteContext context,
    Id3v24WriterPolicy policy =
        Id3v24WriterPolicy.init
)
    @safe pure nothrow @nogc
{
    return
        decideId3v2UnregenerableFrameAction(
            header,
            context,
            policy
        );
}


/++
Revision-specific public name for the common mapped-frame modification
action.
+/
alias Id3v24MappedFrameModificationAction =
    Id3v2MappedFrameModificationAction;


/++
Determines whether an existing mapped ID3v2.4 frame may be regenerated.
+/
Id3v24MappedFrameModificationAction
decideId3v24MappedFrameModificationAction(
    const(Id3v24FrameHeader) header
)
    @safe pure nothrow @nogc
{
    return
        decideId3v2MappedFrameModificationAction(
            header
        );
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
