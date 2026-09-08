/++
Public consumer surface for ID3v2.3 support.

Importing this package provides the ordinary same-version workflow:

- bounded ID3v2.3 parsing;
- canonical metadata inspection and editing;
- complete ID3v2.3 tag serialization;
- optional CRC validation;
- native preservation policy.

Revision-specific planning, frame assembly, regeneration and tag-body
implementation modules remain available for advanced direct imports but
are deliberately not re-exported here.

This package does not import ID3v2.4, conversion logic or any audio
container layer.
+/
module audiotag.id3v2.v23;


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
 * High-level ID3v2.3 parse and serialization entry points.
 */
public import audiotag.id3v2.v23.canonical_tag :
    Id3v23CanonicalTag,
    parseId3v23CanonicalTag;

public import audiotag.id3v2.v23.api :
    serializeId3v23Tag;

public import audiotag.id3v2.v23.tag_write :
    Id3v23TagSerializationResult;


/*
 * Optional integrity validation.
 */
public import audiotag.id3v2.v23.crc_validation :
    Id3v23CrcValidationResult,
    Id3v23CrcValidationStatus;


/*
 * Normal caller-selectable preservation policy.
 *
 * Write context is intentionally not re-exported: the high-level
 * serializer derives tag-level context itself. Container-level file
 * alteration belongs to a container layer.
 */
public import audiotag.id3v2.v23.writer_policy :
    Id3v23RequiredDiscardPolicy,
    Id3v23WriterPolicy;


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
                0x03, 0x00,
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
            parseId3v23CanonicalTag(cursor);

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
                0x00, 'B'
            ];

        assert(
            written.value.value ==
            expected
        );
    }
}
