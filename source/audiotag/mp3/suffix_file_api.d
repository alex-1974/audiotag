/++
Path-based MP3 trailing-ID3v1 update API.

This module composes the structured whole-file I/O and in-memory MP3 suffix
update layers on POSIX systems:

1. read the complete source file through `readFileBytes`;
2. insert, replace or remove the trailing ID3v1 block in memory through
   `updateMp3TrailingId3v1`;
3. atomically replace the original pathname through `replaceFile`.

The supplied replacement bytes are already serialized ID3v1 bytes. Their fixed
128-byte physical shape and `TAG` signature are validated by the in-memory
suffix write planner.

Read, serialization and replacement failures remain distinct through
`Mp3TrailingId3v1FileUpdateErrorDomain`.

No MPEG audio validation is added here.
+/
module audiotag.mp3.suffix_file_api;

version (Posix)
{

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
    updateMp3TrailingId3v1;


/++
Identifies which subsystem prevented a path-based trailing-ID3v1 update.
+/
enum Mp3TrailingId3v1FileUpdateErrorDomain : ubyte
{
    /// The source file could not be read before any suffix processing.
    fileRead,

    /// Replacement validation or complete-buffer materialization failed.
    serialization,

    /// The prepared complete MP3 bytes could not be committed to the path.
    fileReplace
}


/++
Structured failure for one path-based trailing-ID3v1 update.

Only the payload corresponding to `domain` is meaningful. File I/O failures
retain the original `FileUpdateError`, including commit-boundary semantics.
+/
struct Mp3TrailingId3v1FileUpdateError
{
    Mp3TrailingId3v1FileUpdateErrorDomain domain;

    private FileUpdateError _fileError;
    private SerializationError _serializationError;


    /// Constructs a source-read failure.
    static Mp3TrailingId3v1FileUpdateError
    fromFileRead(
        FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        assert(
            error.stage ==
            FileUpdateStage.preCommit
        );

        Mp3TrailingId3v1FileUpdateError result;

        result.domain =
            Mp3TrailingId3v1FileUpdateErrorDomain.fileRead;

        result._fileError =
            error;

        return result;
    }


    /// Constructs a replacement-validation/materialization failure.
    static Mp3TrailingId3v1FileUpdateError
    fromSerialization(
        SerializationError error
    )
        @safe pure nothrow @nogc
    {
        Mp3TrailingId3v1FileUpdateError result;

        result.domain =
            Mp3TrailingId3v1FileUpdateErrorDomain.serialization;

        result._serializationError =
            error;

        return result;
    }


    /// Constructs a whole-file replacement failure.
    static Mp3TrailingId3v1FileUpdateError
    fromFileReplace(
        FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        Mp3TrailingId3v1FileUpdateError result;

        result.domain =
            Mp3TrailingId3v1FileUpdateErrorDomain.fileReplace;

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
                Mp3TrailingId3v1FileUpdateErrorDomain.fileRead ||
            domain ==
                Mp3TrailingId3v1FileUpdateErrorDomain.fileReplace
        );

        return _fileError;
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
            Mp3TrailingId3v1FileUpdateErrorDomain.serialization
        );

        return _serializationError;
    }


    /++
    Returns whether the target path has crossed the replacement commit boundary.

    Read and serialization failures necessarily return false. A `fileReplace`
    failure delegates to the underlying `FileUpdateError` stage.
    +/
    @property
    bool targetCommitted() const
        @safe pure nothrow @nogc
    {
        if (
            domain ==
            Mp3TrailingId3v1FileUpdateErrorDomain.fileReplace
        )
        {
            return _fileError.targetCommitted;
        }

        return false;
    }
}


/++
Result of updating one trailing ID3v1 region directly in an MP3 file.

The successful value is the complete replacement-file byte count committed by
the underlying whole-file replacement API.
+/
struct Mp3TrailingId3v1FileUpdateResult
{
    private bool _hasValue;
    private size_t _value;
    private Mp3TrailingId3v1FileUpdateError _error;


