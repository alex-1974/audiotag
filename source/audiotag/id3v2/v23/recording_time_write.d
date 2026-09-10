/++
Write decomposition for legacy ID3v2.3 recording-time metadata.

ID3v2.3 represents one recording time through up to three independent
ordinary text-information frames:

- `TYER`: four decimal digits `YYYY`;
- `TDAT`: four decimal digits `DDMM`;
- `TIME`: four decimal digits `HHMM`.

The canonical model can represent richer and more irregular temporal shapes
than this legacy native representation. This module therefore performs only
lossless decomposition. Unsupported precision or component shapes are rejected
explicitly rather than normalized or silently discarded.

No frame headers or payload bytes are serialized here.
+/
module audiotag.id3v2.v23.recording_time_write;

import audiotag.id3v2.v23.recording_time :
    Id3v23RecordingTimeText,
    parseId3v23RecordingTime;

import audiotag.metadata.value :
    MetadataDateTime,
    MetadataDateTimeList;


/++
Outcome of decomposing one canonical recording date/time value into the
legacy ID3v2.3 TYER/TDAT/TIME representation.
+/
enum Id3v23RecordingTimeWriteStatus : ubyte
{
    /// The canonical value has one lossless native decomposition.
    ready,

    /// TYER/TDAT/TIME can represent only one canonical temporal value.
    unsupportedValueCount,

    /// The one canonical temporal value contains no semantic component.
    emptyValue,

    /// Component presence or precision cannot be represented losslessly.
    unsupportedComponentShape,

    /// A present canonical numeric component exceeds native range.
    valueOutOfRange,

    /// Native-width components form an impossible calendar or clock value.
    invalidCalendarOrClockValue
}


/++
Deterministic native decomposition of one canonical recording time.

Each present string is already formatted exactly as required by the matching
ID3v2.3 text-information frame. Absent components have an empty string and
must not produce a native frame.
+/
struct Id3v23RecordingTimeWritePlan
{
    Id3v23RecordingTimeWriteStatus status;

    bool hasYear;
    string year;

    bool hasDate;
    string date;

    bool hasTime;
    string time;

    /++ Returns whether this value may proceed to native frame serialization. +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v23RecordingTimeWriteStatus.ready;
    }
}


/++
Plans lossless decomposition of canonical `recordingDate` content to legacy
ID3v2.3 recording-time frames.

Representability rules:

- exactly one `MetadataDateTime` value is required;
- year is independently optional and must be in `0000..9999` when present;
- month and day must either both be present or both be absent;
- hour and minute must either both be present or both be absent;
- seconds, fractional seconds and UTC offsets are not representable by
  TYER/TDAT/TIME and are rejected;
- calendar and clock values must be valid under the same native validation
  rules used by the reader.

The result preserves only semantics genuinely expressible by ID3v2.3. It does
not invent missing components, round precision, drop timezone information or
coerce invalid dates.

Params:
    value = Canonical ordered date/time list from `recordingDate`.

Returns:
    Deterministic native component plan or an explicit non-writable status.
