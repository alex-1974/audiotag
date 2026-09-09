/++
Structured whole-file byte reads for audiotag file-update workflows.

This module provides the read-side counterpart to the replacement APIs.
Expected filesystem failures are translated from `std.file.FileException`
into the shared `FileUpdateError` domain instead of escaping as exceptions.

A read failure is always `preCommit`: no replacement commit has happened and
the existing target remains authoritative.
+/
module audiotag.io.file_read;

import std.file :
    FileException,
    read;

import audiotag.core.file_update :
    FileUpdateError,
    FileUpdateErrorCode,
    FileUpdateResult,
    FileUpdateStage;


/++
Result of reading one complete file into an owned byte buffer.
+/
alias FileReadResult =
    FileUpdateResult!(ubyte[]);


/++
Reads one complete file into owned memory with structured I/O failures.

The function intentionally performs no format parsing. Callers may pass the
returned bytes to MP3, ID3 or other container parsers.

Empty paths and paths containing embedded NUL bytes are rejected before
calling the operating-system file API. Embedded NUL rejection prevents a D
string from being silently truncated when converted to a C pathname.

Params:
    path = File path to read.

Returns:
    Owned complete file bytes on success, or a `preCommit` file-update error.

Notes:
    Allocation failures are not converted into `FileUpdateError`; they remain
    language/runtime allocation failures rather than filesystem failures.
+/
FileReadResult
readFileBytes(
    string path
)
    @safe
{
    if (
        path.length == 0 ||
        containsNul(path)
    )
    {
        return
            FileReadResult
                .failure(
                    FileUpdateError(
                        FileUpdateErrorCode.invalidTarget,
                        FileUpdateStage.preCommit
                    )
                );
    }

    try
    {
        auto raw =
            read(path);

        return
            FileReadResult
                .success(
                    bytesFromVoid(raw)
                );
    }
    catch (FileException error)
    {
        return
            FileReadResult
                .failure(
                    FileUpdateError(
                        FileUpdateErrorCode.readFailed,
                        FileUpdateStage.preCommit,
                        error.errno
                    )
                );
    }
}


/++
Narrows the untyped `std.file.read` buffer to bytes.

`std.file.read` owns the allocation; changing only the slice element type
does not change its storage or lifetime. The cast is isolated here so the
public read API remains `@safe`.
+/
private ubyte[]
bytesFromVoid(
    void[] raw
)
    @trusted pure nothrow @nogc
{
    return
        cast(ubyte[])
            raw;
}


/++
Returns whether a D pathname contains an embedded NUL byte.
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


    private string
    createFileReadTestDirectory()
    {
        const path =
            buildPath(
                tempDir(),
                "audiotag-read-" ~
                    randomUUID()
                        .toString()
            );

        mkdir(path);

        return path;
    }


    /// Successful reads return complete owned file bytes.
    unittest
    {
        const directory =
            createFileReadTestDirectory();

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
                "track.mp3"
            );

        const ubyte[] source =
            [
                0x01,
                0x02,
                0x03
            ];

        write(
            path,
            source
        );

        auto result =
            readFileBytes(path);

        assert(result.hasValue);
        assert(
            result.value ==
            source
        );
    }


    /// Missing files become structured pre-commit read failures.
    unittest
    {
        const directory =
            createFileReadTestDirectory();

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
            readFileBytes(path);

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.readFailed
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


    /// Empty and embedded-NUL paths fail before filesystem access.
    unittest
    {
        foreach (
            path;
            [
                "",
                "track\0ignored.mp3"
            ]
        )
        {
            auto result =
                readFileBytes(path);

            assert(result.hasError);

            assert(
                result.error.code ==
                FileUpdateErrorCode.invalidTarget
            );

            assert(
                result.error.stage ==
                FileUpdateStage.preCommit
            );

            assert(result.error.nativeCode == 0);
            assert(!result.error.targetCommitted);
        }
    }
}
