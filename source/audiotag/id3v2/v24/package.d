/++
Public consumer surface for ID3v2.4 support.

Importing this package provides the ordinary same-version workflow:

- bounded ID3v2.4 parsing;
- canonical metadata inspection and editing;
- complete ID3v2.4 tag serialization within the currently supported
  writer capabilities;
- native preservation policy.

Revision-specific planning, frame assembly, regeneration and tag-body
implementation modules remain available for advanced direct imports but
are deliberately not re-exported here.

This package does not import ID3v2.3, conversion logic or any audio
container layer.
+/
module audiotag.id3v2.v24;


/*
 * Minimal format-independent primitives required by the high-level
 * consumer workflow.
 */
public import audiotag.core.cursor :
    ByteCursor;

public import audiotag.core.span :
    ByteSpan;

public import audiotag.core.error :
    ParseError,
    ParseErrorCode;

public import audiotag.core.result :
    ParseResult;

public import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;


/*
 * Canonical metadata types needed to construct and apply edits.
 */
public import audiotag.metadata.edit :
    MetadataSourceFieldEdit,
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

public import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

public import audiotag.metadata.value :
    MetadataText,
    MetadataValue;


/*
 * High-level ID3v2.4 parse and serialization entry points.
 */
public import audiotag.id3v2.v24.canonical_tag :
    Id3v24CanonicalTag,
    parseId3v24CanonicalTag;

public import audiotag.id3v2.v24.api :
    serializeId3v24Tag;

public import audiotag.id3v2.v24.tag_write :
    Id3v24TagSerializationResult;


/*
 * Normal caller-selectable preservation policy.
 *
 * Write context is intentionally not re-exported: the high-level
 * serializer derives tag-level context itself. Container-level file
 * alteration belongs to a container layer.
 */
public import audiotag.id3v2.v24.writer_policy :
    Id3v24RequiredDiscardPolicy,
    Id3v24WriterPolicy;


version (unittest)
{
    /*
     * This test intentionally uses only names exported through this
     * package module. It exercises the expected ordinary consumer path.
     */
    unittest
    {
        const ubyte[] bytes =
            [
                'I', 'D', '3',
                0x04, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x0C,

                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x02,
                0x00, 0x00,
                0x00, 'A'
            ];

        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );

        auto parsed =
            parseId3v24CanonicalTag(cursor);

        assert(parsed.hasValue);
        assert(cursor.empty);

        auto edit =
            MetadataTreeEdit.forSource(
                parsed.value
                    .projection
                    .metadata
            );

        MetadataValue value =
            MetadataText("B");

        edit.replaceSourceField(
            0,
            MetadataField(
                MetadataKey("title"),
                value
            )
        );

        auto written =
            serializeId3v24Tag(
                parsed.value,
                edit
            );

        assert(written.hasValue);
        assert(written.value.hasValue);

        const ubyte[] expected =
            [
                'I', 'D', '3',
                0x04, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x0C,

                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x02,
                0x00, 0x00,
                0x03, 'B'
            ];

        assert(
            written.value.value ==
            expected
        );
    }
}