    /// Constructs a successful path update.
    static Mp3TrailingId3v1FileUpdateResult
    success(
        size_t value
    )
        @safe pure nothrow @nogc
    {
        Mp3TrailingId3v1FileUpdateResult result;

        result._hasValue =
            true;

        result._value =
            value;

        return result;
    }


    /// Constructs a failed path update.
    static Mp3TrailingId3v1FileUpdateResult
    failure(
        Mp3TrailingId3v1FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        Mp3TrailingId3v1FileUpdateResult result;

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
        return _hasValue;
    }


    /// Whether any read, serialization or replacement stage failed.
    @property
    bool hasError() const
        @safe pure nothrow @nogc
    {
        return !_hasValue;
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

        return _value;
    }


    /++
    Returns the structured high-level update error.

    Preconditions:
        `hasError` must be true.
    +/
    @property
    Mp3TrailingId3v1FileUpdateError error() const
        @safe pure nothrow @nogc
    {
        assert(!_hasValue);

        return _error;
    }
}


/++
Updates the trailing ID3v1 region of one existing MP3 file.

The operation reads the current complete file, performs the tested in-memory
trailing-ID3v1 update, then atomically replaces the target pathname using the
baseline POSIX replacement backend.

Behavior matches `updateMp3TrailingId3v1`:

- no trailing ID3v1 + valid 128-byte tag: append at EOF;
- existing trailing ID3v1 + valid tag: replace final 128 bytes;
- existing trailing ID3v1 + empty input: remove final 128 bytes;
- no trailing ID3v1 + empty input: preserve the complete file contents.

A non-empty replacement must be exactly 128 bytes and begin with `TAG`.
Malformed replacement input fails before any file replacement transaction.

No compare-and-swap guarantee is made against an external writer modifying the
path between the initial read and final replacement transaction.

Params:
    path = Existing regular non-symlink MP3 file.
    serializedId3v1 = Complete 128-byte replacement ID3v1 block, or empty to
        remove the current trailing ID3v1 block.

Returns:
    Complete committed MP3 byte count on success, or a structured error with
    an explicit failure domain.
