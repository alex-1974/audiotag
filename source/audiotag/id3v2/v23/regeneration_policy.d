/++
Structural flag policy for regenerating an existing mapped ID3v2.3
frame from modified canonical metadata.

Unchanged frames never pass through this policy; they retain their
complete original physical bytes.

For a regenerated mapped frame the current conservative rules are:

Status flags:
- tag-alter preservation: preserve;
- file-alter preservation: preserve;
- read-only: reject modification.

Format flags:
- grouping identity: preserve, including the logical group byte;
- compression: reject until compression writing exists;
- encryption: reject until encryption writing exists.

ID3v2.3 has neither frame-level unsynchronisation nor a Data Length
Indicator.

Whole-tag unsynchronisation is a later tag-serialization concern. The
`tagUnsynchronised` parameter is used only to decode the original
frame-data layout correctly.

No bytes are serialized here.
+/
module audiotag.id3v2.v23.regeneration_policy;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v23.frame :
    Id3v23FrameEnvelope;

import audiotag.id3v2.v23.frame_data :
    parseId3v23FrameDataLayout;


/++
Disposition of one native structural feature during regeneration.

`recompute` and `clear` are included in the policy vocabulary even
though the current ID3v2.3 rules require only `preserve` and `reject`.
+/
enum Id3v23RegenerationFlagDisposition : ubyte
{
    preserve,
    recompute,
    clear,
    reject
}


/++
Documented default rules for existing mapped-frame regeneration.

These compile-time values make structural preservation decisions
explicit rather than hiding them inside physical serializers.
+/
struct Id3v23MappedFrameRegenerationRules
{
    enum Id3v23RegenerationFlagDisposition discardOnTagAlter =
        Id3v23RegenerationFlagDisposition.preserve;

    enum Id3v23RegenerationFlagDisposition discardOnFileAlter =
        Id3v23RegenerationFlagDisposition.preserve;

    enum Id3v23RegenerationFlagDisposition readOnly =
        Id3v23RegenerationFlagDisposition.reject;

    enum Id3v23RegenerationFlagDisposition groupingIdentity =
        Id3v23RegenerationFlagDisposition.preserve;

    enum Id3v23RegenerationFlagDisposition compression =
        Id3v23RegenerationFlagDisposition.reject;

    enum Id3v23RegenerationFlagDisposition encryption =
        Id3v23RegenerationFlagDisposition.reject;
}


/++
Semantic availability of structural regeneration for one existing
mapped native frame.

These are writer-policy outcomes, not parse errors. A malformed source
layout is still returned through `ParseResult`.
+/
enum Id3v23MappedFrameRegenerationStatus : ubyte
{
    ready,

    /// Original frame is marked read-only.
    readOnly,

    /// Original semantic representation depends on compression.
    compressionUnsupported,

    /// Original semantic representation depends on encryption.
    encryptionUnsupported,

    /// Original semantic representation depends on both transformations.
    compressionAndEncryptionUnsupported
}


/++
Structural output plan for one regenerated mapped ID3v2.3 frame.

`statusFlags` and `formatFlags` are the flags that a future regenerated
frame header should use.

When `hasGroupingIdentity` is true, `groupingIdentity` must be written
after any other ID3v2.3 frame-format additions and before the semantic
payload.

Compression and encryption additions are deliberately absent from the
output plan because regeneration is rejected while either transformation
is required.
+/
struct Id3v23MappedFrameRegenerationFormatPlan
{
    /// Whether structural regeneration is currently supported.
    Id3v23MappedFrameRegenerationStatus status;

    /// Output status flags for the regenerated frame.
    ubyte statusFlags;

    /// Output format flags before any future whole-tag transformation.
    ubyte formatFlags;

    /// Whether the native grouping byte must be retained.
    bool hasGroupingIdentity;

    /// Logical grouping identifier when present.
    ubyte groupingIdentity;

    /++
    Returns whether this structural representation may be regenerated.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v23MappedFrameRegenerationStatus.ready;
    }
}


/++
Plans structural flags for regeneration of one existing mapped frame.

The function reparses only the already bounded frame-data layout needed
to recover structural context such as grouping identity.

Compression and encryption are valid source metadata but cannot
currently be regenerated. They therefore return successful plans whose
`writable` property is false.

The returned output flags are rebuilt explicitly. Compression and
encryption flags are therefore never copied accidentally into
regenerated untransformed frame data.

Params:
    frame = Original bounded native frame.
    tagUnsynchronised = Whether ID3v2.3 whole-tag unsynchronisation
        applied while reading the source frame.

Returns:
    Structural regeneration plan, or a source `ParseError` if the
    supplied frame envelope does not contain a valid frame-data layout.
