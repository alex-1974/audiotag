/++
Strict parsing and aggregation of legacy ID3v2.3 recording-time text.

ID3v2.3 distributes one recording time across up to three independent text
information frames:

- `TYER`: four decimal digits containing the recording year;
- `TDAT`: four decimal digits in `DDMM` order;
- `TIME`: four decimal digits in `HHMM` order.

The format does not require all three components to be present together.
This module therefore preserves component presence independently and does not
invent dependencies between year, date and time.

This is native-format logic only. It does not depend on the canonical metadata
model and does not assign timezone semantics.
+/
module audiotag.id3v2.v23.recording_time;


/++ Outcome of aggregating legacy ID3v2.3 recording-time components. +/
enum Id3v23RecordingTimeParseStatus : ubyte
{
    /// No TYER, TDAT or TIME component was supplied.
    noComponents,

    /// A supplied component does not have exact four-digit syntax.
    invalidSyntax,

    /// Syntax is correct but a calendar or clock component is impossible.
    invalidValue,

    /// At least one supplied component parsed successfully.
    parsed
}


/++
Presence-aware decoded text for one legacy ID3v2.3 recording time.

The boolean flags distinguish an absent frame from a present frame whose
decoded text is empty or otherwise invalid.
+/
struct Id3v23RecordingTimeText
{
    bool hasYear;
    string year;

    bool hasDate;
    string date;

    bool hasTime;
    string time;
}


/++
Validated native semantic components of one legacy ID3v2.3 recording time.

`TDAT` contributes month and day together. `TIME` contributes hour and minute
together. `TYER` is independent.
+/
struct Id3v23RecordingTime
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
struct Id3v23RecordingTimeParseResult
{
    Id3v23RecordingTimeParseStatus status;
    Id3v23RecordingTime value;

    @property
    bool parsed() const
        @safe pure nothrow @nogc
    {
        return
            status ==
            Id3v23RecordingTimeParseStatus.parsed;
    }

    private static Id3v23RecordingTimeParseResult success(
        Id3v23RecordingTime value
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v23RecordingTimeParseResult(
                Id3v23RecordingTimeParseStatus.parsed,
                value
            );
    }

    private static Id3v23RecordingTimeParseResult failure(
        Id3v23RecordingTimeParseStatus status
    )
        @safe pure nothrow @nogc
    {
        return
            Id3v23RecordingTimeParseResult(
                status,
                Id3v23RecordingTime.init
            );
    }
}


/++
Strictly parses supplied ID3v2.3 recording-time components.

Every present component must be exactly four ASCII decimal digits.

Native forms:

- TYER: `YYYY`
- TDAT: `DDMM`
- TIME: `HHMM`

Calendar validation is as strong as the supplied native data permits.
February 29 is accepted when TDAT occurs without TYER because it is valid in
some years. When TYER is also present, leap-year validity is checked against
that year.

No timezone, trimming, normalization, separator tolerance or missing component
is invented.

Params:
    input = Presence-aware decoded TYER/TDAT/TIME text.

Returns:
    Validated native recording-time components or an explicit parse status.
