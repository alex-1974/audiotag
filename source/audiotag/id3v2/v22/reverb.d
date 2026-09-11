/++
ID3v2.2 reverb (`REV`) frame decoding.

`REV` has a fixed logical payload size of twelve bytes:

- reverb delay left, unsigned 16-bit big-endian milliseconds;
- reverb delay right, unsigned 16-bit big-endian milliseconds;
- bounce count left;
- bounce count right;
- feedback left-to-left;
- feedback left-to-right;
- feedback right-to-right;
- feedback right-to-left;
- premix left-to-right;
- premix right-to-left.

A bounce-count byte of `$FF` means infinitely many bounces. Feedback and
premix bytes use `$00` for 0% and `$FF` for 100%.

Whole-tag unsynchronisation is reversed during logical traversal. Raw field
spans retain the exact physical source representation, including stuffing
bytes.

This module performs no canonical metadata mapping.
+/
module audiotag.id3v2.v22.reverb;

import audiotag.core.error :
    ParseError,
    ParseErrorCode;

import audiotag.core.result :
    ParseResult;

import audiotag.core.span :
    ByteSpan;

import audiotag.id3v2.common.reverb :
    Id3v2ReverbSettings,
    decodeId3v2ReverbBounceCount;

import audiotag.id3v2.v22.data_cursor :
    Id3v22DataCursor;

import audiotag.id3v2.v22.frame :
    Id3v22FrameEnvelope;

private struct Id3v22ReverbByte
{
    ubyte value;
    ByteSpan raw;
}

private ParseResult!Id3v22ReverbByte
takeId3v22ReverbByte(
    ref Id3v22DataCursor cursor
)
    @safe pure nothrow @nogc
{
    auto probe = cursor;
    const start = probe.remainingRaw;

    auto byteResult = probe.takeByte();

    if (byteResult.hasError)
    {
        return ParseResult!Id3v22ReverbByte.failure(byteResult.error);
    }

    const physicalLength =
        start.length -
        probe.remainingRaw.length;

    const raw = start.subspan(0, physicalLength);

    cursor = probe;

    return
        ParseResult!Id3v22ReverbByte
            .success(
                Id3v22ReverbByte(
                    byteResult.value.value,
                    raw
                )
            );
}

struct Id3v22ReverbFrame
{
    size_t sourceOffset;
    Id3v2ReverbSettings settings;

    ByteSpan rawLeftDelay;
    ByteSpan rawRightDelay;
    ByteSpan rawLeftBounces;
    ByteSpan rawRightBounces;

    ByteSpan rawFeedbackLeftToLeft;
    ByteSpan rawFeedbackLeftToRight;
    ByteSpan rawFeedbackRightToRight;
    ByteSpan rawFeedbackRightToLeft;

    ByteSpan rawPremixLeftToRight;
    ByteSpan rawPremixRightToLeft;

    bool effectiveUnsynchronisation;
}