+/
ParseResult!Id3v23MappedFrameRegenerationFormatPlan
planId3v23MappedFrameRegenerationFormat(
    Id3v23FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    auto layoutResult =
        frame.parseId3v23FrameDataLayout(
            tagUnsynchronised
        );

    if (layoutResult.hasError)
    {
        return
            ParseResult!Id3v23MappedFrameRegenerationFormatPlan
                .failure(
                    layoutResult.error
                );
    }

    const layout =
        layoutResult.value;

    Id3v23MappedFrameRegenerationFormatPlan result;

    /*
     * Preserve the two meaningful alteration-status bits.
     *
     * Read-only itself is never copied into a regenerated frame because
     * regeneration is rejected when that bit was set.
     */
    result.statusFlags =
        frame.header.statusFlags &
        0xC0;

    /*
     * Rebuild format flags rather than copying the original byte.
     *
     * Compression and encryption are unsupported for regenerated output,
     * so only grouping may survive into a writable representation.
     */
    if (layout.hasGroupingIdentity)
    {
        result.formatFlags |= 0x20;

        result.hasGroupingIdentity =
            true;

        result.groupingIdentity =
            layout.groupingIdentity;
    }

    if (frame.header.readOnly)
    {
        result.status =
            Id3v23MappedFrameRegenerationStatus
                .readOnly;

        return
            ParseResult!Id3v23MappedFrameRegenerationFormatPlan
                .success(result);
    }

    if (
        frame.header.compressed &&
        frame.header.encrypted
    )
    {
        result.status =
            Id3v23MappedFrameRegenerationStatus
                .compressionAndEncryptionUnsupported;

        return
            ParseResult!Id3v23MappedFrameRegenerationFormatPlan
                .success(result);
    }

    if (frame.header.compressed)
    {
        result.status =
            Id3v23MappedFrameRegenerationStatus
                .compressionUnsupported;

        return
            ParseResult!Id3v23MappedFrameRegenerationFormatPlan
                .success(result);
    }

    if (frame.header.encrypted)
    {
        result.status =
            Id3v23MappedFrameRegenerationStatus
                .encryptionUnsupported;

        return
            ParseResult!Id3v23MappedFrameRegenerationFormatPlan
                .success(result);
    }

    result.status =
        Id3v23MappedFrameRegenerationStatus.ready;

    return
        ParseResult!Id3v23MappedFrameRegenerationFormatPlan
            .success(result);
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v23.data_cursor :
        Id3v23DataCursor;

    import audiotag.id3v2.v23.frame :
        parseId3v23FrameEnvelope;


    private Id3v23FrameEnvelope testFrame(
        const(ubyte)[] bytes,
        bool tagUnsynchronised = false
    )
        @safe
    {
        auto cursor =
            Id3v23DataCursor(
                ByteSpan(bytes),
                tagUnsynchronised
            );

        auto parsed =
            cursor.parseId3v23FrameEnvelope();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// Regeneration rules are explicit compile-time policy.
unittest
{
    alias R =
        Id3v23MappedFrameRegenerationRules;

    assert(
        R.discardOnTagAlter ==
        Id3v23RegenerationFlagDisposition.preserve
    );

    assert(
        R.discardOnFileAlter ==
        Id3v23RegenerationFlagDisposition.preserve
    );

    assert(
        R.readOnly ==
        Id3v23RegenerationFlagDisposition.reject
    );

    assert(
        R.groupingIdentity ==
        Id3v23RegenerationFlagDisposition.preserve
    );

    assert(
        R.compression ==
        Id3v23RegenerationFlagDisposition.reject
    );

    assert(
        R.encryption ==
        Id3v23RegenerationFlagDisposition.reject
    );
}


/// A plain writable source frame regenerates with plain flags.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,

            0x00, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);
    assert(plan.statusFlags == 0);
    assert(plan.formatFlags == 0);
    assert(!plan.hasGroupingIdentity);
}


/// Tag/file alteration status bits survive regeneration.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0xC0, 0x00,

            0x00, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(planned.value.writable);

    assert(
        planned.value.statusFlags ==
        0xC0
    );
}


/// Grouping identity survives with its logical group byte.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x20,

            0x12,
            0x00, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);
    assert(plan.formatFlags == 0x20);
    assert(plan.hasGroupingIdentity);
    assert(plan.groupingIdentity == 0x12);
}


/// Grouping is recovered from the logical whole-tag-unsynchronised stream.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x20,

            /*
             * Logical data is:
             *
             *   FF 00
             *
             * Physical whole-tag unsynchronisation inserts one 00 after FF.
             */
            0xFF, 0x00, 0x00
        ];

    const frame =
        testFrame(
            bytes,
            true
        );

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame,
            true
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);
    assert(plan.formatFlags == 0x20);
    assert(plan.hasGroupingIdentity);
    assert(plan.groupingIdentity == 0xFF);
}


/// Read-only mapped frames remain an explicit regeneration rejection.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x20, 0x00,

            0x00, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v23MappedFrameRegenerationStatus
            .readOnly
    );

    /*
     * The read-only bit is not part of any hypothetical regenerated
     * output header.
     */
    assert(planned.value.statusFlags == 0);
}


/// Compression remains valid source metadata but cannot yet regenerate.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x80,

            // Declared decompressed size.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0x55
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v23MappedFrameRegenerationStatus
            .compressionUnsupported
    );

    assert(planned.value.formatFlags == 0);
}


/// Encryption likewise remains an explicit unsupported transformation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x40,

            // Encryption method.
            0x23,

            // Opaque encrypted payload.
            0x55
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v23MappedFrameRegenerationStatus
            .encryptionUnsupported
    );

    assert(planned.value.formatFlags == 0);
}


/// Combined compression and encryption retain a distinct rejection reason.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0xC0,

            // Declared decompressed size.
            0x00, 0x00, 0x00, 0x01,

            // Encryption method.
            0x23,

            // Opaque transformed payload.
            0x55
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v23MappedFrameRegenerationStatus
            .compressionAndEncryptionUnsupported
    );
}


/// Malformed required format additions remain parse errors.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x80,

            // Too short for the required four-byte decompressed-size field.
            0x55
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v23MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasError);
}
