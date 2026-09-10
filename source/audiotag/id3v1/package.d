/++
Public consumer surface for ID3v1 support.

Importing this package provides the ordinary same-version workflow:

- exact bounded ID3v1.0/ID3v1.1 parsing;
- strict specification-based ISO-8859-1 text decoding;
- canonical metadata projection with exact native provenance;
- format-independent canonical editing;
- lossless 128-byte ID3v1 tag serialization.

Supported canonical write targets currently include title, single artist,
album, year-only `releaseDate`, comment, non-zero ID3v1.1 track number and one
recognized shared-ID3 genre.

Raw source spans remain available so non-conforming legacy encodings and
native-only bytes can be preserved without heuristic decoding. Detailed native
serialization and write planning remain available through direct implementation
module imports but are deliberately not re-exported here.

This package does not locate or update an ID3v1 trailer inside an MP3 file.
Container placement remains the responsibility of `audiotag.mp3`.
+/
module audiotag.id3v1;


/*
 * Minimal format-independent primitives required by the high-level consumer
 * workflow.
 */
public import audiotag.core.error :
    ParseError,
    ParseErrorCode;

public import audiotag.core.result :
    ParseResult;

public import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

public import audiotag.core.span :
    ByteSpan;


/*
 * Canonical metadata types needed to construct and apply ID3v1 edits.
 */
public import audiotag.metadata.edit :
    MetadataSourceFieldEdit,
    MetadataSourceFieldEditState,
    MetadataTreeEdit;

public import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

public import audiotag.metadata.value :
    MetadataDateTime,
    MetadataDateTimeList,
    MetadataPosition,
    MetadataText,
    MetadataTextList,
    MetadataValue;


/*
 * High-level ID3v1 parse and serialization entry points.
 */
public import audiotag.id3v1.tag :
    Id3v1Revision,
    Id3v1Tag,
    id3v1TagSize,
    parseId3v1Tag;

public import audiotag.id3v1.text_decode :
    decodeId3v1Latin1Text,
    id3v1TextContent;

public import audiotag.id3v1.canonical :
    Id3v1CanonicalTag,
    parseId3v1CanonicalTag,
    projectId3v1TagToCanonical;

public import audiotag.id3v1.api :
    serializeId3v1Tag;


version (unittest)
{
    /*
     * Exercise the ordinary public package workflow using only symbols
     * re-exported above.
     */
    unittest
    {
        ubyte[128] bytes;

        bytes[0] = 'T';
        bytes[1] = 'A';
        bytes[2] = 'G';

        bytes[3] = 'A';

        bytes[93] = '1';
        bytes[94] = '9';
        bytes[95] = '9';
        bytes[96] = '9';

        bytes[127] = 17;

        auto parsed =
            parseId3v1CanonicalTag(
                ByteSpan(bytes[])
            );

        assert(parsed.hasValue);

        auto edit =
            MetadataTreeEdit.forSource(
                parsed.value.metadata
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
            serializeId3v1Tag(
                parsed.value,
                edit
            );

        assert(written.hasValue);
        assert(written.value.length == 128);
        assert(written.value[3] == 'B');
        assert(written.value[4] == 0);

        /*
         * Unedited supported fields retain their source-native bytes.
         */
        assert(
            written.value[93 .. 97] ==
            cast(const(ubyte)[])
                "1999"
        );

        assert(written.value[127] == 17);
    }
}
