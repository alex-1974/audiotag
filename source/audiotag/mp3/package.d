/++
Public consumer surface for initial MP3 container inspection and updates.

The current MP3 layer is deliberately small. It can locate and bound a
prepended ID3v2.3 or ID3v2.4 tag, expose the remaining source bytes, plan
replacement of that leading tag, materialize the plan into a new owned
byte buffer and expose those steps through one high-level in-memory update
operation. POSIX builds additionally expose a path-based leading-ID3v2
update operation backed by structured whole-file reads and atomic file
replacement.

The layer does not yet validate MPEG audio frames or scan for appended
metadata. ID3 size, footer and validation rules remain owned by the
revision-specific tag codecs.
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

public import audiotag.mp3.api :
    Mp3LeadingId3v2UpdateResult,
    updateMp3LeadingId3v2;

version (Posix)
{
    public import audiotag.core.file_update :
        FileUpdateError,
        FileUpdateErrorCode,
        FileUpdateStage;

    public import audiotag.mp3.file_api :
        Mp3LeadingId3v2FileUpdateError,
        Mp3LeadingId3v2FileUpdateErrorDomain,
        Mp3LeadingId3v2FileUpdateResult,
        updateMp3LeadingId3v2File;
}
