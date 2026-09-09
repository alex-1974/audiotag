/++
Structured result and error types for filesystem replacement operations.

File-update errors are deliberately separate from parsing and serialization
errors:

- parse errors describe malformed or unsupported source bytes;
- serialization errors describe values that cannot be represented;
- file-update errors describe failures while persisting already prepared bytes.

The update stage is part of every failure because the authoritative target
changes at one precise commit boundary. A failure after that boundary must not
be reported as though the original target were still authoritative.
+/
module audiotag.core.file_update;


/++
Identifies the stage at which a file update failed.

The stages describe the commit boundary, not individual implementation
functions.
+/
enum FileUpdateStage : ubyte
{
    /++
    Failure before the operating-system replacement primitive succeeds.

    The original target remains authoritative.
    +/
    preCommit,

    /++
    Failure of the operating-system replacement primitive itself.

    The replacement was not reported as successfully committed.
    +/
    commit,

    /++
    Failure after the replacement primitive has succeeded.

    The new target is already authoritative.
    +/
    postCommit
}


/++
Identifies a format-independent file-update failure.

Platform-specific details remain available through `nativeCode` instead of
being expanded into platform-specific public enums.
+/
enum FileUpdateErrorCode : ubyte
{
    /// The supplied target path or target state is invalid for the operation.
    invalidTarget,

    /// The target exists but is not a supported regular file.
    unsupportedFileType,

    /// A collision-safe temporary file could not be created.
    temporaryFileCreationFailed,

    /// Replacement bytes could not be written completely.
    writeFailed,

    /// Required target permissions or metadata could not be preserved.
    metadataPreservationFailed,

    /// A file handle could not be flushed or closed as required before commit.
    closeFailed,

    /// The operating-system replacement primitive failed.
    commitFailed,

    /// A requested stronger post-commit durability guarantee failed.
    durabilityFailed,

    /// Temporary or auxiliary state could not be cleaned up.
    cleanupFailed,

    /// The requested update guarantee is unsupported by this backend.
    unsupportedOperation,

    /// Source file bytes could not be read before an update commit.
    readFailed
}


/++
Compact context for one file-update failure.

`nativeCode` carries a platform-native numeric error code when one exists,
such as POSIX `errno` or a Windows error code. Zero means that no native code
was supplied.

`byteOffset` records the output byte position associated with a partial write
or similar byte-oriented failure when meaningful. It otherwise remains zero.

The structure intentionally owns no path or message strings so low-level
update code can propagate failures without allocating descriptive text.
+/
struct FileUpdateError
{
    /// Kind of file-update failure.
    FileUpdateErrorCode code;

    /// Stage relative to the atomic replacement commit boundary.
    FileUpdateStage stage;

    /// Platform-native numeric error code, or zero when unavailable.
    uint nativeCode;

    /// Output byte position associated with the failure when meaningful.
    size_t byteOffset;

    /++
    Constructs one structured file-update error.
    +/
    this(
        FileUpdateErrorCode code,
        FileUpdateStage stage,
        uint nativeCode = 0,
        size_t byteOffset = 0
    )
        @safe pure nothrow @nogc
    {
        this.code = code;
        this.stage = stage;
        this.nativeCode = nativeCode;
        this.byteOffset = byteOffset;
    }

    /++
    Returns whether the replacement had already crossed the commit boundary.

    A `postCommit` error means the new target is authoritative despite the
    reported failure. `preCommit` and `commit` errors do not.
    +/
    @property
    bool targetCommitted() const
        @safe pure nothrow @nogc
    {
        return
            stage ==
            FileUpdateStage.postCommit;
    }
}


/++
Value-or-error result for filesystem update operations.

This mirrors the explicit-success/failure style used by `ParseResult` and
`SerializationResult` while retaining filesystem-specific error semantics.
+/
struct FileUpdateResult(T)
{
    private bool _hasValue;
    private T _value;
    private FileUpdateError _error;

    /++
    Constructs a successful file-update result.
    +/
    static FileUpdateResult success(T value)
        @safe pure nothrow @nogc
    {
        FileUpdateResult result;
        result._hasValue = true;
        result._value = value;
        return result;
    }

    /++
    Constructs a failed file-update result.
    +/
    static FileUpdateResult failure(
        FileUpdateError error
    )
        @safe pure nothrow @nogc
    {
        FileUpdateResult result;
        result._hasValue = false;
        result._error = error;
        return result;
    }

    /// Whether the update produced a successful value.
    @property
    bool hasValue() const
        @safe pure nothrow @nogc
    {
        return _hasValue;
    }

    /// Whether the update failed.
    @property
    bool hasError() const
        @safe pure nothrow @nogc
    {
        return !_hasValue;
    }

    /++
    Returns the successful result value.

    Preconditions:
        `hasValue` must be true.
    +/
    @property
    ref const(T) value() const
        @safe pure nothrow @nogc return
    {
        assert(_hasValue);
        return _value;
    }

    /++
    Returns the structured file-update error.

    Preconditions:
        `hasError` must be true.
    +/
    @property
    ref const(FileUpdateError) error() const
        @safe pure nothrow @nogc return
    {
        assert(!_hasValue);
        return _error;
    }
}


/// Successful results expose their value without file-update error state.
unittest
{
    const result =
        FileUpdateResult!uint.success(
            42
        );

    assert(result.hasValue);
    assert(!result.hasError);
    assert(result.value == 42);
}


/// Pre-commit failures keep the original target authoritative.
unittest
{
    const expected =
        FileUpdateError(
            FileUpdateErrorCode.writeFailed,
            FileUpdateStage.preCommit,
            28,
            4096
        );

    const result =
        FileUpdateResult!uint.failure(
            expected
        );

    assert(!result.hasValue);
    assert(result.hasError);

    assert(
        result.error.code ==
        FileUpdateErrorCode.writeFailed
    );

    assert(
        result.error.stage ==
        FileUpdateStage.preCommit
    );

    assert(result.error.nativeCode == 28);
    assert(result.error.byteOffset == 4096);
    assert(!result.error.targetCommitted);
}


/// A commit-stage failure has not crossed the successful commit boundary.
unittest
{
    const error =
        FileUpdateError(
            FileUpdateErrorCode.commitFailed,
            FileUpdateStage.commit,
            13
        );

    assert(!error.targetCommitted);
}


/// Post-commit failures explicitly retain the new target as authoritative.
unittest
{
    const error =
        FileUpdateError(
            FileUpdateErrorCode.durabilityFailed,
            FileUpdateStage.postCommit,
            5
        );

    assert(error.targetCommitted);
}