+/
Id3v23RecordingTimeParseResult
parseId3v23RecordingTime(
    Id3v23RecordingTimeText input
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
            Id3v23RecordingTimeParseResult.failure(
                Id3v23RecordingTimeParseStatus.noComponents
            );
    }

    Id3v23RecordingTime result;

    if (input.hasYear)
    {
        ushort year;

        if (!parseFourDigits(input.year, year))
        {
            return
                Id3v23RecordingTimeParseResult.failure(
                    Id3v23RecordingTimeParseStatus.invalidSyntax
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
                Id3v23RecordingTimeParseResult.failure(
                    Id3v23RecordingTimeParseStatus.invalidSyntax
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
                Id3v23RecordingTimeParseResult.failure(
                    Id3v23RecordingTimeParseStatus.invalidValue
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
                Id3v23RecordingTimeParseResult.failure(
                    Id3v23RecordingTimeParseStatus.invalidValue
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
                Id3v23RecordingTimeParseResult.failure(
                    Id3v23RecordingTimeParseStatus.invalidSyntax
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
                Id3v23RecordingTimeParseResult.failure(
                    Id3v23RecordingTimeParseStatus.invalidValue
                );
        }

        result.hasHour = true;
        result.hour = hour;

        result.hasMinute = true;
        result.minute = minute;
    }

    return
        Id3v23RecordingTimeParseResult.success(
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
    private Id3v23RecordingTimeText
    yearInput(
        string year
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v23RecordingTimeText.init;

        result.hasYear = true;
        result.year = year;

        return result;
    }


    private Id3v23RecordingTimeText
    dateInput(
        string date
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v23RecordingTimeText.init;

        result.hasDate = true;
        result.date = date;

        return result;
    }


    private Id3v23RecordingTimeText
    timeInput(
        string time
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v23RecordingTimeText.init;

        result.hasTime = true;
        result.time = time;

        return result;
    }


    private Id3v23RecordingTimeText
    completeInput(
        string year,
        string date,
        string time
    )
        @safe pure nothrow @nogc
    {
        auto result =
            Id3v23RecordingTimeText.init;

        result.hasYear = true;
        result.year = year;

        result.hasDate = true;
        result.date = date;

        result.hasTime = true;
        result.time = time;

        return result;
    }
}


/// A complete TYER/TDAT/TIME set is combined without timezone semantics.
unittest
{
    const parsed =
        parseId3v23RecordingTime(
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
        parseId3v23RecordingTime(
            yearInput(
                "1999"
            )
        );

    assert(yearOnly.parsed);
    assert(yearOnly.value.hasYear);
    assert(!yearOnly.value.hasMonth);
    assert(!yearOnly.value.hasHour);

    const dateOnly =
        parseId3v23RecordingTime(
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
        parseId3v23RecordingTime(
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
        parseId3v23RecordingTime(
            dateInput(
                "2902"
            )
        ).parsed
    );

    auto leap =
        Id3v23RecordingTimeText.init;

    leap.hasYear = true;
    leap.year = "2000";
    leap.hasDate = true;
    leap.date = "2902";

    assert(
        parseId3v23RecordingTime(
            leap
        ).parsed
    );

    auto nonLeap =
        Id3v23RecordingTimeText.init;

    nonLeap.hasYear = true;
    nonLeap.year = "2001";
    nonLeap.hasDate = true;
    nonLeap.date = "2902";

    const parsed =
        parseId3v23RecordingTime(
            nonLeap
        );

    assert(!parsed.parsed);

    assert(
        parsed.status ==
        Id3v23RecordingTimeParseStatus.invalidValue
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
            parseId3v23RecordingTime(
                dateInput(
                    value
                )
            );

        assert(!parsed.parsed);

        assert(
            parsed.status ==
            Id3v23RecordingTimeParseStatus.invalidValue
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
            parseId3v23RecordingTime(
                timeInput(
                    value
                )
            );

        assert(!parsed.parsed);

        assert(
            parsed.status ==
            Id3v23RecordingTimeParseStatus.invalidValue
        );
    }
}


/// Present components must use exact four-digit ID3v2.3 syntax.
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
            parseId3v23RecordingTime(
                yearInput(
                    value
                )
            );

        assert(!parsed.parsed);

        assert(
            parsed.status ==
            Id3v23RecordingTimeParseStatus.invalidSyntax
        );
    }

    assert(
        parseId3v23RecordingTime(
            dateInput(
                "12-6"
            )
        ).status ==
        Id3v23RecordingTimeParseStatus.invalidSyntax
    );

    assert(
        parseId3v23RecordingTime(
            timeInput(
                "07:45"
            )
        ).status ==
        Id3v23RecordingTimeParseStatus.invalidSyntax
    );
}


/// An absent legacy recording-time group is distinct from malformed data.
unittest
{
    const parsed =
        parseId3v23RecordingTime(
            Id3v23RecordingTimeText.init
        );

    assert(!parsed.parsed);

    assert(
        parsed.status ==
        Id3v23RecordingTimeParseStatus.noComponents
    );
}


/// Four zero year digits remain explicit native numeric content.
unittest
{
    const parsed =
        parseId3v23RecordingTime(
            yearInput(
                "0000"
            )
        );

    assert(parsed.parsed);
    assert(parsed.value.hasYear);
    assert(parsed.value.year == 0);
}
