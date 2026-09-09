/++
POSIX backend for safe same-filesystem whole-file replacement.

This backend implements the baseline transaction defined by ADR 0007 for
regular files on POSIX systems:

1. validate the target with `lstat` without following a final symbolic link;
2. create a collision-safe temporary file in the target directory with
   `mkstemp`;
3. write the complete replacement byte sequence, handling short writes and
   interrupted writes;
4. copy the target's ordinary owner/group/other access-mode bits to the
   temporary file;
5. close the temporary file descriptor;
6. atomically replace the target pathname with POSIX `rename`;
7. perform no stronger post-commit durability operation.

The backend deliberately does not yet preserve ownership, ACLs, extended
attributes, special mode bits, timestamps or filesystem-specific metadata.
It also does not provide `fsync`/directory-sync power-loss durability.

The type is intended to be driven through `executeFileReplacement()`.
+/
module audiotag.io.posix_file_replace;

version (Posix)
{

import core.stdc.errno :
    EINTR,
    ENOENT,
    errno;

import core.sys.posix.stdlib :
    mkstemp;

import core.sys.posix.stdio :
    rename;

import core.sys.posix.sys.stat :
    S_IRWXG,
    S_IRWXO,
    S_IRWXU,
    S_ISREG,
    fchmod,
    lstat,
    stat_t;

import core.sys.posix.sys.types :
    mode_t,
    ssize_t;

import core.sys.posix.unistd :
    close,
    unlink,
    write;

import std.path :
    buildPath,
    dirName;

import audiotag.core.file_update :
    FileUpdateError,
    FileUpdateErrorCode,
    FileUpdateStage;

import audiotag.io.file_replace :
    FileReplacementResult,
    FileReplacementStepResult,
    executeFileReplacement,
    fileReplacementStepDone;


/++
Atomically replaces one existing regular POSIX file with complete new bytes.

This is the public convenience entry point for the baseline POSIX replacement
transaction. It adds no semantics beyond `PosixFileReplacementBackend` and
`executeFileReplacement()`.

The target must already exist as a regular non-symlink file. The replacement
uses a same-directory temporary file and POSIX `rename` commit semantics.

This baseline operation does not promise power-loss durability and does not
preserve ownership, ACLs, extended attributes, special mode bits or timestamps.

Params:
    path = Existing regular file to replace.
    replacement = Complete replacement byte sequence.

Returns:
    Number of replacement bytes on success, or a structured file-update error.
+/
FileReplacementResult
replaceFile(
    string path,
    const(ubyte)[] replacement
)
    @safe
{
    auto backend =
        PosixFileReplacementBackend(
            path
        );

    return
        executeFileReplacement(
            backend,
            replacement
        );
}


/++
One-shot POSIX backend state for a single target pathname.

Expected filesystem failures are translated into structured
`FileReplacementStepResult` values. The backend owns no exception-based
filesystem contract.

A backend instance should be passed by reference to
`executeFileReplacement()` and not reused for another transaction.
+/
struct PosixFileReplacementBackend
{
    private string _targetPath;
    private string _targetCString;

    private char[] _temporaryCString;
    private int _temporaryFd = -1;

    private mode_t _targetAccessMode;
    private bool _prepared;
    private bool _temporaryExists;
    private bool _committed;

    /++
    Constructs one backend for `targetPath`.

    Path validation is intentionally deferred to `prepareTarget()` so invalid
    external input remains a structured file-update failure.
    +/
    this(string targetPath)
        @safe
    {
        _targetPath =
            targetPath;

        _targetCString =
            targetPath ~ '\0';
    }

    /// Original target path supplied to the backend.
    @property
    string targetPath() const
        @safe pure nothrow @nogc
    {
        return
            _targetPath;
    }

    /++
    Validates that the target exists and is a regular non-symlink file.

    `lstat` is used so a symbolic link at the final path component is rejected
    rather than followed.

    On success, only ordinary owner/group/other access bits are retained for
    later application to the temporary file.
    +/
    FileReplacementStepResult
    prepareTarget()
        @safe
    {
        assert(!_prepared);
        assert(_temporaryFd == -1);
        assert(!_temporaryExists);
        assert(!_committed);

        if (
            _targetPath.length == 0 ||
            containsNul(_targetPath)
        )
        {
            return
                failure(
                    FileUpdateErrorCode.invalidTarget,
                    FileUpdateStage.preCommit
                );
        }

        stat_t info;

        if (
            nativeLstat(
                _targetCString,
                info
            ) != 0
        )
        {
            return
                failure(
                    FileUpdateErrorCode.invalidTarget,
                    FileUpdateStage.preCommit,
                    currentErrno()
                );
        }

        if (
            !nativeIsRegular(
                info.st_mode
            )
        )
        {
            return
                failure(
                    FileUpdateErrorCode
                        .unsupportedFileType,
                    FileUpdateStage.preCommit
                );
        }

        enum mode_t accessMask =
            cast(mode_t)(
                S_IRWXU |
                S_IRWXG |
                S_IRWXO
            );

        _targetAccessMode =
            info.st_mode &
            accessMask;

        _prepared =
            true;

        return
            fileReplacementStepDone();
    }

    /++
    Creates an exclusive temporary file beside the target.

    The fixed hidden basename is safe because `mkstemp` replaces the six
    trailing `X` characters and performs exclusive creation.
    +/
    FileReplacementStepResult
    createTemporary()
        @safe
    {
        assert(_prepared);
        assert(_temporaryFd == -1);
        assert(!_temporaryExists);
        assert(!_committed);

        const pattern =
            buildPath(
                dirName(_targetPath),
                ".audiotag.XXXXXX"
            );

        _temporaryCString =
            (pattern ~ '\0').dup;

        const fd =
            nativeMkstemp(
                _temporaryCString
            );

        if (fd < 0)
        {
            _temporaryCString =
                null;

            return
                failure(
                    FileUpdateErrorCode
                        .temporaryFileCreationFailed,
                    FileUpdateStage.preCommit,
                    currentErrno()
                );
        }

        _temporaryFd =
            fd;

        _temporaryExists =
            true;

        return
            fileReplacementStepDone();
    }

    /++
    Writes all replacement bytes to the temporary file descriptor.

    Short writes are continued. `EINTR` is retried. Any other failed write
    reports the number of bytes already written through `byteOffset`.
    +/
    FileReplacementStepResult
    writeReplacement(
        const(ubyte)[] replacement
    )
        @safe
    {
        assert(_prepared);
        assert(_temporaryFd >= 0);
        assert(_temporaryExists);
        assert(!_committed);

        size_t offset;

        while (
            offset <
            replacement.length
        )
        {
            const remaining =
                replacement.length -
                offset;

            const maxChunk =
                cast(size_t)
                    ssize_t.max;

            const count =
                remaining < maxChunk
                    ? remaining
                    : maxChunk;

            const written =
                nativeWrite(
                    _temporaryFd,
                    replacement,
                    offset,
                    count
                );

            if (written < 0)
            {
                const nativeCode =
                    currentErrno();

                if (
                    nativeCode ==
                    EINTR
                )
                {
                    continue;
                }

                return
                    failure(
                        FileUpdateErrorCode.writeFailed,
                        FileUpdateStage.preCommit,
                        nativeCode,
                        offset
                    );
            }

            if (written == 0)
            {
                return
                    failure(
                        FileUpdateErrorCode.writeFailed,
                        FileUpdateStage.preCommit,
                        0,
                        offset
                    );
            }

            offset +=
                cast(size_t)
                    written;
        }

        return
            fileReplacementStepDone();
    }

    /++
    Applies ordinary access permissions from the original target.

    Ownership, ACLs, extended attributes, special mode bits and timestamps are
    intentionally outside this initial backend scope.
    +/
    FileReplacementStepResult
    preserveMetadata()
        @safe
    {
        assert(_prepared);
        assert(_temporaryFd >= 0);
        assert(_temporaryExists);
        assert(!_committed);

        for (;;)
        {
            if (
                nativeFchmod(
                    _temporaryFd,
                    _targetAccessMode
                ) == 0
            )
            {
                return
                    fileReplacementStepDone();
            }

            const nativeCode =
                currentErrno();

            if (
                nativeCode ==
                EINTR
            )
            {
                continue;
            }

            return
                failure(
                    FileUpdateErrorCode
                        .metadataPreservationFailed,
                    FileUpdateStage.preCommit,
                    nativeCode
                );
        }
    }

    /++
    Closes the temporary file descriptor before pathname replacement.

    `close` is deliberately not retried after `EINTR`: on POSIX systems the
    descriptor state after an interrupted close is not portable enough to make
    an automatic retry safe.
    +/
    FileReplacementStepResult
    closeTemporary()
        @safe
    {
        assert(_prepared);
        assert(_temporaryFd >= 0);
        assert(_temporaryExists);
        assert(!_committed);

        const fd =
            _temporaryFd;

        _temporaryFd =
            -1;

        if (
            nativeClose(fd) != 0
        )
        {
            return
                failure(
                    FileUpdateErrorCode.closeFailed,
                    FileUpdateStage.preCommit,
                    currentErrno()
                );
        }

        return
            fileReplacementStepDone();
    }

    /++
    Atomically replaces the target pathname using POSIX `rename`.

    Because the temporary file was created in the target directory, this
    backend never intentionally crosses a filesystem boundary.
    +/
    FileReplacementStepResult
    commitReplacement()
        @safe
    {
        assert(_prepared);
        assert(_temporaryFd == -1);
        assert(_temporaryExists);
        assert(!_committed);

        if (
            nativeRename(
                _temporaryCString,
                _targetCString
            ) != 0
        )
        {
            return
                failure(
                    FileUpdateErrorCode.commitFailed,
                    FileUpdateStage.commit,
                    currentErrno()
                );
        }

        _temporaryExists =
            false;

        _committed =
            true;

        return
            fileReplacementStepDone();
    }

    /++
    Baseline POSIX backend post-commit step.

    No durability synchronization is requested or implied by this backend, so
    the baseline operation completes immediately after successful rename.
    +/
    FileReplacementStepResult
    finalizeCommittedTarget()
        @safe pure nothrow @nogc
    {
        assert(_prepared);
        assert(_temporaryFd == -1);
        assert(!_temporaryExists);
        assert(_committed);

        return
            fileReplacementStepDone();
    }

    /++
    Best-effort cleanup for an uncommitted temporary file.

    Descriptor close and pathname unlink are both attempted. The first cleanup
    failure is retained if both operations fail. `ENOENT` from unlink is
    accepted because the temporary pathname is already absent.
    +/
    FileReplacementStepResult
    abortTemporary()
        @safe
    {
        assert(!_committed);

        uint firstNativeCode;

        if (
            _temporaryFd >= 0
        )
        {
            const fd =
                _temporaryFd;

            _temporaryFd =
                -1;

            if (
                nativeClose(fd) != 0
            )
            {
                firstNativeCode =
                    currentErrno();
            }
        }

        if (_temporaryExists)
        {
            if (
                nativeUnlink(
                    _temporaryCString
                ) != 0
            )
            {
                const nativeCode =
                    currentErrno();

                if (
                    nativeCode !=
                    ENOENT
                )
                {
                    if (
                        firstNativeCode ==
                        0
                    )
                    {
                        firstNativeCode =
                            nativeCode;
                    }
                }
                else
                {
                    _temporaryExists =
                        false;
                }
            }
            else
            {
                _temporaryExists =
                    false;
            }
        }

        if (
            firstNativeCode !=
            0
        )
        {
            return
                failure(
                    FileUpdateErrorCode.cleanupFailed,
                    FileUpdateStage.preCommit,
                    firstNativeCode
                );
        }

        return
            fileReplacementStepDone();
    }

    private FileReplacementStepResult
    failure(
        FileUpdateErrorCode code,
        FileUpdateStage stage,
        uint nativeCode = 0,
        size_t byteOffset = 0
    )
        @safe pure nothrow @nogc
    {
        return
            FileReplacementStepResult
                .failure(
                    FileUpdateError(
                        code,
                        stage,
                        nativeCode,
                        byteOffset
                    )
                );
    }
}


/++
Returns whether a D pathname contains an embedded NUL byte.

C/POSIX path APIs would otherwise silently observe only the prefix before the
first NUL.
+/
private bool
containsNul(
    const(char)[] path
)
    @safe pure nothrow @nogc
{
    foreach (character; path)
    {
        if (
            character ==
            '\0'
        )
        {
            return true;
        }
    }

    return false;
}


/++
Trusted wrapper around the druntime `S_ISREG` helper.

`S_ISREG` is exposed as `@system` by the POSIX druntime binding even though
this operation only inspects the supplied mode bits and does not access
memory. Keeping that narrow mismatch here preserves the public backend's
`@safe` boundary.
+/
private bool
nativeIsRegular(
    mode_t mode
)
    @trusted
{
    return
        S_ISREG(mode);
}


/++
Returns the current POSIX `errno` as unsigned structured context.
+/
private uint
currentErrno()
    @trusted nothrow @nogc
{
    const value =
        errno();

    return
        value > 0
            ? cast(uint) value
            : 0;
}


/++
Trusted wrapper around `lstat`.

The caller supplies a NUL-terminated immutable D string and valid writable
storage for `stat_t`.
+/
private int
nativeLstat(
    string pathCString,
    ref stat_t info
)
    @trusted nothrow @nogc
{
    return
        lstat(
            pathCString.ptr,
            &info
        );
}


/++
Trusted wrapper around `mkstemp`.

The mutable array includes a trailing NUL and six `X` template bytes.
+/
private int
nativeMkstemp(
    ref char[] templateCString
)
    @trusted nothrow @nogc
{
    return
        mkstemp(
            templateCString.ptr
        );
}


/++
Trusted bounded wrapper around POSIX `write`.
+/
private ssize_t
nativeWrite(
    int fd,
    const(ubyte)[] bytes,
    size_t offset,
    size_t count
)
    @trusted nothrow @nogc
{
    assert(
        offset <=
        bytes.length
    );

    assert(
        count <=
        bytes.length -
        offset
    );

    return
        write(
            fd,
            bytes.ptr + offset,
            count
        );
}


/++
Trusted wrapper around `fchmod`.
+/
private int
nativeFchmod(
    int fd,
    mode_t mode
)
    @trusted nothrow @nogc
{
    return
        fchmod(
            fd,
            mode
        );
}


/++
Trusted wrapper around POSIX `close`.
+/
private int
nativeClose(
    int fd
)
    @trusted nothrow @nogc
{
    return
        close(fd);
}


/++
Trusted wrapper around POSIX `rename`.
+/
private int
nativeRename(
    const(char)[] fromCString,
    const(char)[] toCString
)
    @trusted nothrow @nogc
{
    return
        rename(
            fromCString.ptr,
            toCString.ptr
        );
}


/++
Trusted wrapper around POSIX `unlink`.
+/
private int
nativeUnlink(
    const(char)[] pathCString
)
    @trusted nothrow @nogc
{
    return
        unlink(
            pathCString.ptr
        );
}


version (unittest)
{
    import core.sys.posix.unistd :
        createHardLinkNative = link;

    import std.conv :
        octal;

    import std.file :
        exists,
        getAttributes,
        mkdir,
        readFile = read,
        rmdirRecurse,
        setAttributes,
        symlink,
        tempDir,
        writeFile = write;

    import std.uuid :
        randomUUID;

    import audiotag.io.file_replace :
        executeFileReplacement;


    private string
    createPosixBackendTestDirectory()
        @safe
    {
        const path =
            buildPath(
                tempDir(),
                "audiotag-posix-" ~
                    randomUUID()
                        .toString()
            );

        mkdir(path);

        return path;
    }


    private ubyte[]
    readTestBytes(
        string path
    )
    {
        return
            cast(ubyte[])
                readFile(path);
    }


    /++
    Creates one hard-link alias for a test file.

    The POSIX `link` binding consumes NUL-terminated C strings. This test-only
    helper owns those temporary C-string buffers and keeps the pointer boundary
    narrowly `@trusted`.
    +/
    private void
    createHardLink(
        string existingPath,
        string aliasPath
    )
        @trusted
    {
        const existingCString =
            existingPath ~ '\0';

        const aliasCString =
            aliasPath ~ '\0';

        assert(
            createHardLinkNative(
                existingCString.ptr,
                aliasCString.ptr
            ) ==
            0
        );
    }


    /// A complete replacement changes bytes atomically and preserves access mode.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const target =
            buildPath(
                directory,
                "track.mp3"
            );

        writeFile(
            target,
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x02
            ]
        );

        enum uint expectedMode =
            octal!640;

        setAttributes(
            target,
            expectedMode
        );

        auto backend =
            PosixFileReplacementBackend(
                target
            );

        const ubyte[] replacement =
            [
                0xAA,
                0xBB,
                0xCC
            ];

        auto result =
            executeFileReplacement(
                backend,
                replacement
            );

        assert(result.hasValue);
        assert(result.value == replacement.length);

        assert(
            readTestBytes(target) ==
            replacement
        );

        assert(
            (
                getAttributes(target) &
                cast(uint) octal!777
            ) ==
            expectedMode
        );

        assert(backend._committed);
        assert(!backend._temporaryExists);
        assert(backend._temporaryFd == -1);

        const temporaryPath =
            backend
                ._temporaryCString[
                    0 ..
                    $ - 1
                ]
                .idup;

        assert(!exists(temporaryPath));
    }


    /// Public `replaceFile` composes the POSIX backend transaction.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const target =
            buildPath(
                directory,
                "public-api.mp3"
            );

        writeFile(
            target,
            [
                cast(ubyte) 0x01,
                cast(ubyte) 0x02
            ]
        );

        const ubyte[] replacement =
            [
                0xA1,
                0xB2,
                0xC3
            ];

        auto result =
            replaceFile(
                target,
                replacement
            );

        assert(result.hasValue);
        assert(result.value == replacement.length);

        assert(
            readTestBytes(target) ==
            replacement
        );
    }


    /// Empty replacement bytes produce a valid zero-length committed file.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const target =
            buildPath(
                directory,
                "empty.mp3"
            );

        writeFile(
            target,
            [
                cast(ubyte) 0x01
            ]
        );

        auto backend =
            PosixFileReplacementBackend(
                target
            );

        const ubyte[] replacement = [];

        auto result =
            executeFileReplacement(
                backend,
                replacement
            );

        assert(result.hasValue);
        assert(result.value == 0);
        assert(readTestBytes(target).length == 0);
    }


    /// Replacing one pathname does not modify an existing hard-link alias.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const target =
            buildPath(
                directory,
                "track.mp3"
            );

        const aliasPath =
            buildPath(
                directory,
                "track-alias.mp3"
            );

        const ubyte[] original =
            [
                0x10,
                0x20,
                0x30
            ];

        const ubyte[] replacement =
            [
                0xAA,
                0xBB,
                0xCC,
                0xDD
            ];

        writeFile(
            target,
            original
        );

        createHardLink(
            target,
            aliasPath
        );

        assert(
            readTestBytes(aliasPath) ==
            original
        );

        auto backend =
            PosixFileReplacementBackend(
                target
            );

        auto result =
            executeFileReplacement(
                backend,
                replacement
            );

        assert(result.hasValue);
        assert(result.value == replacement.length);

        assert(
            readTestBytes(target) ==
            replacement
        );

        assert(
            readTestBytes(aliasPath) ==
            original
        );
    }


    /// A symbolic-link target is rejected without modifying its referent.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const referent =
            buildPath(
                directory,
                "real.mp3"
            );

        const link =
            buildPath(
                directory,
                "link.mp3"
            );

        const ubyte[] original =
            [
                0x10,
                0x20
            ];

        writeFile(
            referent,
            original
        );

        symlink(
            referent,
            link
        );

        auto backend =
            PosixFileReplacementBackend(
                link
            );

        auto result =
            executeFileReplacement(
                backend,
                [
                    cast(ubyte) 0xFF
                ]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode
                .unsupportedFileType
        );

        assert(
            result.error.stage ==
            FileUpdateStage.preCommit
        );

        assert(!result.error.targetCommitted);

        assert(
            readTestBytes(referent) ==
            original
        );
    }


    /// A directory target is rejected as an unsupported file type.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        auto backend =
            PosixFileReplacementBackend(
                directory
            );

        auto result =
            executeFileReplacement(
                backend,
                [
                    cast(ubyte) 0xFF
                ]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode
                .unsupportedFileType
        );

        assert(!result.error.targetCommitted);
    }


    /// A missing target is a structured pre-commit invalid-target failure.
    unittest
    {
        const directory =
            createPosixBackendTestDirectory();

        scope (exit)
        {
            if (exists(directory))
            {
                rmdirRecurse(directory);
            }
        }

        const target =
            buildPath(
                directory,
                "missing.mp3"
            );

        auto backend =
            PosixFileReplacementBackend(
                target
            );

        auto result =
            executeFileReplacement(
                backend,
                [
                    cast(ubyte) 0xFF
                ]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.invalidTarget
        );

        assert(
            result.error.stage ==
            FileUpdateStage.preCommit
        );

        assert(
            result.error.nativeCode !=
            0
        );

        assert(!result.error.targetCommitted);
    }


    /// Embedded NUL bytes are rejected before any POSIX pathname call.
    unittest
    {
        auto backend =
            PosixFileReplacementBackend(
                "track\0ignored.mp3"
            );

        auto result =
            executeFileReplacement(
                backend,
                [
                    cast(ubyte) 0xFF
                ]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.invalidTarget
        );

        assert(result.error.nativeCode == 0);
        assert(!result.error.targetCommitted);
    }
}

}
