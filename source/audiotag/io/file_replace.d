/++
Backend-injected orchestration for safe whole-file replacement.

This module implements the portable transaction order defined by ADR 0007
without performing operating-system I/O itself.

A backend owns target/path state and provides concrete operations for target
validation, temporary-file management, writing, metadata preservation,
replacement commit and optional post-commit durability work.

The orchestrator owns only:

- operation ordering;
- the commit boundary;
- failure propagation;
- best-effort temporary cleanup before a successful commit.

Platform-specific APIs such as POSIX `rename` or Windows `ReplaceFileW` do not
belong in this module.
+/
module audiotag.io.file_replace;

import audiotag.core.file_update :
    FileUpdateError,
    FileUpdateResult,
    FileUpdateStage;


/++
Marker value returned by successful backend transaction steps.

The type intentionally carries no payload. It avoids assigning artificial
meaning to a `bool` or integer merely to fit the generic result type.
+/
struct FileReplacementStepDone
{
}


/++
Result type required from one backend transaction step.
+/
alias FileReplacementStepResult =
    FileUpdateResult!FileReplacementStepDone;


/++
Successful result of one complete file-replacement transaction.

The value is the number of replacement bytes submitted to the backend.
+/
alias FileReplacementResult =
    FileUpdateResult!size_t;


/++
Constructs a successful backend step result.
+/
FileReplacementStepResult
fileReplacementStepDone()
    @safe pure nothrow @nogc
{
    return
        FileReplacementStepResult
            .success(
                FileReplacementStepDone.init
            );
}


/++
Runs one whole-file replacement transaction through an injected backend.

The backend must provide these methods:

```text
FileReplacementStepResult prepareTarget()
FileReplacementStepResult createTemporary()
FileReplacementStepResult writeReplacement(const(ubyte)[] bytes)
FileReplacementStepResult preserveMetadata()
FileReplacementStepResult closeTemporary()
FileReplacementStepResult commitReplacement()
FileReplacementStepResult finalizeCommittedTarget()
FileReplacementStepResult abortTemporary()
```

Error-stage contract:

```text
prepareTarget            -> preCommit
createTemporary          -> preCommit
writeReplacement         -> preCommit
preserveMetadata         -> preCommit
closeTemporary           -> preCommit
abortTemporary           -> preCommit
commitReplacement        -> commit
finalizeCommittedTarget  -> postCommit
```

A backend violating this mapping has a programming error. The orchestrator
asserts the stage before propagating an error.

After `createTemporary()` succeeds, any later pre-commit or commit failure
triggers `abortTemporary()` once. Cleanup is best-effort: if cleanup itself
fails, the original causal error remains the returned error. This preserves
the failure that prevented the update from committing.

After `commitReplacement()` succeeds, `abortTemporary()` is never called.
Therefore a `postCommit` failure correctly reports that the new target is
already authoritative.

The orchestrator does not catch exceptions from a backend. Concrete I/O
backends are responsible for translating expected filesystem failures into
`FileUpdateResult` values before crossing this boundary.

Params:
    backend = Mutable backend instance containing target-specific state.
    replacement = Complete replacement bytes to persist.

Returns:
    Number of replacement bytes on success, or the structured backend failure.

Safety:
    This function performs no direct I/O. A safe instantiation requires the
    supplied backend methods to be callable from `@safe` code.
+/
FileReplacementResult
executeFileReplacement(Backend)(
    ref Backend backend,
    const(ubyte)[] replacement
)
    @safe
{
    auto step =
        backend.prepareTarget();

    if (step.hasError)
    {
        return
            propagateFailure(
                step.error,
                FileUpdateStage.preCommit
            );
    }

    step =
        backend.createTemporary();

    if (step.hasError)
    {
        return
            propagateFailure(
                step.error,
                FileUpdateStage.preCommit
            );
    }

    step =
        backend.writeReplacement(
            replacement
        );

    if (step.hasError)
    {
        const error =
            step.error;

        abortTemporaryBestEffort(
            backend
        );

        return
            propagateFailure(
                error,
                FileUpdateStage.preCommit
            );
    }

    step =
        backend.preserveMetadata();

    if (step.hasError)
    {
        const error =
            step.error;

        abortTemporaryBestEffort(
            backend
        );

        return
            propagateFailure(
                error,
                FileUpdateStage.preCommit
            );
    }

    step =
        backend.closeTemporary();

    if (step.hasError)
    {
        const error =
            step.error;

        abortTemporaryBestEffort(
            backend
        );

        return
            propagateFailure(
                error,
                FileUpdateStage.preCommit
            );
    }

    step =
        backend.commitReplacement();

    if (step.hasError)
    {
        const error =
            step.error;

        abortTemporaryBestEffort(
            backend
        );

        return
            propagateFailure(
                error,
                FileUpdateStage.commit
            );
    }

    step =
        backend.finalizeCommittedTarget();

    if (step.hasError)
    {
        return
            propagateFailure(
                step.error,
                FileUpdateStage.postCommit
            );
    }

    return
        FileReplacementResult
            .success(
                replacement.length
            );
}


