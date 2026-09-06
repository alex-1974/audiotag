/++
Structural flag policy for regenerating an existing mapped ID3v2.4
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
- encryption: reject until encryption writing exists;
- frame-level unsynchronisation: clear and regenerate normal logical
  frame data;
- Data Length Indicator: preserve its presence but recompute its value
  from the regenerated semantic payload.

Tag-level unsynchronisation is a later whole-tag serialization concern.
The `tagUnsynchronised` parameter is used only to decode the original
frame-data layout correctly.

No bytes are serialized here.
+/
module audiotag.id3v2.v24.regeneration_policy;

import audiotag.core.result :
    ParseResult;

import audiotag.id3v2.v24.frame :
    Id3v24FrameEnvelope;

import audiotag.id3v2.v24.frame_data :
    parseId3v24FrameDataLayout;


/++
Disposition of one native structural feature during regeneration.

`recompute` means that the feature remains present but its value is
derived again from the new representation rather than copied from the
source.
+/
enum Id3v24RegenerationFlagDisposition : ubyte
{
    preserve,
    recompute,
    clear,
    reject
}


/++
Documented default rules for existing mapped-frame regeneration.

These compile-time values make structural normalization decisions
explicit rather than hiding them inside serializers.
+/
struct Id3v24MappedFrameRegenerationRules
{
    enum Id3v24RegenerationFlagDisposition discardOnTagAlter =
        Id3v24RegenerationFlagDisposition.preserve;

    enum Id3v24RegenerationFlagDisposition discardOnFileAlter =
        Id3v24RegenerationFlagDisposition.preserve;

    enum Id3v24RegenerationFlagDisposition readOnly =
        Id3v24RegenerationFlagDisposition.reject;

    enum Id3v24RegenerationFlagDisposition groupingIdentity =
        Id3v24RegenerationFlagDisposition.preserve;

    enum Id3v24RegenerationFlagDisposition compression =
        Id3v24RegenerationFlagDisposition.reject;

    enum Id3v24RegenerationFlagDisposition encryption =
        Id3v24RegenerationFlagDisposition.reject;

    enum Id3v24RegenerationFlagDisposition unsynchronisation =
        Id3v24RegenerationFlagDisposition.clear;

    enum Id3v24RegenerationFlagDisposition dataLengthIndicator =
        Id3v24RegenerationFlagDisposition.recompute;
}


/++
Semantic availability of structural regeneration for one existing
mapped native frame.

These are writer-policy outcomes, not parse errors. A malformed source
layout is still returned through `ParseResult`.
+/
enum Id3v24MappedFrameRegenerationStatus : ubyte
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
Structural output plan for one regenerated mapped frame.

`statusFlags` and `formatFlags` are the flags that a future regenerated
frame header should use.

When `hasGroupingIdentity` is true, `groupingIdentity` must be written
before the semantic payload.

When `hasDataLengthIndicator` is true, a future serializer must emit a
new DLI. The original DLI value is deliberately not retained because it
describes the old representation.
+/
struct Id3v24MappedFrameRegenerationFormatPlan
{
    /// Whether structural regeneration is currently supported.
    Id3v24MappedFrameRegenerationStatus status;

    /// Output status flags for the regenerated frame.
    ubyte statusFlags;

    /// Output format flags before any future whole-tag transformation.
    ubyte formatFlags;

    /// Whether the native grouping byte must be retained.
    bool hasGroupingIdentity;

    /// Logical grouping identifier when present.
    ubyte groupingIdentity;

    /// Whether a DLI must be emitted and recomputed.
    bool hasDataLengthIndicator;

    /++
    Returns whether this structural representation may be regenerated.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v24MappedFrameRegenerationStatus.ready;
    }
}


/++
Plans structural flags for regeneration of one existing mapped frame.

The function reparses only the already bounded frame-data layout needed
to recover structural context such as grouping identity and DLI
presence.

Compression and encryption are valid source metadata but cannot
currently be regenerated. They therefore return successful plans whose
`writable` property is false.

Params:
    frame = Original bounded native frame.
    tagUnsynchronised = Whether tag-level unsynchronisation applied while
        reading the source frame.

Returns:
    Structural regeneration plan, or a source `ParseError` if the supplied
    frame envelope does not contain a valid frame-data layout.
