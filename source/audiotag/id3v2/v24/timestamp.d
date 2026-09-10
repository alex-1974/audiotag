/++
ID3v2.4 timestamp parsing.

ID3v2.4 defines timestamps as a strict reduced-precision subset of ISO 8601:

    yyyy
    yyyy-MM
    yyyy-MM-dd
    yyyy-MM-ddTHH
    yyyy-MM-ddTHH:mm
    yyyy-MM-ddTHH:mm:ss

The syntax is interpreted here without depending on the canonical metadata
model. All ID3v2.4 timestamps are UTC by specification; that semantic fact is
applied by the later canonical mapping layer.

No whitespace, timezone suffix, UTC offset, fractional seconds or alternative
separator spelling is accepted by this parser.

Calendar and clock ranges are validated. Seconds value 60 is retained as the
ISO-style leap-second representation; this parser does not maintain a
historical leap-second table.
+/
module audiotag.id3v2.v24.timestamp;


/++ Outcome of parsing one ID3v2.4 timestamp string. +/
enum Id3v24TimestampParseStatus : ubyte
{
    invalidSyntax,
    invalidValue,
    parsed
}


/++
Native semantic components of one ID3v2.4 timestamp.

Year is always present. Remaining components form a precision prefix:
month, day, hour, minute, second.
+/
struct Id3v24Timestamp
{
    ushort year;

    bool hasMonth;
    ubyte month;

    bool hasDay;
    ubyte day;

    bool hasHour;
    ubyte hour;

    bool hasMinute;
    ubyte minute;

    bool hasSecond;
    ubyte second;
}


/++ Result of one ID3v2.4 timestamp parse. +/
struct Id3v24TimestampParseResult
{
    Id3v24TimestampParseStatus status;
    Id3v24Timestamp value;

    @property
    bool parsed() const
        @safe pure nothrow @nogc
    {
        return status == Id3v24TimestampParseStatus.parsed;
    }

    private static Id3v24TimestampParseResult success(
        Id3v24Timestamp value
    )
        @safe pure nothrow @nogc
    {
        return Id3v24TimestampParseResult(
            Id3v24TimestampParseStatus.parsed,
            value
        );
    }

    private static Id3v24TimestampParseResult invalidSyntax()
        @safe pure nothrow @nogc
    {
        return Id3v24TimestampParseResult(
            Id3v24TimestampParseStatus.invalidSyntax,
            Id3v24Timestamp.init
        );
    }

    private static Id3v24TimestampParseResult invalidValue()
        @safe pure nothrow @nogc
    {
        return Id3v24TimestampParseResult(
            Id3v24TimestampParseStatus.invalidValue,
            Id3v24Timestamp.init
        );
    }
}


/++
Parses one decoded ID3v2.4 timestamp.

Accepted lengths and separators are exact. Component ranges are validated
against the Gregorian calendar and a 24-hour UTC clock.
+/
Id3v24TimestampParseResult
parseId3v24Timestamp(
    string text
)
    @safe pure nothrow @nogc
{
    switch (text.length)
    {
        case 4:
            break;

        case 7:
            if (text[4] != '-')
                return Id3v24TimestampParseResult.invalidSyntax();
            break;

        case 10:
            if (
                text[4] != '-' ||
                text[7] != '-'
            )
            {
                return Id3v24TimestampParseResult.invalidSyntax();
            }
            break;

        case 13:
            if (
                text[4] != '-' ||
                text[7] != '-' ||
                text[10] != 'T'
            )
            {
                return Id3v24TimestampParseResult.invalidSyntax();
            }
            break;

        case 16:
            if (
                text[4] != '-' ||
                text[7] != '-' ||
                text[10] != 'T' ||
                text[13] != ':'
            )
            {
                return Id3v24TimestampParseResult.invalidSyntax();
            }
            break;

        case 19:
            if (
                text[4] != '-' ||
                text[7] != '-' ||
                text[10] != 'T' ||
                text[13] != ':' ||
                text[16] != ':'
            )
            {
                return Id3v24TimestampParseResult.invalidSyntax();
            }
            break;

        default:
            return Id3v24TimestampParseResult.invalidSyntax();
    }

    foreach (index, character; text)
    {
        if (
            index == 4 ||
            index == 7 ||
            index == 10 ||
            index == 13 ||
            index == 16
        )
        {
            continue;
        }

        if (
            character < '0' ||
            character > '9'
        )
        {
            return Id3v24TimestampParseResult.invalidSyntax();
        }
    }

    Id3v24Timestamp result;

    result.year =
        cast(ushort)
            (
                digit(text[0]) * 1000 +
                digit(text[1]) * 100 +
                digit(text[2]) * 10 +
                digit(text[3])
            );

    if (text.length >= 7)
    {
        result.hasMonth = true;
        result.month = parseTwoDigits(text[5], text[6]);

        if (
            result.month < 1 ||
            result.month > 12
        )
        {
            return Id3v24TimestampParseResult.invalidValue();
        }
    }

    if (text.length >= 10)
    {
        result.hasDay = true;
        result.day = parseTwoDigits(text[8], text[9]);

        if (
            result.day < 1 ||
            result.day > daysInMonth(result.year, result.month)
        )
        {
            return Id3v24TimestampParseResult.invalidValue();
        }
    }

    if (text.length >= 13)
    {
        result.hasHour = true;
        result.hour = parseTwoDigits(text[11], text[12]);

        if (result.hour > 23)
            return Id3v24TimestampParseResult.invalidValue();
    }

    if (text.length >= 16)
    {
        result.hasMinute = true;
        result.minute = parseTwoDigits(text[14], text[15]);

        if (result.minute > 59)
            return Id3v24TimestampParseResult.invalidValue();
    }

    if (text.length == 19)
    {
        result.hasSecond = true;
        result.second = parseTwoDigits(text[17], text[18]);

        if (result.second > 60)
            return Id3v24TimestampParseResult.invalidValue();
    }

    return Id3v24TimestampParseResult.success(result);
}


