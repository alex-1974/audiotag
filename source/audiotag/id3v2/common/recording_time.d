/++
Shared strict parsing of legacy ID3v2 recording-time text.

ID3v2.2 and ID3v2.3 represent one recording time through three independent
text components with the same decoded syntax:

- year: four decimal digits `YYYY`;
- date: four decimal digits `DDMM`;
- time: four decimal digits `HHMM`.

The native frame identifiers differ by revision (`TYE`/`TDA`/`TIM` versus
`TYER`/`TDAT`/`TIME`), but the decoded component semantics do not. This module
therefore owns the revision-independent parser.

The format does not require all components to be present together. Component
presence remains independent and no timezone semantics are invented.
+/
module audiotag.id3v2.common.recording_time;


/++ Outcome of aggregating legacy ID3v2 recording-time components. +/
enum Id3v2RecordingTimeParseStatus : ubyte
{
    /// No year, date or time component was supplied.
    noComponents,

    /// A supplied component does not have exact four-digit syntax.
    invalidSyntax,

    /// Syntax is correct but a calendar or clock component is impossible.
    invalidValue,

    /// At least one supplied component parsed successfully.
    parsed
}


/++
Presence-aware decoded text for one legacy ID3v2 recording time.

The boolean flags distinguish an absent frame from a present frame whose
decoded text is empty or otherwise invalid.
+/
struct Id3v2RecordingTimeText
{
    bool hasYear;
    string year;

    bool hasDate;
    string date;

    bool hasTime;
    string time;
}


/++
Validated semantic components of one legacy ID3v2 recording time.

The date component contributes month and day together. The time component
contributes hour and minute together. Year remains independent.
+/
struct Id3v2RecordingTime
{
    bool hasYear;
    ushort year;

    bool hasMonth;
    ubyte month;

    bool hasDay;
    ubyte day;

    bool hasHour;
    ubyte hour;

    bool hasMinute;
    ubyte minute;
}


/++ Result of strict legacy recording-time aggregation. +/
struct Id3v2RecordingTimeParseResult
{
    Id3v2RecordingTimeParseStatus status;
    Id3v2RecordingTime value;

    @property
    bool parsed() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v2RecordingTimeParseStatus.parsed;
    }

    private static Id3v2RecordingTimeParseResult success(
        Id3v2RecordingTime value
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v2RecordingTimeParseResult(
                Id3v2RecordingTimeParseStatus.parsed,
                value
            );
    }

    private static Id3v2RecordingTimeParseResult failure(
        Id3v2RecordingTimeParseStatus status
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v2RecordingTimeParseResult(
                status,
                Id3v2RecordingTime.init
            );
    }
}


/++
Strictly parses supplied legacy ID3v2 recording-time components.

Every present component must be exactly four ASCII decimal digits.

Native forms:

- year: `YYYY`
- date: `DDMM`
- time: `HHMM`

Calendar validation is as strong as the supplied native data permits.
February 29 is accepted when a date occurs without a year because it is valid
in some years. When a year is also present, leap-year validity is checked
against that year.

