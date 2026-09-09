/++
Path-based MP3 leading-ID3v2 update API.

This module composes the existing structured I/O and in-memory MP3 update
layers on POSIX systems:

1. read the complete source file through `readFileBytes`;
2. insert, replace or remove the leading ID3v2 envelope in memory through
   `updateMp3LeadingId3v2`;
3. atomically replace the original pathname through `replaceFile`.

The supplied replacement bytes remain opaque, already serialized ID3v2 bytes.
No MPEG audio validation is added here.

Read, parse, serialization and replacement failures remain distinct through
`Mp3LeadingId3v2FileUpdateErrorDomain`.
+/
module audiotag.mp3.file_api;

version (Posix)
{

import audiotag.core.error :
    ParseError;

import audiotag.core.file_update :
    FileUpdateError,
    FileUpdateStage;

import audiotag.core.serialization :
    SerializationError;

import audiotag.core.span :
    ByteSpan;

import audiotag.io.file_read :
    readFileBytes;

import audiotag.io.posix_file_replace :
    replaceFile;

import audiotag.mp3.api :
    updateMp3LeadingId3v2;


/++
Identifies which subsystem prevented a path-based MP3 update from completing.
+/
enum Mp3LeadingId3v2FileUpdateErrorDomain : ubyte
{
    /// The source file could not be read before any format parsing.
    fileRead,

    /// The existing leading MP3/ID3 prefix was malformed or unsupported.
    parse,

    /// The complete updated MP3 buffer could not be materialized.
    serialization,

    /// The prepared complete MP3 bytes could not be committed to the path.
    fileReplace
}


/++
Structured failure for one path-based leading-ID3v2 update.

Only the payload corresponding to `domain` is meaningful. File I/O failures
retain the original `FileUpdateError`, including commit-boundary semantics.
Parse and serialization failures retain their native structured error types.
+/
struct Mp3LeadingId3v2FileUpdateError
{
    /// Subsystem that produced this failure.
    Mp3LeadingId3v2FileUpdateErrorDomain domain;

    private FileUpdateError _fileError;
    private ParseError _parseError;
    private SerializationError _serializationError;

    /// Constructs a source-read failure.
    static Mp3LeadingId3v2FileUpdateError
    fromFileRead(
        FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        assert(
            error.stage ==
            FileUpdateStage.preCommit
        );

        Mp3LeadingId3v2FileUpdateError result;
        result.domain =
            Mp3LeadingId3v2FileUpdateErrorDomain.fileRead;
        result._fileError =
            error;

        return result;
    }

    /// Constructs a source-prefix parse failure.
    static Mp3LeadingId3v2FileUpdateError
    fromParse(
        ParseError error
    )
        @safe pure nothrow @nogc
    {
        Mp3LeadingId3v2FileUpdateError result;
        result.domain =
            Mp3LeadingId3v2FileUpdateErrorDomain.parse;
        result._parseError =
            error;

        return result;
    }

    /// Constructs an output-materialization failure.
    static Mp3LeadingId3v2FileUpdateError
    fromSerialization(
        SerializationError error
    )
        @safe pure nothrow @nogc
    {
        Mp3LeadingId3v2FileUpdateError result;
        result.domain =
            Mp3LeadingId3v2FileUpdateErrorDomain.serialization;
        result._serializationError =
            error;

        return result;
    }

    /// Constructs a whole-file replacement failure.
    static Mp3LeadingId3v2FileUpdateError
    fromFileReplace(
        FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        Mp3LeadingId3v2FileUpdateError result;
        result.domain =
            Mp3LeadingId3v2FileUpdateErrorDomain.fileReplace;
        result._fileError =
            error;

        return result;
    }

    /++
    Returns the file I/O error.

    Preconditions:
        `domain` must be `fileRead` or `fileReplace`.
    +/
    @property
    FileUpdateError fileError() const
        @safe pure nothrow @nogc
    {
        assert(
            domain ==
                Mp3LeadingId3v2FileUpdateErrorDomain.fileRead ||
            domain ==
                Mp3LeadingId3v2FileUpdateErrorDomain.fileReplace
        );

        return
            _fileError;
    }

    /++
    Returns the source parse error.

    Preconditions:
        `domain` must be `parse`.
    +/
    @property
    ParseError parseError() const
        @safe pure nothrow @nogc
    {
        assert(
            domain ==
            Mp3LeadingId3v2FileUpdateErrorDomain.parse
        );

        return
            _parseError;
    }

    /++
    Returns the serialization error.

    Preconditions:
        `domain` must be `serialization`.
    +/
    @property
    SerializationError serializationError() const
        @safe pure nothrow @nogc
    {
        assert(
            domain ==
            Mp3LeadingId3v2FileUpdateErrorDomain.serialization
        );

        return
            _serializationError;
    }

    /++
    Returns whether the target path has already crossed the replacement
    commit boundary despite this failure.

    Read, parse and serialization failures necessarily return false. A
    `fileReplace` failure delegates to its `FileUpdateError` stage.
    +/
    @property
    bool targetCommitted() const
        @safe pure nothrow @nogc
    {
        if (
            domain ==
            Mp3LeadingId3v2FileUpdateErrorDomain.fileReplace
        )
        {
            return
                _fileError.targetCommitted;
        }

        return false;
    }
}


/++
Result of updating one leading ID3v2 region directly in an MP3 file.

The successful value is the complete replacement-file byte count committed by
the underlying whole-file replacement API.
+/
struct Mp3LeadingId3v2FileUpdateResult
{
    private bool _hasValue;
    private size_t _value;
    private Mp3LeadingId3v2FileUpdateError _error;

    /// Constructs a successful path update.
    static Mp3LeadingId3v2FileUpdateResult
    success(
        size_t value
    )
        @safe pure nothrow @nogc
    {
        Mp3LeadingId3v2FileUpdateResult result;
        result._hasValue =
            true;
        result._value =
            value;

        return result;
    }

    /// Constructs a failed path update.
    static Mp3LeadingId3v2FileUpdateResult
    failure(
        Mp3LeadingId3v2FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        Mp3LeadingId3v2FileUpdateResult result;
        result._hasValue =
            false;
        result._error =
            error;

        return result;
    }

    /// Whether the complete updated MP3 file was committed successfully.
    @property
    bool hasValue() const
        @safe pure nothrow @nogc
    {
        return
            _hasValue;
    }

    /// Whether any read, parse, serialization or replacement stage failed.
    @property
    bool hasError() const
        @safe pure nothrow @nogc
    {
        return
            !_hasValue;
    }

    /++
    Returns the committed complete-file byte count.

    Preconditions:
        `hasValue` must be true.
    +/
    @property
    size_t value() const
        @safe pure nothrow @nogc
    {
        assert(_hasValue);

        return
            _value;
    }

    /++
    Returns the structured high-level update error.

    Preconditions:
        `hasError` must be true.
    +/
    @property
    Mp3LeadingId3v2FileUpdateError error() const
        @safe pure nothrow @nogc
    {
        assert(!_hasValue);

        return
            _error;
    }
}


/++
Updates the prepended ID3v2 region of one existing MP3 file.

The operation reads the current complete file, performs the already-tested
in-memory leading-ID3v2 update, then atomically replaces the target pathname
using the baseline POSIX replacement backend.

Supported leading-tag behavior matches `updateMp3LeadingId3v2`:

- no leading ID3 signature: insert the supplied replacement at byte zero;
- ID3v2.3 or ID3v2.4: replace the complete existing leading envelope;
- empty replacement: remove an existing leading tag;
- malformed/truncated supported ID3: fail before any file replacement;
- unsupported leading ID3 major version: fail before replacement.

The replacement bytes are not validated as ID3 data. Normal callers should
supply complete bytes produced by an ID3 serializer.

No compare-and-swap guarantee is made against an external writer modifying the
path between the initial read and the final replacement transaction.

Params:
    path = Existing regular non-symlink MP3 file.
    serializedId3v2 = Complete replacement ID3v2 bytes, or an empty slice to
        remove the existing leading tag.

Returns:
    Complete committed MP3 byte count on success, or a structured error with
    an explicit failure domain.
+/
Mp3LeadingId3v2FileUpdateResult
updateMp3LeadingId3v2File(
    string path,
    const(ubyte)[] serializedId3v2
)
    @safe
{
    auto source =
        readFileBytes(path);

    if (source.hasError)
    {
        return
            Mp3LeadingId3v2FileUpdateResult
                .failure(
                    Mp3LeadingId3v2FileUpdateError
                        .fromFileRead(
                            source.error
                        )
                );
    }

    auto updated =
        updateMp3LeadingId3v2(
            ByteSpan(source.value),
            serializedId3v2
        );

    if (updated.hasError)
    {
        return
            Mp3LeadingId3v2FileUpdateResult
                .failure(
                    Mp3LeadingId3v2FileUpdateError
                        .fromParse(
                            updated.error
                        )
                );
    }

    auto materialized =
        updated.value;

    if (materialized.hasError)
    {
        return
            Mp3LeadingId3v2FileUpdateResult
                .failure(
                    Mp3LeadingId3v2FileUpdateError
                        .fromSerialization(
                            materialized.error
                        )
                );
    }

    auto persisted =
        replaceFile(
            path,
            materialized.value
        );

    if (persisted.hasError)
    {
        return
            Mp3LeadingId3v2FileUpdateResult
                .failure(
                    Mp3LeadingId3v2FileUpdateError
                        .fromFileReplace(
                            persisted.error
                        )
                );
    }

    return
        Mp3LeadingId3v2FileUpdateResult
            .success(
                persisted.value
            );
}


version (unittest)
{
    import std.file :
        exists,
        mkdir,
        rmdirRecurse,
        tempDir,
        write;

    import std.path :
        buildPath;

    import std.uuid :
        randomUUID;

    import std.sumtype :
        match;

    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.core.error :
        ParseErrorCode;

    import audiotag.id3v2.v23.api :
        serializeId3v23Tag;

    import audiotag.id3v2.v23.canonical_tag :
        parseId3v23CanonicalTag;

    import audiotag.id3v2.v24.api :
        serializeId3v24Tag;

    import audiotag.id3v2.v24.canonical_tag :
        parseId3v24CanonicalTag;

    import audiotag.metadata.edit :
        MetadataTreeEdit;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataText,
        MetadataValue;

    import audiotag.mp3.prefix :
        parseMp3Prefix;

    import audiotag.core.file_update :
        FileUpdateErrorCode;

    import audiotag.io.file_read :
        readFileBytes;


    private string
    createMp3FileApiTestDirectory()
    {
        const path =
            buildPath(
                tempDir(),
                "audiotag-mp3-file-" ~
                    randomUUID()
                        .toString()
            );

        mkdir(path);

        return path;
    }


    private void
    assertFileBytes(
        string path,
        const(ubyte)[] expected
    )
    {
        auto actual =
            readFileBytes(path);

        assert(actual.hasValue);

        assert(
            actual.value ==
            expected
        );
    }


    /// Untagged MP3 bytes receive a new leading ID3v2 tag.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "insert.mp3"
            );

        const ubyte[] audio =
            [
                0xFF,
                0xFB,
                0x90,
                0x64
            ];

        const ubyte[] replacement =
            [
                'I', 'D', '3',
                0x04, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x00
            ];

        write(
            path,
            audio
        );

        auto result =
            updateMp3LeadingId3v2File(
                path,
                replacement
            );

        assert(result.hasValue);
        assert(
            result.value ==
            replacement.length +
            audio.length
        );

        assertFileBytes(
            path,
            replacement ~
                audio
        );
    }


    /// Existing ID3v2.3 bytes are replaced while the remainder is preserved.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "replace.mp3"
            );

        const ubyte[] audio =
            [
                0xFF,
                0xFB,
                0x90,
                0x64
            ];

        const ubyte[] source =
            [
                'I', 'D', '3',
                0x03, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x02,
                0xAA, 0xBB,

                0xFF, 0xFB, 0x90, 0x64
            ];

        const ubyte[] replacement =
            [
                'I', 'D', '3',
                0x04, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x00
            ];

        write(
            path,
            source
        );

        auto result =
            updateMp3LeadingId3v2File(
                path,
                replacement
            );

        assert(result.hasValue);
        assert(
            result.value ==
            replacement.length +
            audio.length
        );

        assertFileBytes(
            path,
            replacement ~
                audio
        );
    }


    /// Empty replacement bytes remove an existing leading ID3v2 tag.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "remove.mp3"
            );

        const ubyte[] audio =
            [
                0xFF,
                0xFB,
                0x90,
                0x64
            ];

        const ubyte[] source =
            [
                'I', 'D', '3',
                0x04, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x01,
                0xAA,

                0xFF, 0xFB, 0x90, 0x64
            ];

        write(
            path,
            source
        );

        auto result =
            updateMp3LeadingId3v2File(
                path,
                []
            );

        assert(result.hasValue);
        assert(result.value == audio.length);

        assertFileBytes(
            path,
            audio
        );
    }


    /// ID3v2.3 canonical editing survives a complete path-based file update.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "canonical-v23.mp3"
            );

        const ubyte[] audio =
            [
                0xFF, 0xFB, 0x90, 0x64,
                0x12, 0x34
            ];

        const ubyte[] source =
            [
                'I', 'D', '3',
                0x03, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x0C,

                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x02,
                0x00, 0x00,
                0x00, 'U',

                0xFF, 0xFB, 0x90, 0x64,
                0x12, 0x34
            ];

        write(
            path,
            source
        );

        auto originalFile =
            readFileBytes(path);

        assert(originalFile.hasValue);

        auto prefix =
            parseMp3Prefix(
                ByteSpan(
                    originalFile.value
                )
            );

        assert(prefix.hasValue);

        assert(
            prefix.value
                .remainder
                .data ==
            audio
        );

        auto tagCursor =
            ByteCursor(
                prefix.value
                    .leadingId3v2
            );

        auto parsedTag =
            tagCursor
                .parseId3v23CanonicalTag();

        assert(parsedTag.hasValue);
        assert(tagCursor.empty);

        auto edit =
            MetadataTreeEdit.forSource(
                parsedTag.value
                    .projection
                    .metadata
            );

        MetadataValue newTitle =
            MetadataText("V");

        edit.replaceSourceField(
            0,
            MetadataField(
                MetadataKey("title"),
                newTitle
            )
        );

        auto serialized =
            serializeId3v23Tag(
                parsedTag.value,
                edit
            );

        assert(serialized.hasValue);
        assert(serialized.value.hasValue);

        auto update =
            updateMp3LeadingId3v2File(
                path,
                serialized.value.value
            );

        assert(update.hasValue);

        auto updatedFile =
            readFileBytes(path);

        assert(updatedFile.hasValue);
        assert(
            update.value ==
            updatedFile.value.length
        );

        auto updatedPrefix =
            parseMp3Prefix(
                ByteSpan(
                    updatedFile.value
                )
            );

        assert(updatedPrefix.hasValue);

        assert(
            updatedPrefix.value
                .remainder
                .data ==
            audio
        );

        auto updatedTagCursor =
            ByteCursor(
                updatedPrefix.value
                    .leadingId3v2
            );

        auto reparsedTag =
            updatedTagCursor
                .parseId3v23CanonicalTag();

        assert(reparsedTag.hasValue);
        assert(updatedTagCursor.empty);

        assert(
            reparsedTag.value
                .projection
                .metadata
                .length ==
            1
        );

        assert(
            reparsedTag.value
                .projection
                .metadata[0]
                .key
                .name ==
            "title"
        );

        const titleMatches =
            reparsedTag.value
                .projection
                .metadata[0]
                .value
                .match!(
                    (MetadataText text) =>
                        text.value == "V",
                    _ => false
                );

        assert(titleMatches);
    }


    /// ID3v2.4 canonical editing survives a complete path-based file update.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "canonical-v24.mp3"
            );

        const ubyte[] audio =
            [
                0xFF, 0xFB, 0x90, 0x64,
                0x56, 0x78
            ];

        const ubyte[] source =
            [
                'I', 'D', '3',
                0x04, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x0C,

                'T', 'I', 'T', '2',
                0x00, 0x00, 0x00, 0x02,
                0x00, 0x00,
                0x00, 'U',

                0xFF, 0xFB, 0x90, 0x64,
                0x56, 0x78
            ];

        write(
            path,
            source
        );

        auto originalFile =
            readFileBytes(path);

        assert(originalFile.hasValue);

        auto prefix =
            parseMp3Prefix(
                ByteSpan(
                    originalFile.value
                )
            );

        assert(prefix.hasValue);

        assert(
            prefix.value
                .remainder
                .data ==
            audio
        );

        auto tagCursor =
            ByteCursor(
                prefix.value
                    .leadingId3v2
            );

        auto parsedTag =
            tagCursor
                .parseId3v24CanonicalTag();

        assert(parsedTag.hasValue);
        assert(tagCursor.empty);

        auto edit =
            MetadataTreeEdit.forSource(
                parsedTag.value
                    .projection
                    .metadata
            );

        MetadataValue newTitle =
            MetadataText("V");

        edit.replaceSourceField(
            0,
            MetadataField(
                MetadataKey("title"),
                newTitle
            )
        );

        auto serialized =
            serializeId3v24Tag(
                parsedTag.value,
                edit
            );

        assert(serialized.hasValue);
        assert(serialized.value.hasValue);

        auto update =
            updateMp3LeadingId3v2File(
                path,
                serialized.value.value
            );

        assert(update.hasValue);

        auto updatedFile =
            readFileBytes(path);

        assert(updatedFile.hasValue);
        assert(
            update.value ==
            updatedFile.value.length
        );

        auto updatedPrefix =
            parseMp3Prefix(
                ByteSpan(
                    updatedFile.value
                )
            );

        assert(updatedPrefix.hasValue);

        assert(
            updatedPrefix.value
                .remainder
                .data ==
            audio
        );

        auto updatedTagCursor =
            ByteCursor(
                updatedPrefix.value
                    .leadingId3v2
            );

        auto reparsedTag =
            updatedTagCursor
                .parseId3v24CanonicalTag();

        assert(reparsedTag.hasValue);
        assert(updatedTagCursor.empty);

        assert(
            reparsedTag.value
                .projection
                .metadata
                .length ==
            1
        );

        assert(
            reparsedTag.value
                .projection
                .metadata[0]
                .key
                .name ==
            "title"
        );

        const titleMatches =
            reparsedTag.value
                .projection
                .metadata[0]
                .value
                .match!(
                    (MetadataText text) =>
                        text.value == "V",
                    _ => false
                );

        assert(titleMatches);
    }


    /// Malformed supported ID3 input fails before modifying the target file.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "malformed.mp3"
            );

        const ubyte[] source =
            [
                'I', 'D', '3',
                0x03, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0x03,
                0xAA
            ];

        write(
            path,
            source
        );

        auto result =
            updateMp3LeadingId3v2File(
                path,
                []
            );

        assert(result.hasError);

        assert(
            result.error.domain ==
            Mp3LeadingId3v2FileUpdateErrorDomain.parse
        );

        assert(
            result.error
                .parseError
                .code ==
            ParseErrorCode.endOfSpan
        );

        assert(!result.error.targetCommitted);

        assertFileBytes(
            path,
            source
        );
    }


    /// Missing source files retain their structured read-side failure domain.
    unittest
    {
        const directory =
            createMp3FileApiTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const path =
            buildPath(
                directory,
                "missing.mp3"
            );

        auto result =
            updateMp3LeadingId3v2File(
                path,
                []
            );

        assert(result.hasError);

        assert(
            result.error.domain ==
            Mp3LeadingId3v2FileUpdateErrorDomain.fileRead
        );

        assert(
            result.error
                .fileError
                .code ==
            FileUpdateErrorCode.readFailed
        );

        assert(!result.error.targetCommitted);
    }
}

}
