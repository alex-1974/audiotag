/++
High-level consumer API for same-version ID3v2.3 editing and
serialization.

This module deliberately hides semantic write-plan construction from
ordinary library consumers.

A caller supplies:

- one canonically parsed ID3v2.3 tag;
- one canonical edit overlay;
- optionally a native preservation policy.

The write context is derived conservatively:

- an unchanged edit uses `Id3v23WriteContext.unchanged()`;
- a changed edit uses `Id3v23WriteContext.tagOnly()`.

This layer never assumes that the containing audio file is being
modified. File-level alteration semantics belong to a future container
layer such as `audiotag.mp3`.

No file or container I/O is performed here.
+/
module audiotag.id3v2.v23.api;

import audiotag.metadata.edit :
    MetadataTreeEdit;

import audiotag.id3v2.v23.canonical_tag :
    Id3v23CanonicalTag;

import audiotag.id3v2.v23.tag_write :
    Id3v23TagSerializationResult,
    serializeId3v23PlannedTag;

import audiotag.id3v2.v23.tag_write_plan :
    planId3v23CanonicalTagWrite;

import audiotag.id3v2.v23.writer_policy :
    Id3v23WriteContext,
    Id3v23WriterPolicy;


/++
Serializes one canonically parsed ID3v2.3 tag after applying a canonical
edit overlay.

Semantic write planning is performed internally. Ordinary callers do
not need to construct or inspect `Id3v23TagWritePlan`.

An unchanged edit is planned as an unchanged enclosing tag. Any
canonical modification is planned as a tag-only alteration. This
function deliberately never marks the containing file as altered.

Params:
    tag = Parsed native-plus-canonical ID3v2.3 source tag.
    edit = Canonical edit overlay associated with `tag.projection.metadata`.
    policy = Native-frame preservation/discard policy.

Returns:
    Complete owned ID3v2.3 tag bytes, an outer source-parse failure, or
    an inner serialization/planning failure.
+/
Id3v23TagSerializationResult
serializeId3v23Tag(
    const(Id3v23CanonicalTag) tag,
    const(MetadataTreeEdit) edit,
    Id3v23WriterPolicy policy =
        Id3v23WriterPolicy.init
)
    @safe
{
    const context =
        edit.unchanged
            ? Id3v23WriteContext.unchanged()
            : Id3v23WriteContext.tagOnly();

    const plan =
        planId3v23CanonicalTagWrite(
            tag.projection,
            edit,
            context,
            policy
        );

    return
        serializeId3v23PlannedTag(
            tag.structure,
            tag.projection,
            edit,
            plan
        );
}


version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.span :
        ByteSpan;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;

    import audiotag.id3v2.v23.canonical_tag :
        parseId3v23CanonicalTag;
}


/// A no-op edit roundtrips one complete canonical ID3v2.3 tag.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'U'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto parsed =
        cursor.parseId3v23CanonicalTag();

    assert(parsed.hasValue);
    assert(cursor.empty);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value
                .projection
                .metadata
        );

    assert(edit.unchanged);

    auto written =
        serializeId3v23Tag(
            parsed.value,
            edit
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    assert(
        written.value.value ==
        bytes
    );
}


/// A canonical modification is serialized as a tag-only alteration.
unittest
{
    const ubyte[] bytes =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'U'
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(bytes)
        );

    auto parsed =
        cursor.parseId3v23CanonicalTag();

    assert(parsed.hasValue);
    assert(cursor.empty);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value
                .projection
                .metadata
        );

    MetadataValue value =
        MetadataText("V");

    edit.replaceSourceField(
        0,
        MetadataField(
            MetadataKey("title"),
            value
        )
    );

    assert(!edit.unchanged);

    auto written =
        serializeId3v23Tag(
            parsed.value,
            edit
        );

    assert(written.hasValue);
    assert(written.value.hasValue);

    const ubyte[] expected =
        [
            'I', 'D', '3',
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0C,

            'T', 'I', 'T', '2',
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 'V'
        ];

    assert(
        written.value.value ==
        expected
    );
}
