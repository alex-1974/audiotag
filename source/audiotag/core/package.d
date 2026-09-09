/++
Format-independent core primitives used by audiotag parsers, serializers
and file-update layers.

This package contains bounded binary parsing primitives and shared
structured result/error types.
+/
module audiotag.core;

public import audiotag.core.cursor;
public import audiotag.core.error;
public import audiotag.core.file_update;
public import audiotag.core.result;
public import audiotag.core.serialization;
public import audiotag.core.span;