/++
Propagates one backend failure while checking the backend stage contract.
+/
private FileReplacementResult
propagateFailure(
    FileUpdateError error,
    FileUpdateStage expectedStage
)
    @safe pure nothrow @nogc
{
    assert(
        error.stage ==
        expectedStage
    );

    return
        FileReplacementResult
            .failure(error);
}


/++
Attempts to discard temporary state after a failed uncommitted transaction.

Cleanup failure is deliberately secondary to the causal update failure and
therefore is not returned by the current single-error result model.
+/
private void
abortTemporaryBestEffort(Backend)(
    ref Backend backend
)
    @safe
{
    auto cleanup =
        backend.abortTemporary();

    if (cleanup.hasError)
    {
        assert(
            cleanup.error.stage ==
            FileUpdateStage.preCommit
        );
    }
}


version (unittest)
{
    import audiotag.core.file_update :
        FileUpdateErrorCode;


    /++
    Failure point used by the deterministic fake backend tests.
    +/
    private enum TestFailurePoint : ubyte
    {
        none,
        prepareTarget,
        createTemporary,
        writeReplacement,
        preserveMetadata,
        closeTemporary,
        commitReplacement,
        finalizeCommittedTarget
    }


    /++
    Backend call identifier used to verify exact orchestration order.
    +/
    private enum TestBackendCall : ubyte
    {
        prepareTarget,
        createTemporary,
        writeReplacement,
        preserveMetadata,
        closeTemporary,
        commitReplacement,
        finalizeCommittedTarget,
        abortTemporary
    }


    /++
    Deterministic no-I/O backend used for transaction and failure-injection tests.
    +/
    private struct TestFileReplacementBackend
    {
        TestFailurePoint failAt;
        bool abortFails;

        TestBackendCall[] calls;
        size_t writtenLength;
        bool committed;

        FileReplacementStepResult
        prepareTarget()
            @safe
        {
            calls ~=
                TestBackendCall.prepareTarget;

            if (
                failAt ==
                TestFailurePoint.prepareTarget
            )
            {
                return
                    failure(
                        FileUpdateErrorCode.invalidTarget,
                        FileUpdateStage.preCommit,
                        1
                    );
            }

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        createTemporary()
            @safe
        {
            calls ~=
                TestBackendCall.createTemporary;

            if (
                failAt ==
                TestFailurePoint.createTemporary
            )
            {
                return
                    failure(
                        FileUpdateErrorCode
                            .temporaryFileCreationFailed,
                        FileUpdateStage.preCommit,
                        2
                    );
            }

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        writeReplacement(
            const(ubyte)[] replacement
        )
            @safe
        {
            calls ~=
                TestBackendCall.writeReplacement;

            writtenLength =
                replacement.length;

            if (
                failAt ==
                TestFailurePoint.writeReplacement
            )
            {
                return
                    failure(
                        FileUpdateErrorCode.writeFailed,
                        FileUpdateStage.preCommit,
                        3,
                        replacement.length > 0
                            ? replacement.length - 1
                            : 0
                    );
            }

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        preserveMetadata()
            @safe
        {
            calls ~=
                TestBackendCall.preserveMetadata;

            if (
                failAt ==
                TestFailurePoint.preserveMetadata
            )
            {
                return
                    failure(
                        FileUpdateErrorCode
                            .metadataPreservationFailed,
                        FileUpdateStage.preCommit,
                        4
                    );
            }

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        closeTemporary()
            @safe
        {
            calls ~=
                TestBackendCall.closeTemporary;

            if (
                failAt ==
                TestFailurePoint.closeTemporary
            )
            {
                return
                    failure(
                        FileUpdateErrorCode.closeFailed,
                        FileUpdateStage.preCommit,
                        5
                    );
            }

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        commitReplacement()
            @safe
        {
            calls ~=
                TestBackendCall.commitReplacement;

            if (
                failAt ==
                TestFailurePoint.commitReplacement
            )
            {
                return
                    failure(
                        FileUpdateErrorCode.commitFailed,
                        FileUpdateStage.commit,
                        6
                    );
            }

            committed =
                true;

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        finalizeCommittedTarget()
            @safe
        {
            calls ~=
                TestBackendCall
                    .finalizeCommittedTarget;

            if (
                failAt ==
                TestFailurePoint
                    .finalizeCommittedTarget
            )
            {
                return
                    failure(
                        FileUpdateErrorCode
                            .durabilityFailed,
                        FileUpdateStage.postCommit,
                        7
                    );
            }

            return
                fileReplacementStepDone();
        }

        FileReplacementStepResult
        abortTemporary()
            @safe
        {
            calls ~=
                TestBackendCall.abortTemporary;

            if (abortFails)
            {
                return
                    failure(
                        FileUpdateErrorCode.cleanupFailed,
                        FileUpdateStage.preCommit,
                        8
                    );
            }

            return
                fileReplacementStepDone();
        }

        private FileReplacementStepResult
        failure(
            FileUpdateErrorCode code,
            FileUpdateStage stage,
            uint nativeCode,
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


    /// Successful orchestration executes every step once and commits the target.
    unittest
    {
        auto backend =
            TestFileReplacementBackend.init;

        const ubyte[] replacement =
            [0x11, 0x22, 0x33];

        auto result =
            executeFileReplacement(
                backend,
                replacement
            );

        assert(result.hasValue);
        assert(result.value == replacement.length);
        assert(backend.writtenLength == replacement.length);
        assert(backend.committed);

        assert(
            backend.calls ==
            [
                TestBackendCall.prepareTarget,
                TestBackendCall.createTemporary,
                TestBackendCall.writeReplacement,
                TestBackendCall.preserveMetadata,
                TestBackendCall.closeTemporary,
                TestBackendCall.commitReplacement,
                TestBackendCall.finalizeCommittedTarget
            ]
        );
    }


    /// Failure before temporary creation stops without an abort operation.
    unittest
    {
        auto backend =
            TestFileReplacementBackend(
                TestFailurePoint.createTemporary
            );

        auto result =
            executeFileReplacement(
                backend,
                [cast(ubyte) 0x11]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode
                .temporaryFileCreationFailed
        );

        assert(
            result.error.stage ==
            FileUpdateStage.preCommit
        );

        assert(!result.error.targetCommitted);
        assert(!backend.committed);

        assert(
            backend.calls ==
            [
                TestBackendCall.prepareTarget,
                TestBackendCall.createTemporary
            ]
        );
    }


    /// A write failure aborts temporary state and preserves byte-offset context.
    unittest
    {
        auto backend =
            TestFileReplacementBackend(
                TestFailurePoint.writeReplacement
            );

        const ubyte[] replacement =
            [0x11, 0x22, 0x33];

        auto result =
            executeFileReplacement(
                backend,
                replacement
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.writeFailed
        );

        assert(result.error.byteOffset == 2);
        assert(!result.error.targetCommitted);
        assert(!backend.committed);

        assert(
            backend.calls ==
            [
                TestBackendCall.prepareTarget,
                TestBackendCall.createTemporary,
                TestBackendCall.writeReplacement,
                TestBackendCall.abortTemporary
            ]
        );
    }


    /// Metadata and close failures remain pre-commit and abort temporary state.
    unittest
    {
        foreach (
            failAt;
            [
                TestFailurePoint.preserveMetadata,
                TestFailurePoint.closeTemporary
            ]
        )
        {
            auto backend =
                TestFileReplacementBackend(
                    failAt
                );

            auto result =
                executeFileReplacement(
                    backend,
                    [cast(ubyte) 0x11]
                );

            assert(result.hasError);
            assert(
                result.error.stage ==
                FileUpdateStage.preCommit
            );
            assert(!result.error.targetCommitted);
            assert(!backend.committed);

            assert(
                backend.calls[$ - 1] ==
                TestBackendCall.abortTemporary
            );
        }
    }


    /// Commit failure remains uncommitted and aborts the temporary replacement.
    unittest
    {
        auto backend =
            TestFileReplacementBackend(
                TestFailurePoint.commitReplacement
            );

        auto result =
            executeFileReplacement(
                backend,
                [cast(ubyte) 0x11]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.commitFailed
        );

        assert(
            result.error.stage ==
            FileUpdateStage.commit
        );

        assert(!result.error.targetCommitted);
        assert(!backend.committed);

        assert(
            backend.calls[$ - 1] ==
            TestBackendCall.abortTemporary
        );
    }


    /// Post-commit failure never aborts and reports the new target authoritative.
    unittest
    {
        auto backend =
            TestFileReplacementBackend(
                TestFailurePoint
                    .finalizeCommittedTarget
            );

        auto result =
            executeFileReplacement(
                backend,
                [cast(ubyte) 0x11]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.durabilityFailed
        );

        assert(
            result.error.stage ==
            FileUpdateStage.postCommit
        );

        assert(result.error.targetCommitted);
        assert(backend.committed);

        foreach (call; backend.calls)
        {
            assert(
                call !=
                TestBackendCall.abortTemporary
            );
        }
    }


    /// Cleanup failure does not hide the causal pre-commit update failure.
    unittest
    {
        auto backend =
            TestFileReplacementBackend(
                TestFailurePoint.writeReplacement,
                true
            );

        auto result =
            executeFileReplacement(
                backend,
                [
                    cast(ubyte) 0x11,
                    cast(ubyte) 0x22
                ]
            );

        assert(result.hasError);

        assert(
            result.error.code ==
            FileUpdateErrorCode.writeFailed
        );

        assert(result.error.nativeCode == 3);
        assert(!result.error.targetCommitted);

        assert(
            backend.calls[$ - 1] ==
            TestBackendCall.abortTemporary
        );
    }
}
