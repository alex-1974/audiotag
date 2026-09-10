/++
Shared parsing of ID3v2 numeric position text.

ID3v2 track-position and part-of-set values use the same native shape: a
decimal number, optionally followed by "/" and a decimal total. This module
parses only that native syntax and deliberately does not depend on the
canonical metadata model.
+/
module audiotag.id3v2.common.position;

enum Id3v2PositionParseStatus : ubyte
{
    invalidSyntax,
    integerOverflow,
    parsed
}

struct Id3v2NumericPosition
{
    ulong number;
    bool hasTotal;
    ulong total;
}

struct Id3v2PositionParseResult
{
    Id3v2PositionParseStatus status;
    Id3v2NumericPosition value;

    @property
    bool parsed() const
        @safe pure nothrow @nogc
    {
        return status == Id3v2PositionParseStatus.parsed;
    }

    private static Id3v2PositionParseResult success(
        Id3v2NumericPosition value
    )
        @safe pure nothrow @nogc
    {
        return Id3v2PositionParseResult(
            Id3v2PositionParseStatus.parsed,
            value
        );
    }

    private static Id3v2PositionParseResult invalid()
        @safe pure nothrow @nogc
    {
        return Id3v2PositionParseResult(
            Id3v2PositionParseStatus.invalidSyntax,
            Id3v2NumericPosition.init
        );
    }

    private static Id3v2PositionParseResult overflow()
        @safe pure nothrow @nogc
    {
        return Id3v2PositionParseResult(
            Id3v2PositionParseStatus.integerOverflow,
            Id3v2NumericPosition.init
        );
    }
}

private struct DecimalParseResult
{
    Id3v2PositionParseStatus status;
    ulong value;

    @property
    bool parsed() const
        @safe pure nothrow @nogc
    {
        return status == Id3v2PositionParseStatus.parsed;
    }
}

Id3v2PositionParseResult
parseId3v2Position(
    string text
)
    @safe pure nothrow @nogc
{
    if (text.length == 0)
        return Id3v2PositionParseResult.invalid();

    size_t separator = text.length;
    bool hasSeparator;

    foreach (index, character; text)
    {
        if (character == '/')
        {
            if (hasSeparator)
                return Id3v2PositionParseResult.invalid();

            hasSeparator = true;
            separator = index;
            continue;
        }

        if (character < '0' || character > '9')
            return Id3v2PositionParseResult.invalid();
    }

    if (
        separator == 0 ||
        (
            hasSeparator &&
            separator + 1 == text.length
        )
    )
    {
        return Id3v2PositionParseResult.invalid();
    }

    const numberResult = parseDecimal(text[0 .. separator]);

    if (!numberResult.parsed)
    {
        return numberResult.status == Id3v2PositionParseStatus.integerOverflow
            ? Id3v2PositionParseResult.overflow()
            : Id3v2PositionParseResult.invalid();
    }

    if (!hasSeparator)
    {
        return Id3v2PositionParseResult.success(
            Id3v2NumericPosition(
                numberResult.value,
                false,
                0
            )
        );
    }

    const totalResult =
        parseDecimal(
            text[separator + 1 .. text.length]
        );

    if (!totalResult.parsed)
    {
        return totalResult.status == Id3v2PositionParseStatus.integerOverflow
            ? Id3v2PositionParseResult.overflow()
            : Id3v2PositionParseResult.invalid();
    }

    return Id3v2PositionParseResult.success(
        Id3v2NumericPosition(
            numberResult.value,
            true,
            totalResult.value
        )
    );
}

private DecimalParseResult
parseDecimal(
    string text
)
    @safe pure nothrow @nogc
{
    if (text.length == 0)
    {
        return DecimalParseResult(
            Id3v2PositionParseStatus.invalidSyntax,
            0
        );
    }

    ulong value;

    foreach (character; text)
    {
        if (character < '0' || character > '9')
        {
            return DecimalParseResult(
                Id3v2PositionParseStatus.invalidSyntax,
                0
            );
        }

        const digit = cast(ulong) (character - '0');

        if (value > (ulong.max - digit) / 10)
        {
            return DecimalParseResult(
                Id3v2PositionParseStatus.integerOverflow,
                0
            );
        }

        value = value * 10 + digit;
    }

    return DecimalParseResult(
        Id3v2PositionParseStatus.parsed,
        value
    );
}

unittest
{
    const numberOnly = parseId3v2Position("4");

    assert(numberOnly.parsed);
    assert(numberOnly.value.number == 4);
    assert(!numberOnly.value.hasTotal);

    const pair = parseId3v2Position("004/009");

    assert(pair.parsed);
    assert(pair.value.number == 4);
    assert(pair.value.hasTotal);
    assert(pair.value.total == 9);
}

unittest
{
    const zero = parseId3v2Position("0/0");

    assert(zero.parsed);
    assert(zero.value.number == 0);
    assert(zero.value.hasTotal);
    assert(zero.value.total == 0);

    const maximum =
        parseId3v2Position(
            "18446744073709551615/18446744073709551615"
        );

    assert(maximum.parsed);
    assert(maximum.value.number == ulong.max);
    assert(maximum.value.total == ulong.max);
}

unittest
{
    foreach (
        text;
        [
            "",
            "/9",
            "4/",
            "4//9",
            "4/9/10",
            "-1",
            "+1",
            " 4",
            "4 ",
            "4 / 9",
            "4x",
            "4/x"
        ]
    )
    {
        const result = parseId3v2Position(text);

        assert(!result.parsed);
        assert(
            result.status ==
            Id3v2PositionParseStatus.invalidSyntax
        );
    }
}

unittest
{
    foreach (
        text;
        [
            "18446744073709551616",
            "1/18446744073709551616"
        ]
    )
    {
        const result = parseId3v2Position(text);

        assert(!result.parsed);
        assert(
            result.status ==
            Id3v2PositionParseStatus.integerOverflow
        );
    }
}
