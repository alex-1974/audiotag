# ADR 0007: Replace updated files through a same-filesystem temporary file

## Status

Accepted.

## Context

`audiotag` now has an in-memory MP3 update path that can build a complete
replacement byte stream without modifying the source file.

Persisting such an update introduces a different class of failure modes from
parsing and serialization:

- a process may fail after truncating a destination but before writing all
  replacement bytes;
- the filesystem may run out of space during a write;
- a rename or replacement may fail because of permissions, sharing modes or
  filesystem boundaries;
- a crash may occur before or after the replacement becomes visible;
- creating a new file can accidentally change permissions, ACLs or other
  security-relevant attributes;
- predictable temporary names can collide with or be redirected by another
  process;
- a path may refer to a symbolic link, hard-linked file or non-regular file;
- another process may modify the target concurrently.

A container writer therefore must not equate "serialize bytes" with "safely
update a file".

Atomic visibility and crash durability are also different guarantees. A name
replacement can be atomic while the newly written data or directory entry is
not yet guaranteed to survive power loss.

The portable D `std.file.rename` API overwrites an existing destination and
documents atomic replacement on POSIX when source and destination are on the
same filesystem. It does not document the same cross-platform atomicity
guarantee for Windows. Windows provides dedicated replacement primitives with
different metadata-preservation and sharing semantics.

## Decision

File updates are performed by **replacement**, never by truncating and
rewriting the original file in place.

The file-update layer uses the following conceptual transaction:

```text
read / validate / serialize
        |
        v
create unique temporary file beside target
        |
        v
write complete replacement bytes
        |
        v
apply required target metadata / permissions
        |
        v
flush language/runtime buffers and close temporary file
        |
        v
commit with an operating-system replacement primitive
        |
        v
optional stronger durability synchronization
```

### Same directory and same filesystem

The temporary file is created in the target file's directory.

This is required because an atomic rename/replacement normally requires source
and destination to reside on the same filesystem or volume. The implementation
must not silently fall back to copy-and-delete across filesystems.

A cross-filesystem condition is an update failure, not a reason to weaken the
replacement guarantee.

### Temporary-file creation

Temporary-file creation must be exclusive and collision-safe.

The implementation must not use a predictable name followed by an ordinary
open that can overwrite or follow an attacker-controlled pre-existing path.

Before commit, the temporary file should use permissions no broader than
necessary. Security-relevant permissions must never become more permissive
merely because the update is implemented through a newly created file.

### Commit primitive

The final namespace change is platform-specific behind one safe abstraction.

On POSIX, the intended primitive is same-filesystem atomic replacement through
`rename` semantics.

On Windows, the implementation should use a Windows replacement primitive
whose semantics are appropriate for replacing an existing regular file, rather
than assuming that a generic portable rename has identical guarantees.
`ReplaceFileW` is preferred where its metadata-preservation semantics fit the
operation. A weaker copy-and-delete fallback is not permitted under the atomic
update API.

All handles that would prevent replacement on the target platform must be
closed before the commit attempt.

### Failure boundary

The update result must make the commit boundary observable.

Before the replacement primitive succeeds:

> failure means the original target path has not intentionally been replaced.

The temporary file should be cleaned up on failure where possible.

After the replacement primitive succeeds:

> the new file is the committed target, even if a later durability or cleanup
> step fails.

A post-commit failure must not be reported in a way that implies the old file
is still authoritative. Future structured I/O errors should therefore carry
enough stage information to distinguish at least:

```text
preCommit
commit
postCommit
```

Plain success/failure without commit-state information is insufficient once
post-commit operations exist.

### Atomicity versus durability

The baseline update contract requires atomic visibility of the replacement on
platform/filesystem combinations where the backend claims that guarantee.

It does **not** silently promise power-loss durability.

A stronger durability mode may be added separately. Such a mode must use the
platform-appropriate synchronization sequence, for example syncing replacement
file data before commit and, where required, the containing directory after
commit.

If the platform or filesystem cannot provide the requested durability
guarantee, the API must report that limitation rather than pretending the
baseline atomic replacement is equivalent.

### Metadata policy

Security-relevant access metadata must not be accidentally weakened by
replacement.

The implementation must preserve the original file's ordinary access
permissions and equivalent security attributes where the selected platform
backend supports this safely. Platform-specific ACLs, extended attributes,
alternate streams, encryption/compression flags and ownership require explicit
backend policy; unsupported preservation must be documented rather than
silently claimed.

Modification time is not preserved by default because the file content has
changed. A future explicit policy may request timestamp preservation.

No implementation should claim full metadata preservation merely because the
file bytes were preserved correctly.

### Symbolic links and non-regular files

The initial safe-update API operates on regular files.

A symbolic-link path is rejected by default rather than silently replacing the
link object or unexpectedly modifying its target. Other special filesystem
objects are likewise rejected.

Explicit link-aware behavior may be added later as a separate policy.

### Hard links

Atomic path replacement changes which file object the updated pathname refers
to.

Other hard links to the original file continue to refer to the old file
object. The initial safe-update API accepts this consequence because avoiding
partial writes takes priority over preserving inode/file identity.

The API and documentation must not imply that all hard-linked names are
updated together.

### Concurrent external writers

The initial replacement model does not claim a portable compare-and-swap
transaction against other processes.

An implementation may detect obvious target changes between read and commit,
but it must not present such checks as race-free unless the platform backend
actually provides that guarantee.

Applications requiring coordinated multi-process editing need an explicit
locking or conflict-detection policy above the baseline replacement operation.

### No hidden backup

The default operation does not create a persistent backup copy.

Backup creation, if added, is an explicit policy because it changes filesystem
side effects, privacy characteristics and cleanup requirements.

## Consequences

- a failed write cannot leave the original file half-truncated;
- serialization/container logic remains independent of filesystem mechanics;
- the I/O layer needs platform-specific replacement backends even though the
  higher-level API can remain portable;
- atomic replacement requires temporary space approximately equal to the
  replacement file size;
- hard-linked aliases are not updated and file identity may change;
- symlink and special-file behavior is conservative by default;
- security metadata preservation becomes an explicit implementation
  responsibility;
- power-loss durability is a separate, stronger contract rather than an
  accidental promise;
- post-commit errors require structured commit-stage reporting;
- tests for the future I/O implementation must inject failures before write
  completion, before commit, at commit and after commit and verify which file
  remains authoritative;
- platform/filesystem behavior that cannot meet the requested replacement
  guarantee must fail explicitly rather than silently degrading to
  copy-and-delete.

## References

- D `std.file.rename` documentation:
  https://dlang.org/phobos/std_file.html
- POSIX/Linux `rename(2)` semantics:
  https://man7.org/linux/man-pages/man2/rename.2.html
- Windows `ReplaceFile`:
  https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-replacefilew
- Windows `MoveFileEx`:
  https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-movefileexw
