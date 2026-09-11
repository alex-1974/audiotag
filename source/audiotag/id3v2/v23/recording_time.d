/++
ID3v2.3 compatibility names for the shared legacy ID3v2 recording-time parser.

The decoded `TYER`, `TDAT` and `TIME` component syntax is revision-independent
and is implemented in `audiotag.id3v2.common.recording_time`.
+/
module audiotag.id3v2.v23.recording_time;

import audiotag.id3v2.common.recording_time :
    Id3v2RecordingTime,
    Id3v2RecordingTimeParseResult,
    Id3v2RecordingTimeParseStatus,
    Id3v2RecordingTimeText,
    parseId3v2RecordingTime;


alias Id3v23RecordingTime =
    Id3v2RecordingTime;

alias Id3v23RecordingTimeParseResult =
    Id3v2RecordingTimeParseResult;

alias Id3v23RecordingTimeParseStatus =
    Id3v2RecordingTimeParseStatus;

alias Id3v23RecordingTimeText =
    Id3v2RecordingTimeText;

alias parseId3v23RecordingTime =
    parseId3v2RecordingTime;
