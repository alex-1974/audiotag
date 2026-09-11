/++
Shared semantic tempo concepts used by ID3v2 synchronised-tempo frames.

ID3v2.2 `STC` and ID3v2.3/v2.4 `SYTC` use the same tempo semantics:

- `$00`: beat-free period;
- `$01`: one single beat followed by a beat-free period;
- values from 2 through 510: tempo in beats per minute.

The physical one- or two-byte encoding and raw source provenance remain
revision-specific.
+/
module audiotag.id3v2.common.tempo;

enum Id3v2TempoKind : ubyte
{
    beatFree,
    singleBeat,
    beatsPerMinute
}

struct Id3v2Tempo
{
    Id3v2TempoKind kind;
    ushort beatsPerMinute;
}

unittest
{
    const beatFree =
        Id3v2Tempo(
            Id3v2TempoKind.beatFree,
            0
        );

    const singleBeat =
        Id3v2Tempo(
            Id3v2TempoKind.singleBeat,
            0
        );

    const bpm =
        Id3v2Tempo(
            Id3v2TempoKind.beatsPerMinute,
            300
        );

    assert(beatFree.kind == Id3v2TempoKind.beatFree);
    assert(singleBeat.kind == Id3v2TempoKind.singleBeat);
    assert(bpm.kind == Id3v2TempoKind.beatsPerMinute);
    assert(bpm.beatsPerMinute == 300);
}