private uint
digit(
    char value
)
    @safe pure nothrow @nogc
{
    return cast(uint) (value - '0');
}


private ubyte
parseTwoDigits(
    char high,
    char low
)
    @safe pure nothrow @nogc
{
    return cast(ubyte) (
        digit(high) * 10 +
        digit(low)
    );
}


private ubyte
daysInMonth(
    ushort year,
    ubyte month
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
            return isLeapYear(year) ? 29 : 28;

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


/// Every precision explicitly listed by ID3v2.4 is accepted.
unittest
{
    const inputs =
    [
        "1999",
        "1999-12",
        "2000-02-29",
        "2001-06-12T23",
        "2001-06-12T23:45",
        "2001-06-12T23:45:59"
    ];

    foreach (input; inputs)
    {
        const result = parseId3v24Timestamp(input);
        assert(result.parsed);
    }
}


/// Parsed components preserve the native precision exactly.
unittest
{
    const year = parseId3v24Timestamp("1999");

    assert(year.parsed);
    assert(year.value.year == 1999);
    assert(!year.value.hasMonth);

    const full =
        parseId3v24Timestamp(
            "2001-06-12T23:45:01"
        );

    assert(full.parsed);
    assert(full.value.year == 2001);
    assert(full.value.hasMonth);
    assert(full.value.month == 6);
    assert(full.value.hasDay);
    assert(full.value.day == 12);
    assert(full.value.hasHour);
    assert(full.value.hour == 23);
    assert(full.value.hasMinute);
    assert(full.value.minute == 45);
    assert(full.value.hasSecond);
    assert(full.value.second == 1);
}


/// Gregorian leap-day validity is checked.
unittest
{
    assert(parseId3v24Timestamp("2000-02-29").parsed);
    assert(!parseId3v24Timestamp("1900-02-29").parsed);
    assert(parseId3v24Timestamp("2004-02-29").parsed);
}


/// Leap-second syntax remains representable as second 60.
unittest
{
    const result =
        parseId3v24Timestamp(
            "2016-12-31T23:59:60"
        );

    assert(result.parsed);
    assert(result.value.second == 60);
}


/// Invalid ID3v2.4 timestamp syntax is rejected without normalization.
unittest
{
    foreach (
        input;
        [
            "",
            "199",
            "19990",
            "1999-1",
            "1999/01",
            "1999-01-1",
            "1999-01-01t12",
            "1999-01-01 12",
            "1999-01-01T12:00Z",
            "1999-01-01T12:00+02:00",
            "1999-01-01T12:00:00.1",
            " 1999",
            "1999 "
        ]
    )
    {
        const result = parseId3v24Timestamp(input);

        assert(!result.parsed);
        assert(
            result.status ==
            Id3v24TimestampParseStatus.invalidSyntax
        );
    }
}


/// Syntactically shaped but impossible component values are rejected.
unittest
{
    foreach (
        input;
        [
            "1999-00",
            "1999-13",
            "1999-01-00",
            "1999-04-31",
            "2001-02-29",
            "1999-01-01T24",
            "1999-01-01T23:60",
            "1999-01-01T23:59:61"
        ]
    )
    {
        const result = parseId3v24Timestamp(input);

        assert(!result.parsed);
        assert(
            result.status ==
            Id3v24TimestampParseStatus.invalidValue
        );
    }
}
