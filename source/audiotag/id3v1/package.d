/++
Public consumer surface for initial ID3v1 support.

The current ID3v1 layer is deliberately structural and lossless. It parses an
exact 128-byte ID3v1.0/ID3v1.1 block and exposes raw zero-copy field spans,
revision, track and genre bytes.

This package does not locate an ID3v1 trailer inside an MP3 file, decode the
historically ambiguous text encoding, map fields into canonical metadata or
serialize tags yet. Those responsibilities remain separate later layers.
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
