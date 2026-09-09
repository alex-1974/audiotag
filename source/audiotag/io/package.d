/++
File-update orchestration and platform backends for audiotag.

The portable orchestrator is independent of operating-system file APIs.
Platform backends implement the concrete filesystem operations required by
that transaction model.
+/
module audiotag.io;

public import audiotag.io.file_read;
public import audiotag.io.file_replace;

version (Posix)
{
    public import audiotag.io.posix_file_replace;
}
