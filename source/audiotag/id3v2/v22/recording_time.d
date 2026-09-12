/++
ID3v2.2 names for the shared legacy ID3v2 recording-time parser.

ID3v2.2 uses frame identifiers `TYE`, `TDA` and `TIM`, but their decoded text
syntax is identical to the legacy ID3v2.3 `TYER`, `TDAT` and `TIME` components.


Standards:
    ID3v2.2.0, https://id3.org/id3v2-00

Authors:
    Alexander Bernardi

Copyright:
    Copyright © 2024, Alexander Bernardi

License:
    CC-BY-SA-4.0

Date:
    2026-09-12
+/
module audiotag.id3v2.v22.recording_time;

import audiotag.id3v2.common.recording_time :
    Id3v2RecordingTime,
    Id3v2RecordingTimeParseResult,
    Id3v2RecordingTimeParseStatus,
    Id3v2RecordingTimeText,
    parseId3v2RecordingTime;


alias Id3v22RecordingTime =
    Id3v2RecordingTime;

alias Id3v22RecordingTimeParseResult =
    Id3v2RecordingTimeParseResult;

alias Id3v22RecordingTimeParseStatus =
    Id3v2RecordingTimeParseStatus;

alias Id3v22RecordingTimeText =
    Id3v2RecordingTimeText;

alias parseId3v22RecordingTime =
    parseId3v2RecordingTime;