+/
Id3v23RecordingTimeWritePlan
planId3v23RecordingTimeWrite(
    ref const(MetadataDateTimeList) value
)
    @safe
{
    if (
        value.values.length !=
        1
    )
    {
        return failure(
            Id3v23RecordingTimeWriteStatus
                .unsupportedValueCount
        );
    }

    ref const timestamp =
        value.values[0];

    if (timestamp.empty)
    {
        return failure(
            Id3v23RecordingTimeWriteStatus
                .emptyValue
        );
    }

    if (
        timestamp.hasMonth !=
            timestamp.hasDay ||
        timestamp.hasHour !=
            timestamp.hasMinute ||
        timestamp.hasSecond ||
        timestamp.hasFractionalSecond ||
        timestamp.hasUtcOffset
    )
    {
        return failure(
            Id3v23RecordingTimeWriteStatus
                .unsupportedComponentShape
        );
    }

    if (
        timestamp.hasYear &&
        (
            timestamp.year < 0 ||
            timestamp.year > 9999
        )
    )
    {
        return failure(
            Id3v23RecordingTimeWriteStatus
                .valueOutOfRange
        );
    }

    Id3v23RecordingTimeWritePlan result;

    result.status =
        Id3v23RecordingTimeWriteStatus.ready;

    Id3v23RecordingTimeText nativeText;

    if (timestamp.hasYear)
    {
        result.hasYear = true;
        result.year =
            formatFourDigits(
                cast(uint)
                    timestamp.year
            );

        nativeText.hasYear = true;
        nativeText.year = result.year;
    }

    if (timestamp.hasMonth)
    {
        result.hasDate = true;
        result.date =
            formatFourDigits(
                cast(uint)
                    timestamp.day * 100 +
                timestamp.month
            );

        nativeText.hasDate = true;
        nativeText.date = result.date;
    }

    if (timestamp.hasHour)
    {
        result.hasTime = true;
        result.time =
            formatFourDigits(
                cast(uint)
                    timestamp.hour * 100 +
                timestamp.minute
            );

        nativeText.hasTime = true;
        nativeText.time = result.time;
    }

    const parsed =
        parseId3v23RecordingTime(
            nativeText
        );

    if (!parsed.parsed)
    {
        return failure(
            Id3v23RecordingTimeWriteStatus
                .invalidCalendarOrClockValue
        );
    }

    return result;
}


private Id3v23RecordingTimeWritePlan
failure(
    Id3v23RecordingTimeWriteStatus status
)
    @safe pure nothrow @nogc
{
    return
        Id3v23RecordingTimeWritePlan(
            status
        );
}


private string
formatFourDigits(
    uint value
)
    @safe
{
    assert(value <= 9999);

    char[4] digits;

    foreach_reverse (index; 0 .. digits.length)
    {
        digits[index] =
            cast(char)
                ('0' + value % 10);

        value /= 10;
    }

    return digits[].idup;
}


version (unittest)
{
    private MetadataDateTimeList
    single(
        MetadataDateTime value
    )
        @safe
    {
        return
            MetadataDateTimeList(
                [
                    value
                ]
            );
    }
}


/// A complete minute-precision timestamp decomposes deterministically.
unittest
{
    auto timestamp =
        MetadataDateTime.calendarDate(
            2000,
            2,
            29
        );

    timestamp.hasHour = true;
    timestamp.hour = 23;
    timestamp.hasMinute = true;
    timestamp.minute = 59;

    auto value =
        single(timestamp);

    const plan =
        planId3v23RecordingTimeWrite(
            value
        );

    assert(plan.writable);

    assert(plan.hasYear);
    assert(plan.year == "2000");

    assert(plan.hasDate);
    assert(plan.date == "2902");

    assert(plan.hasTime);
    assert(plan.time == "2359");
}


/// Year, date and time components are independently optional natively.
unittest
{
    auto yearValue =
        single(
            MetadataDateTime.yearOnly(
                7
            )
        );

    const yearPlan =
        planId3v23RecordingTimeWrite(
            yearValue
        );

    assert(yearPlan.writable);
    assert(yearPlan.hasYear);
    assert(yearPlan.year == "0007");
    assert(!yearPlan.hasDate);
    assert(!yearPlan.hasTime);

    MetadataDateTime dateOnly;
    dateOnly.hasMonth = true;
    dateOnly.month = 6;
    dateOnly.hasDay = true;
    dateOnly.day = 12;

    auto dateValue =
        single(dateOnly);

    const datePlan =
        planId3v23RecordingTimeWrite(
            dateValue
        );

    assert(datePlan.writable);
    assert(!datePlan.hasYear);
    assert(datePlan.hasDate);
    assert(datePlan.date == "1206");
    assert(!datePlan.hasTime);

    MetadataDateTime timeOnly;
    timeOnly.hasHour = true;
    timeOnly.hour = 7;
    timeOnly.hasMinute = true;
    timeOnly.minute = 45;

    auto timeValue =
        single(timeOnly);

    const timePlan =
        planId3v23RecordingTimeWrite(
            timeValue
        );

    assert(timePlan.writable);
    assert(!timePlan.hasYear);
    assert(!timePlan.hasDate);
    assert(timePlan.hasTime);
    assert(timePlan.time == "0745");
}