No timezone, trimming, normalization, separator tolerance or missing component
is invented.
+/
Id3v2RecordingTimeParseResult
parseId3v2RecordingTime(
    Id3v2RecordingTimeText input
)
    @safe pure nothrow @nogc
{
    if (
        !input.hasYear &&
        !input.hasDate &&
        !input.hasTime
    )
    {
        return
            Id3v2RecordingTimeParseResult.failure(
                Id3v2RecordingTimeParseStatus.noComponents
            );
    }

    Id3v2RecordingTime result;

    if (input.hasYear)
    {
        ushort year;

        if (!parseFourDigits(input.year, year))
        {
            return
                Id3v2RecordingTimeParseResult.failure(
                    Id3v2RecordingTimeParseStatus.invalidSyntax
                );
        }

        result.hasYear = true;
        result.year = year;
    }

    if (input.hasDate)
    {
        ushort dateDigits;

        if (!parseFourDigits(input.date, dateDigits))
        {
            return
                Id3v2RecordingTimeParseResult.failure(
                    Id3v2RecordingTimeParseStatus.invalidSyntax
                );
        }

        const day =
            cast(ubyte)
                (dateDigits / 100);

        const month =
            cast(ubyte)
                (dateDigits % 100);

        if (
            month < 1 ||
            month > 12
        )
        {
            return
                Id3v2RecordingTimeParseResult.failure(
                    Id3v2RecordingTimeParseStatus.invalidValue
                );
        }

        const maximumDay =
            maximumDayFor(
                month,
                result.hasYear,
                result.year
            );

        if (
            day < 1 ||
            day > maximumDay
        )
        {
            return
                Id3v2RecordingTimeParseResult.failure(
                    Id3v2RecordingTimeParseStatus.invalidValue
                );
        }

        result.hasMonth = true;
        result.month = month;

        result.hasDay = true;
        result.day = day;
    }

    if (input.hasTime)
    {
        ushort timeDigits;

        if (!parseFourDigits(input.time, timeDigits))
        {
            return
                Id3v2RecordingTimeParseResult.failure(
                    Id3v2RecordingTimeParseStatus.invalidSyntax
                );
        }

        const hour =
            cast(ubyte)
                (timeDigits / 100);

        const minute =
            cast(ubyte)
                (timeDigits % 100);

        if (
            hour > 23 ||
            minute > 59
        )
        {
            return
                Id3v2RecordingTimeParseResult.failure(
                    Id3v2RecordingTimeParseStatus.invalidValue
                );
        }

        result.hasHour = true;
        result.hour = hour;

        result.hasMinute = true;
        result.minute = minute;
    }

    return
        Id3v2RecordingTimeParseResult.success(
            result
        );
}


private bool
parseFourDigits(
    string text,
    out ushort value
)
    @safe pure nothrow @nogc
{
    if (text.length != 4)
        return false;

    uint parsedValue;

    foreach (character; text)
    {
        if (
            character < '0' ||
            character > '9'
        )
        {
            return false;
        }

        parsedValue =
            parsedValue * 10 +
            cast(uint)
                (character - '0');
    }

    value =
        cast(ushort)
            parsedValue;

    return true;
}


private ubyte
maximumDayFor(
    ubyte month,
    bool hasYear,
    ushort year
)
    @safe pure nothrow @nogc
{
    switch (month)
    {
        case 1:
        case 3:
        case 5:
        case 7:
        case 8:
        case 10:
        case 12:
            return 31;

        case 4:
        case 6:
        case 9:
        case 11:
            return 30;

        case 2:
            if (!hasYear)
                return 29;

            return
                isLeapYear(year)
                ? 29
                : 28;

        default:
            return 0;
    }
}


private bool
isLeapYear(
    ushort year
)
    @safe pure nothrow @nogc
{
    return
        year % 400 == 0 ||
        (
            year % 4 == 0 &&
            year % 100 != 0
        );
}


version (unittest)
{
    private Id3v2RecordingTimeText
    yearInput(
        string year
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v2RecordingTimeText.init;

        result.hasYear = true;
        result.year = year;

        return result;
    }


    private Id3v2RecordingTimeText
    dateInput(
        string date
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v2RecordingTimeText.init;

        result.hasDate = true;
        result.date = date;

        return result;
    }


    private Id3v2RecordingTimeText
    timeInput(
        string time
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v2RecordingTimeText.init;

        result.hasTime = true;
        result.time = time;

        return result;
    }


    private Id3v2RecordingTimeText
    completeInput(
        string year,
        string date,
        string time
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v2RecordingTimeText.init;

        result.hasYear = true;
        result.year = year;

        result.hasDate = true;
        result.date = date;

        result.hasTime = true;
        result.time = time;

        return result;
    }
}


/// A complete year/date/time set is combined without timezone semantics.
unittest
{
    const parsed =
        parseId3v2RecordingTime(
            completeInput(
                "2000",
                "2902",
                "2359"
            )
        );

    assert(parsed.parsed);

    assert(parsed.value.hasYear);
    assert(parsed.value.year == 2000);

    assert(parsed.value.hasMonth);
    assert(parsed.value.month == 2);

    assert(parsed.value.hasDay);
    assert(parsed.value.day == 29);

    assert(parsed.value.hasHour);
    assert(parsed.value.hour == 23);

    assert(parsed.value.hasMinute);
    assert(parsed.value.minute == 59);
}


