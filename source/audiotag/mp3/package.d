/++
Public consumer surface for initial MP3 container inspection and updates.

The current MP3 layer is deliberately small. It can locate and bound a
prepended ID3v2.3 or ID3v2.4 tag, expose the remaining source bytes, plan
replacement of that leading tag and materialize the plan into a new owned
byte buffer. It does not yet validate MPEG audio frames, scan for appended
metadata or perform file I/O.

The container layer reuses the revision-specific ID3 envelope parsers so
ID3 size, footer and validation rules remain owned by the tag codecs.
+/
module audiotag.mp3;

public import audiotag.core.error :
    ParseError,
    ParseErrorCode;

public import audiotag.core.result :
    ParseResult;

public import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

public import audiotag.core.span :
    ByteSpan;

public import audiotag.mp3.prefix :
    Mp3LeadingId3v2Kind,
    Mp3PrefixLayout,
    parseMp3Prefix;

public import audiotag.mp3.prefix_write_plan :
    Mp3LeadingId3v2WritePlan,
    planMp3LeadingId3v2Write;

public import audiotag.mp3.prefix_write :
    Mp3LeadingId3v2WriteResult,
    materializeMp3LeadingId3v2Write;
