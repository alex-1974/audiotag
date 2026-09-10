/++
Public consumer surface for initial ID3v1 support.

The current ID3v1 layer parses an exact 128-byte ID3v1.0/ID3v1.1 block and
exposes raw zero-copy field spans, revision, track and genre bytes. It also
provides strict specification-based ISO-8859-1 decoding of NUL-padded string
fields.

Raw spans remain available so callers can deliberately handle non-conforming
legacy encodings without heuristic decoding or loss of source bytes.

Title, artist, album, comment, the ID3v1.1 track number and recognized
numeric genres can be projected into the shared canonical metadata model with
exact native provenance. Unknown genre bytes remain native-only. Year remains
native-only until canonical date semantics are defined.

This package does not locate an ID3v1 trailer inside an MP3 file or serialize
tags yet. Those responsibilities remain separate later layers.
+/
module audiotag.id3v1;

public import audiotag.core.error :
    ParseError,
    ParseErrorCode;

public import audiotag.core.result :
    ParseResult;

public import audiotag.core.span :
    ByteSpan;

public import audiotag.id3v1.tag :
    Id3v1Revision,
    Id3v1Tag,
    id3v1TagSize,
    parseId3v1Tag;

public import audiotag.id3v1.text_decode :
    decodeId3v1Latin1Text,
    id3v1TextContent;

public import audiotag.id3v1.canonical :
    Id3v1CanonicalTag,
    parseId3v1CanonicalTag,
    projectId3v1TagToCanonical;