/// Each legacy recording-time component may occur independently.
unittest
{
    const yearOnly =
        parseId3v2RecordingTime(
            yearInput(
                "1999"
            )
        );

    assert(yearOnly.parsed);
    assert(yearOnly.value.hasYear);
    assert(!yearOnly.value.hasMonth);
    assert(!yearOnly.value.hasHour);

    const dateOnly =
        parseId3v2RecordingTime(
            dateInput(
                "1206"
            )
        );

    assert(dateOnly.parsed);
    assert(!dateOnly.value.hasYear);
    assert(dateOnly.value.hasMonth);
    assert(dateOnly.value.month == 6);
    assert(dateOnly.value.hasDay);
    assert(dateOnly.value.day == 12);

    const timeOnly =
        parseId3v2RecordingTime(
            timeInput(
                "0745"
            )
        );

    assert(timeOnly.parsed);
    assert(!timeOnly.value.hasYear);
    assert(!timeOnly.value.hasMonth);
    assert(timeOnly.value.hasHour);
    assert(timeOnly.value.hour == 7);
    assert(timeOnly.value.hasMinute);
    assert(timeOnly.value.minute == 45);
}


/// February 29 is conditionally validated when a year is available.
unittest
{
    assert(
        parseId3v2RecordingTime(
            dateInput(
                "2902"
            )
        ).parsed
    );

    auto leap =
        Id3v2RecordingTimeText.init;

    leap.hasYear = true;
    leap.year = "2000";
    leap.hasDate = true;
    leap.date = "2902";

    assert(
        parseId3v2RecordingTime(
            leap
        ).parsed
    );

    auto nonLeap =
        Id3v2RecordingTimeText.init;

    nonLeap.hasYear = true;
    nonLeap.year = "2001";
    nonLeap.hasDate = true;
    nonLeap.date = "2902";

    const parsed =
        parseId3v2RecordingTime(
            nonLeap
        );

    assert(!parsed.parsed);

    assert(
        parsed.status ==
        Id3v2RecordingTimeParseStatus.invalidValue
    );
}


/// Impossible calendar values are rejected.
unittest
{
    foreach (
        value;
        [
            "0001",
            "3113",
            "3104"
        ]
    )
    {
        const parsed =
            parseId3v2RecordingTime(
                dateInput(
                    value
                )
            );

        assert(!parsed.parsed);

        assert(
            parsed.status ==
            Id3v2RecordingTimeParseStatus.invalidValue
        );
    }
}


/// Impossible clock values are rejected.
unittest
{
    foreach (
        value;
        [
            "2400",
            "2360"
        ]
    )
    {
        const parsed =
            parseId3v2RecordingTime(
                timeInput(
                    value
                )
            );

        assert(!parsed.parsed);

        assert(
            parsed.status ==
            Id3v2RecordingTimeParseStatus.invalidValue
        );
    }
}


/// Present components must use exact four-digit syntax.
unittest
{
    foreach (
        value;
        [
            "",
            "999",
            "10000",
            "20A1",
            " 999",
            "999 "
        ]
    )
    {
        const parsed =
            parseId3v2RecordingTime(
                yearInput(
                    value
                )
            );

        assert(!parsed.parsed);

        assert(
            parsed.status ==
            Id3v2RecordingTimeParseStatus.invalidSyntax
        );
    }

    assert(
        parseId3v2RecordingTime(
            dateInput(
                "12-6"
            )
        ).status ==
        Id3v2RecordingTimeParseStatus.invalidSyntax
    );

    assert(
        parseId3v2RecordingTime(
            timeInput(
                "07:45"
            )
        ).status ==
        Id3v2RecordingTimeParseStatus.invalidSyntax
    );
}


/// An absent legacy recording-time group is distinct from malformed data.
unittest
{
    const parsed =
        parseId3v2RecordingTime(
            Id3v2RecordingTimeText.init
        );

    assert(!parsed.parsed);

    assert(
        parsed.status ==
        Id3v2RecordingTimeParseStatus.noComponents
    );
}


/// Four zero year digits remain explicit native numeric content.
unittest
{
    const parsed =
        parseId3v2RecordingTime(
            yearInput(
                "0000"
            )
        );

    assert(parsed.parsed);
    assert(parsed.value.hasYear);
    assert(parsed.value.year == 0);
}