+/
ParseResult!Id3v24MappedFrameRegenerationFormatPlan
planId3v24MappedFrameRegenerationFormat(
    Id3v24FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe pure nothrow @nogc
{
    auto layoutResult =
        frame.parseId3v24FrameDataLayout(
            tagUnsynchronised
        );

    if (layoutResult.hasError)
    {
        return
            ParseResult!Id3v24MappedFrameRegenerationFormatPlan
                .failure(
                    layoutResult.error
                );
    }

    const layout =
        layoutResult.value;

    Id3v24MappedFrameRegenerationFormatPlan result;

    /*
     * Preserve the two meaningful preservation-status bits.
     *
     * Read-only itself is never copied into a regenerated frame because
     * regeneration is rejected when that bit was set.
     */
    result.statusFlags =
        frame.header.statusFlags &
        0x60;

    /*
     * Rebuild format flags explicitly rather than copying the original
     * byte. Compression, encryption and frame-level unsynchronisation
     * therefore cannot leak accidentally into regenerated data.
     */
    if (layout.hasGroupingIdentity)
    {
        result.formatFlags |= 0x40;

        result.hasGroupingIdentity = true;
        result.groupingIdentity =
            layout.groupingIdentity;
    }

    /*
     * Preserve DLI presence but never the old value. The future frame
     * serializer must recompute it from the regenerated semantic data.
     */
    if (layout.hasDataLengthIndicator)
    {
        result.formatFlags |= 0x01;
        result.hasDataLengthIndicator = true;
    }

    if (frame.header.readOnly)
    {
        result.status =
            Id3v24MappedFrameRegenerationStatus
                .readOnly;

        return
            ParseResult!Id3v24MappedFrameRegenerationFormatPlan
                .success(result);
    }

    if (
        frame.header.compressed &&
        frame.header.encrypted
    )
    {
        result.status =
            Id3v24MappedFrameRegenerationStatus
                .compressionAndEncryptionUnsupported;

        return
            ParseResult!Id3v24MappedFrameRegenerationFormatPlan
                .success(result);
    }

    if (frame.header.compressed)
    {
        result.status =
            Id3v24MappedFrameRegenerationStatus
                .compressionUnsupported;

        return
            ParseResult!Id3v24MappedFrameRegenerationFormatPlan
                .success(result);
    }

    if (frame.header.encrypted)
    {
        result.status =
            Id3v24MappedFrameRegenerationStatus
                .encryptionUnsupported;

        return
            ParseResult!Id3v24MappedFrameRegenerationFormatPlan
                .success(result);
    }

    result.status =
        Id3v24MappedFrameRegenerationStatus.ready;

    return
        ParseResult!Id3v24MappedFrameRegenerationFormatPlan
            .success(result);
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v2.v24.frame :
        parseId3v24FrameEnvelope;


    private Id3v24FrameEnvelope testFrame(
        const(ubyte)[] bytes
    )
        @safe
    {
        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            cursor.parseId3v24FrameEnvelope();

        assert(parsed.hasValue);
        assert(cursor.empty);

        return parsed.value;
    }
}


/// Regeneration rules are explicit compile-time policy.
unittest
{
    alias R =
        Id3v24MappedFrameRegenerationRules;

    assert(
        R.discardOnTagAlter ==
        Id3v24RegenerationFlagDisposition.preserve
    );

    assert(
        R.discardOnFileAlter ==
        Id3v24RegenerationFlagDisposition.preserve
    );

    assert(
        R.readOnly ==
        Id3v24RegenerationFlagDisposition.reject
    );

    assert(
        R.groupingIdentity ==
        Id3v24RegenerationFlagDisposition.preserve
    );

    assert(
        R.compression ==
        Id3v24RegenerationFlagDisposition.reject
    );

    assert(
        R.encryption ==
        Id3v24RegenerationFlagDisposition.reject
    );

    assert(
        R.unsynchronisation ==
        Id3v24RegenerationFlagDisposition.clear
    );

    assert(
        R.dataLengthIndicator ==
        Id3v24RegenerationFlagDisposition.recompute
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

            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);
    assert(plan.statusFlags == 0);
    assert(plan.formatFlags == 0);
    assert(!plan.hasGroupingIdentity);
    assert(!plan.hasDataLengthIndicator);
}


/// Tag/file preservation status bits survive regeneration.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x60, 0x00,

            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(planned.value.writable);

    assert(
        planned.value.statusFlags ==
        0x60
    );
}


/// Grouping identity survives with its logical group byte.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x03,
            0x00, 0x40,

            0x12,
            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);
    assert(plan.formatFlags == 0x40);
    assert(plan.hasGroupingIdentity);
    assert(plan.groupingIdentity == 0x12);
}


/// Logical grouping survives even when its source frame was unsynchronised.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x04,
            0x00, 0x42,

            // Logical grouping identity $FF with physical stuffing.
            0xFF, 0x00,

            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);

    // Grouping is retained, frame-level unsynchronisation is cleared.
    assert(plan.formatFlags == 0x40);

    assert(plan.hasGroupingIdentity);
    assert(plan.groupingIdentity == 0xFF);
}


/// DLI presence survives but its old numeric value is not part of the plan.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x01,

            // Original DLI = 2.
            0x00, 0x00, 0x00, 0x02,

            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);

    const plan =
        planned.value;

    assert(plan.writable);
    assert(plan.formatFlags == 0x01);
    assert(plan.hasDataLengthIndicator);
}


/// Frame-level unsynchronisation is normalized away during regeneration.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x02,

            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(planned.value.writable);

    assert(
        planned.value.formatFlags ==
        0x00
    );
}


/// Read-only mapped frames remain an explicit regeneration rejection.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x10, 0x00,

            0x03, 'X'
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v24MappedFrameRegenerationStatus
            .readOnly
    );
}


/// Compression remains valid source metadata but cannot yet regenerate.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x05,
            0x00, 0x09,

            // Required DLI.
            0x00, 0x00, 0x00, 0x01,

            // Opaque compressed payload.
            0x55
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v24MappedFrameRegenerationStatus
            .compressionUnsupported
    );
}


/// Encryption likewise remains an explicit unsupported transformation.
unittest
{
    const ubyte[] bytes =
        [
            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x04,

            // Encryption method.
            0x23,

            // Opaque encrypted payload.
            0x55
        ];

    const frame =
        testFrame(bytes);

    auto planned =
        planId3v24MappedFrameRegenerationFormat(
            frame
        );

    assert(planned.hasValue);
    assert(!planned.value.writable);

    assert(
        planned.value.status ==
        Id3v24MappedFrameRegenerationStatus
            .encryptionUnsupported
    );
}