ParseResult!Id3v22ReverbFrame
decodeId3v22ReverbFrame(
    Id3v22FrameEnvelope frame,
    bool tagUnsynchronised = false
)
    @safe
{
    if (frame.header.id[] != "REV")
    {
        return
            ParseResult!Id3v22ReverbFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidSignature,
                        frame.header.sourceOffset
                    )
                );
    }

    if (frame.header.size != 12)
    {
        return
            ParseResult!Id3v22ReverbFrame
                .failure(
                    ParseError(
                        ParseErrorCode.invalidLength,
                        frame.data.sourceOffset,
                        12,
                        frame.header.size
                    )
                );
    }

    auto payload =
        Id3v22DataCursor(
            frame.data,
            tagUnsynchronised
        );

    const leftDelayStart = payload.remainingRaw;
    auto leftDelayResult = payload.takeU16BE();

    if (leftDelayResult.hasError)
    {
        return ParseResult!Id3v22ReverbFrame.failure(leftDelayResult.error);
    }

    const rawLeftDelay =
        leftDelayStart.subspan(
            0,
            leftDelayStart.length - payload.remainingRaw.length
        );

    const rightDelayStart = payload.remainingRaw;
    auto rightDelayResult = payload.takeU16BE();

    if (rightDelayResult.hasError)
    {
        return ParseResult!Id3v22ReverbFrame.failure(rightDelayResult.error);
    }

    const rawRightDelay =
        rightDelayStart.subspan(
            0,
            rightDelayStart.length - payload.remainingRaw.length
        );

    auto leftBouncesResult = takeId3v22ReverbByte(payload);
    if (leftBouncesResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(leftBouncesResult.error);

    auto rightBouncesResult = takeId3v22ReverbByte(payload);
    if (rightBouncesResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(rightBouncesResult.error);

    auto feedbackLeftToLeftResult = takeId3v22ReverbByte(payload);
    if (feedbackLeftToLeftResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(feedbackLeftToLeftResult.error);

    auto feedbackLeftToRightResult = takeId3v22ReverbByte(payload);
    if (feedbackLeftToRightResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(feedbackLeftToRightResult.error);

    auto feedbackRightToRightResult = takeId3v22ReverbByte(payload);
    if (feedbackRightToRightResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(feedbackRightToRightResult.error);

    auto feedbackRightToLeftResult = takeId3v22ReverbByte(payload);
    if (feedbackRightToLeftResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(feedbackRightToLeftResult.error);

    auto premixLeftToRightResult = takeId3v22ReverbByte(payload);
    if (premixLeftToRightResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(premixLeftToRightResult.error);

    auto premixRightToLeftResult = takeId3v22ReverbByte(payload);
    if (premixRightToLeftResult.hasError)
        return ParseResult!Id3v22ReverbFrame.failure(premixRightToLeftResult.error);

    if (!payload.empty)
    {
        return
            ParseResult!Id3v22ReverbFrame
                .failure(
                    ParseError(
                        ParseErrorCode.inconsistentStructure,
                        payload.absoluteOffset
                    )
                );
    }

    const settings =
        Id3v2ReverbSettings(
            leftDelayResult.value,
            rightDelayResult.value,
            decodeId3v2ReverbBounceCount(leftBouncesResult.value.value),
            decodeId3v2ReverbBounceCount(rightBouncesResult.value.value),
            feedbackLeftToLeftResult.value.value,
            feedbackLeftToRightResult.value.value,
            feedbackRightToRightResult.value.value,
            feedbackRightToLeftResult.value.value,
            premixLeftToRightResult.value.value,
            premixRightToLeftResult.value.value
        );

    return
        ParseResult!Id3v22ReverbFrame
            .success(
                Id3v22ReverbFrame(
                    frame.header.sourceOffset,
                    settings,
                    rawLeftDelay,
                    rawRightDelay,
                    leftBouncesResult.value.raw,
                    rightBouncesResult.value.raw,
                    feedbackLeftToLeftResult.value.raw,
                    feedbackLeftToRightResult.value.raw,
                    feedbackRightToRightResult.value.raw,
                    feedbackRightToLeftResult.value.raw,
                    premixLeftToRightResult.value.raw,
                    premixRightToLeftResult.value.raw,
                    tagUnsynchronised
                )
            );
}

version (unittest)
{
    import audiotag.core.cursor :
        ByteCursor;

    import audiotag.id3v2.v22.frame :
        parseId3v22FrameEnvelope;
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x0C,
            0x00, 0x64,
            0x00, 0xC8,
            0x03,
            0xFF,
            0x40,
            0x20,
            0x10,
            0x08,
            0x00,
            0xFF
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                100
            )
        );

    auto frame = cursor.parseId3v22FrameEnvelope();
    assert(frame.hasValue);

    auto result = frame.value.decodeId3v22ReverbFrame();
    assert(result.hasValue);

    const reverb = result.value;

    assert(reverb.settings.leftDelayMilliseconds == 100);
    assert(reverb.settings.rightDelayMilliseconds == 200);
    assert(!reverb.settings.leftBounces.infinite);
    assert(reverb.settings.leftBounces.finiteCount == 3);
    assert(reverb.settings.rightBounces.infinite);
    assert(reverb.settings.feedbackLeftToLeft == 0x40);
    assert(reverb.settings.feedbackLeftToRight == 0x20);
    assert(reverb.settings.feedbackRightToRight == 0x10);
    assert(reverb.settings.feedbackRightToLeft == 0x08);
    assert(reverb.settings.premixLeftToRight == 0x00);
    assert(reverb.settings.premixRightToLeft == 0xFF);

    assert(reverb.rawLeftDelay.sourceOffset == 106);
    assert(reverb.rawRightDelay.sourceOffset == 108);
    assert(reverb.rawLeftBounces.sourceOffset == 110);
    assert(reverb.rawRightBounces.sourceOffset == 111);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x0B,
            0x00, 0x64,
            0x00, 0xC8,
            0x03,
            0x04,
            0x10,
            0x20,
            0x30,
            0x40,
            0x50
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                300
            )
        );

    auto frame = cursor.parseId3v22FrameEnvelope();
    assert(frame.hasValue);

    auto result = frame.value.decodeId3v22ReverbFrame();
    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.requested == 12);
    assert(result.error.available == 11);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x0D,
            0x00, 0x64,
            0x00, 0xC8,
            0x03,
            0x04,
            0x10,
            0x20,
            0x30,
            0x40,
            0x50,
            0x60,
            0x70
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                400
            )
        );

    auto frame = cursor.parseId3v22FrameEnvelope();
    assert(frame.hasValue);

    auto result = frame.value.decodeId3v22ReverbFrame();
    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidLength);
    assert(result.error.requested == 12);
    assert(result.error.available == 13);
}

unittest
{
    const ubyte[] bytes =
        [
            'R', 'E', 'V',
            0x00, 0x00, 0x0C,
            0x00, 0x64,
            0x00, 0xC8,
            0x03,
            0x04,
            0xFF, 0x00,
            0x20,
            0x10,
            0x08,
            0x00,
            0x01
        ];

    auto cursor =
        Id3v22DataCursor(
            ByteSpan(
                bytes,
                500
            ),
            true
        );

    auto frame = cursor.parseId3v22FrameEnvelope();

    assert(frame.hasValue);
    assert(frame.value.header.size == 12);
    assert(frame.value.data.length == 13);
    assert(cursor.empty);

    auto result =
        frame.value.decodeId3v22ReverbFrame(true);

    assert(result.hasValue);
    assert(result.value.effectiveUnsynchronisation);
    assert(result.value.settings.feedbackLeftToLeft == 0xFF);

    assert(
        result.value.rawFeedbackLeftToLeft.data ==
        [
            0xFF,
            0x00
        ]
    );
}

unittest
{
    const ubyte[] bytes =
        [
            'E', 'Q', 'U',
            0x00, 0x00, 0x0C,
            0x00, 0x64,
            0x00, 0xC8,
            0x03,
            0x04,
            0x10,
            0x20,
            0x30,
            0x40,
            0x50,
            0x60
        ];

    auto cursor =
        ByteCursor(
            ByteSpan(
                bytes,
                600
            )
        );

    auto frame = cursor.parseId3v22FrameEnvelope();
    assert(frame.hasValue);

    auto result = frame.value.decodeId3v22ReverbFrame();
    assert(result.hasError);
    assert(result.error.code == ParseErrorCode.invalidSignature);
    assert(result.error.offset == 600);
}
