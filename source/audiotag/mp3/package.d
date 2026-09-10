/++
Public consumer surface for initial MP3 container inspection and updates.

The current MP3 layer is deliberately small. It can locate and bound a
prepended ID3v2.3 or ID3v2.4 tag and a fixed trailing ID3v1 block, expose the
remaining source bytes, plan and materialize edge-tag replacement, and expose
leading-ID3v2 and trailing-ID3v1 operations through high-level in-memory update
APIs. POSIX builds additionally expose path-based leading-ID3v2 and
trailing-ID3v1 updates backed by structured whole-file reads and atomic file
replacement.

The layer does not yet validate MPEG audio frames or coordinate multiple
trailing tag systems such as APEv2, Lyrics3 and ID3v1. Tag interpretation
remains owned by the revision-specific metadata codecs.
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

public import audiotag.mp3.suffix :
    Mp3SuffixLayout,
    locateMp3TrailingId3v1;

public import audiotag.mp3.suffix_write_plan :
    Mp3TrailingId3v1WritePlan,
    planMp3TrailingId3v1Write;

public import audiotag.mp3.suffix_write :
    Mp3TrailingId3v1WriteResult,
    materializeMp3TrailingId3v1Write;

public import audiotag.mp3.layout :
    Mp3Layout,
    parseMp3Layout;

public import audiotag.mp3.prefix_write_plan :
    Mp3LeadingId3v2WritePlan,
    planMp3LeadingId3v2Write;

public import audiotag.mp3.prefix_write :
    Mp3LeadingId3v2WriteResult,
    materializeMp3LeadingId3v2Write;

public import audiotag.mp3.api :
    Mp3LeadingId3v2UpdateResult,
    Mp3TrailingId3v1UpdateResult,
    updateMp3LeadingId3v2,
    updateMp3TrailingId3v1;

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

    public import audiotag.mp3.suffix_file_api :
        Mp3TrailingId3v1FileUpdateError,
        Mp3TrailingId3v1FileUpdateErrorDomain,
        Mp3TrailingId3v1FileUpdateResult,
        updateMp3TrailingId3v1File;
}
