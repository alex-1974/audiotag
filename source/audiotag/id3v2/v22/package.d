/++
Public read-only consumer surface for ID3v2.2.0 support.

Importing this package provides the ordinary ID3v2.2 read workflow:

- bounded ID3v2.2.0 parsing;
- provenance-preserving native metadata;
- canonical metadata inspection;
- tag-wide conformance diagnostics.

ID3v2.2 writing is not implemented, so this package deliberately exposes no
serialization or edit-to-writer API.

Revision-specific structural parsers, individual frame codecs and projection
implementation modules remain available for advanced direct imports but are
deliberately not re-exported here.

Whole-tag-compressed ID3v2.2 bodies remain opaque because ID3v2.2 does not
standardize the compression representation. Such tags preserve their physical
body but report canonical projection and tag-level frame validation as
unavailable.

This package does not import other ID3 revisions, conversion logic or any audio
container layer.

Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22;


/*
 * Minimal format-independent primitives required by the high-level
 * read workflow.
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


/*
 * High-level ID3v2.2 native and canonical read entry points.
 */
public import audiotag.id3v2.v22.canonical_tag :
    Id3v22CanonicalTag,
    parseId3v22CanonicalTag;

public import audiotag.id3v2.v22.native_tag :
    Id3v22NativeTag,
    parseId3v22NativeTag;


/*
 * Tag-wide conformance result types needed by normal callers to inspect
 * semantic ID3v2.2.0 restrictions after a successful native parse.
 */
public import audiotag.id3v2.v22.tag_validation :
    Id3v22TagValidationCode,
    Id3v22TagValidationDiagnostic,
    Id3v22TagValidationReport,
    Id3v22TagValidationSeverity;


version (unittest)
{
    /*
     * This test intentionally uses only names exported through this package
     * module. It exercises the expected ordinary read-only consumer path.
     */
    unittest
    {
        const ubyte[] bytes =
            [
                'I', 'D', '3',
                0x02, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x08,

                'T', 'T', '2',
                0x00, 0x00, 0x02,
                0x00, 'A'
            ];


        auto cursor =
            ByteCursor(
                ByteSpan(bytes)
            );


        auto parsed =
            parseId3v22CanonicalTag(
                cursor
            );


        assert(parsed.hasValue);
        assert(cursor.empty);


        Id3v22CanonicalTag tag =
            parsed.value;

        Id3v22NativeTag native =
            tag.native;

        Id3v22TagValidationReport validation =
            native.tagValidation;


        assert(tag.hasCanonicalProjection);
        assert(tag.frameCount == 1);

        assert(native.hasTagValidation);
        assert(validation.strictlyConformant);
        assert(native.strictlyConformant);

        assert(
            tag.projection.metadata.length ==
            1
        );
    }
}