/// The exact four-digit native year range includes explicit year zero.
unittest
{
    auto minimum =
        single(
            MetadataDateTime.yearOnly(
                0
            )
        );

    const minimumPlan =
        planId3v23RecordingTimeWrite(
            minimum
        );

    assert(minimumPlan.writable);
    assert(minimumPlan.year == "0000");

    auto maximum =
        single(
            MetadataDateTime.yearOnly(
                9999
            )
        );

    const maximumPlan =
        planId3v23RecordingTimeWrite(
            maximum
        );

    assert(maximumPlan.writable);
    assert(maximumPlan.year == "9999");
}


/// TYER/TDAT/TIME cannot encode multiple canonical temporal values.
unittest
{
    MetadataDateTimeList value;

    value.values =
        [
            MetadataDateTime.yearOnly(1999),
            MetadataDateTime.yearOnly(2000)
        ];

    const plan =
        planId3v23RecordingTimeWrite(
            value
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23RecordingTimeWriteStatus
            .unsupportedValueCount
    );
}


/// Empty canonical temporal content has no native frame representation.
unittest
{
    auto value =
        single(
            MetadataDateTime.init
        );

    const plan =
        planId3v23RecordingTimeWrite(
            value
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23RecordingTimeWriteStatus
            .emptyValue
    );
}


/// Partial date or clock pairs are rejected rather than invented.
unittest
{
    MetadataDateTime monthOnly;
    monthOnly.hasMonth = true;
    monthOnly.month = 6;

    auto monthValue =
        single(monthOnly);

    assert(
        planId3v23RecordingTimeWrite(
            monthValue
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .unsupportedComponentShape
    );

    MetadataDateTime hourOnly;
    hourOnly.hasHour = true;
    hourOnly.hour = 7;

    auto hourValue =
        single(hourOnly);

    assert(
        planId3v23RecordingTimeWrite(
            hourValue
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .unsupportedComponentShape
    );
}


/// Precision beyond minutes and timezone semantics are rejected losslessly.
unittest
{
    auto seconds =
        MetadataDateTime.yearOnly(
            2000
        );

    seconds.hasSecond = true;
    seconds.second = 30;

    auto secondsValue =
        single(seconds);

    assert(
        planId3v23RecordingTimeWrite(
            secondsValue
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .unsupportedComponentShape
    );

    auto fraction =
        MetadataDateTime.yearOnly(
            2000
        );

    fraction.hasFractionalSecond = true;
    fraction.fractionalSecondNanoseconds = 1;
    fraction.fractionalSecondDigits = 9;

    auto fractionValue =
        single(fraction);

    assert(
        planId3v23RecordingTimeWrite(
            fractionValue
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .unsupportedComponentShape
    );

    auto utc =
        MetadataDateTime.yearOnly(
            2000
        );

    utc.hasUtcOffset = true;
    utc.utcOffsetMinutes = 0;

    auto utcValue =
        single(utc);

    assert(
        planId3v23RecordingTimeWrite(
            utcValue
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .unsupportedComponentShape
    );
}


/// Canonical years outside the native four-digit range are rejected.
unittest
{
    foreach (year; [-1L, 10_000L])
    {
        auto value =
            single(
                MetadataDateTime.yearOnly(
                    year
                )
            );

        const plan =
            planId3v23RecordingTimeWrite(
                value
            );

        assert(!plan.writable);

        assert(
            plan.status ==
            Id3v23RecordingTimeWriteStatus
                .valueOutOfRange
        );
    }
}


/// Native-width but impossible calendar and clock values remain invalid.
unittest
{
    auto impossibleDate =
        single(
            MetadataDateTime.calendarDate(
                2001,
                2,
                29
            )
        );

    assert(
        planId3v23RecordingTimeWrite(
            impossibleDate
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .invalidCalendarOrClockValue
    );

    MetadataDateTime impossibleTime;
    impossibleTime.hasHour = true;
    impossibleTime.hour = 24;
    impossibleTime.hasMinute = true;
    impossibleTime.minute = 0;

    auto impossibleTimeValue =
        single(impossibleTime);

    assert(
        planId3v23RecordingTimeWrite(
            impossibleTimeValue
        ).status ==
        Id3v23RecordingTimeWriteStatus
            .invalidCalendarOrClockValue
    );
}