+/
Mp3TrailingId3v1FileUpdateResult
updateMp3TrailingId3v1File(
    string path,
    const(ubyte)[] serializedId3v1
)
    @safe
{
    auto source =
        readFileBytes(path);

    if (source.hasError)
    {
        return
            Mp3TrailingId3v1FileUpdateResult
                .failure(
                    Mp3TrailingId3v1FileUpdateError
                        .fromFileRead(
                            source.error
                        )
                );
    }

    auto updated =
        updateMp3TrailingId3v1(
            ByteSpan(source.value),
            serializedId3v1
        );

    if (updated.hasError)
    {
        return
            Mp3TrailingId3v1FileUpdateResult
                .failure(
                    Mp3TrailingId3v1FileUpdateError
                        .fromSerialization(
                            updated.error
                        )
                );
    }

    auto persisted =
        replaceFile(
            path,
            updated.value
        );

    if (persisted.hasError)
    {
        return
            Mp3TrailingId3v1FileUpdateResult
                .failure(
                    Mp3TrailingId3v1FileUpdateError
                        .fromFileReplace(
                            persisted.error
                        )
                );
    }

    return
        Mp3TrailingId3v1FileUpdateResult
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

    import audiotag.core.serialization :
        SerializationErrorCode;

    import audiotag.io.file_read :
        readFileBytes;


    private string
    createSuffixFileApiTestDirectory()
    {
        const path =
            buildPath(
                tempDir(),
                "audiotag-mp3-suffix-file-" ~
                    randomUUID()
                        .toString()
            );

        mkdir(path);

        return path;
    }


    private void
    assertSuffixFileBytes(
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


    private ubyte[128]
    testId3v1Tag(
        ubyte genre = 255
    )
        @safe pure nothrow @nogc
    {
        ubyte[128] tag;

        tag[0] = 'T';
        tag[1] = 'A';
        tag[2] = 'G';
        tag[127] = genre;

        return tag;
    }
}


/// Untagged MP3 bytes receive one trailing ID3v1 block.
unittest
{
    const directory =
        createSuffixFileApiTestDirectory();

    scope (exit)
    {
        if (exists(directory))
            rmdirRecurse(directory);
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

    auto replacement =
        testId3v1Tag(17);

    write(
        path,
        audio
    );

    auto result =
        updateMp3TrailingId3v1File(
            path,
            replacement[]
        );

    assert(result.hasValue);

    assert(
        result.value ==
        audio.length +
            replacement.length
    );

    assertSuffixFileBytes(
        path,
        audio ~
            replacement[]
    );
}


/// Existing trailing ID3v1 bytes are replaced while the prefix is preserved.
unittest
{
    const directory =
        createSuffixFileApiTestDirectory();

    scope (exit)
    {
        if (exists(directory))
            rmdirRecurse(directory);
    }

    const path =
        buildPath(
            directory,
            "replace.mp3"
        );

    const ubyte[] audio =
        [
            0xFF,
            0xFB
        ];

    auto oldTag =
        testId3v1Tag(17);

    oldTag[3] = 'A';

    auto replacement =
        testId3v1Tag(13);

    replacement[3] = 'B';

    write(
        path,
        audio ~
            oldTag[]
    );

    auto result =
        updateMp3TrailingId3v1File(
            path,
            replacement[]
        );

    assert(result.hasValue);

    assert(
        result.value ==
        audio.length +
            replacement.length
    );

    assertSuffixFileBytes(
        path,
        audio ~
            replacement[]
    );
}


/// An empty replacement removes the existing trailing ID3v1 block.
unittest
{
    const directory =
        createSuffixFileApiTestDirectory();

    scope (exit)
    {
        if (exists(directory))
            rmdirRecurse(directory);
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

    auto tag =
        testId3v1Tag();

    write(
        path,
        audio ~
            tag[]
    );

    auto result =
        updateMp3TrailingId3v1File(
            path,
            []
        );

    assert(result.hasValue);
    assert(result.value == audio.length);

    assertSuffixFileBytes(
        path,
        audio
    );
}


/// Invalid replacement bytes fail before the target file is replaced.
unittest
{
    const directory =
        createSuffixFileApiTestDirectory();

    scope (exit)
    {
        if (exists(directory))
            rmdirRecurse(directory);
    }

    const path =
        buildPath(
            directory,
            "invalid-replacement.mp3"
        );

    const ubyte[] source =
        [
            0xFF,
            0xFB,
            0x90,
            0x64
        ];

    auto invalid =
        testId3v1Tag();

    invalid[2] = 'X';

    write(
        path,
        source
    );

    auto result =
        updateMp3TrailingId3v1File(
            path,
            invalid[]
        );

    assert(result.hasError);

    assert(
        result.error.domain ==
        Mp3TrailingId3v1FileUpdateErrorDomain
            .serialization
    );

    assert(!result.error.targetCommitted);

    assert(
        result.error
            .serializationError
            .code ==
        SerializationErrorCode.invalidValue
    );

    assertSuffixFileBytes(
        path,
        source
    );
}


/// A missing source path remains a pre-commit file-read failure.
unittest
{
    const directory =
        createSuffixFileApiTestDirectory();

    scope (exit)
    {
        if (exists(directory))
            rmdirRecurse(directory);
    }

    const path =
        buildPath(
            directory,
            "missing.mp3"
        );

    auto result =
        updateMp3TrailingId3v1File(
            path,
            []
        );

    assert(result.hasError);

    assert(
        result.error.domain ==
        Mp3TrailingId3v1FileUpdateErrorDomain
            .fileRead
    );

    assert(!result.error.targetCommitted);

    assert(
        result.error.fileError.stage ==
        FileUpdateStage.preCommit
    );
}

}
