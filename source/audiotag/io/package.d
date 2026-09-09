/++
Format-independent file-update orchestration for audiotag.

This package contains I/O coordination logic that is independent of any
specific operating-system file API. Platform backends are introduced
separately.
+/
module audiotag.io;

public import audiotag.io.file_replace;
