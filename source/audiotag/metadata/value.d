/++
Format-independent canonical metadata value types.

The canonical metadata layer owns semantic values independently of
the lifetime of parser input buffers. Native byte ranges therefore do
not appear in this module; source provenance is represented separately.

`MetadataValue` is a discriminated union of the initial canonical
value families required by the metadata tree.
+/
module audiotag.metadata.value;

import std.sumtype :
    SumType,
    match;


/++
Canonical scalar text.
+/
struct MetadataText
{
    /// Decoded Unicode text.
    string value;
}


/++
Canonical ordered multi-value text.

The distinction between one text value and an ordered list of values
is preserved explicitly rather than being inferred from separators.
+/
struct MetadataTextList
{
    /// Decoded values in their semantic order.
    string[] values;
}


/++
Canonical integer value.

A signed 64-bit representation provides one simple initial integer
domain. More specialized numeric structures may be added later where
metadata semantics require them.
+/
struct MetadataInteger
{
    /// Integer value.
    long value;
}


/++
Canonical position within an ordered set.

Track and disc metadata commonly carry two related numeric components:

- the item's number/position in the set;
- the optional total number of items in that set.

Native formats represent these components differently. ID3v2 may combine
them as `3/12`, Vorbis Comment may store them in separate fields, and MP4
stores them as one numeric pair. The canonical model therefore keeps both
components together while making their presence explicit.

Neither zero nor another numeric value is used as an absence sentinel.
This permits the canonical layer to distinguish an absent component from an
explicit native zero when a format-specific mapper chooses to preserve one.

No relationship such as `number <= total` is imposed here. Validation of
native syntax and format-specific semantic constraints belongs to the codec
or mapping layer.
+/
struct MetadataPosition
{
    /// Whether a position/number is present.
    bool hasNumber;

    /// Position/number when `hasNumber` is true.
    ulong number;

    /// Whether a total count is present.
    bool hasTotal;

    /// Total count when `hasTotal` is true.
    ulong total;

    /// Constructs a position containing only its number.
    static MetadataPosition numberOnly(ulong number)
        @safe pure nothrow @nogc
    {
        return MetadataPosition(true, number, false, 0);
    }

    /// Constructs a position containing both number and total.
    static MetadataPosition numberAndTotal(
        ulong number,
        ulong total
    )
        @safe pure nothrow @nogc
    {
        return MetadataPosition(true, number, true, total);
    }

    /++
    Constructs a position containing only its total.

    This shape is required for metadata systems such as Vorbis Comment,
    where total-count fields are physically independent from number fields.
    +/
    static MetadataPosition totalOnly(ulong total)
        @safe pure nothrow @nogc
    {
        return MetadataPosition(false, 0, true, total);
    }

    /// Returns whether neither semantic component is present.
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return !hasNumber && !hasTotal;
    }
}



/++
Canonical partial date/time value.

Audio metadata formats expose temporal information with different precision
and structure:

- some provide only a year;
- some provide calendar and clock components independently;
- some provide a complete timestamp;
- some specify UTC or an explicit UTC offset;
- some support fractional seconds.

Each component therefore has an explicit presence flag. No numeric sentinel is
used for absence. This permits native mappings such as ID3v2.3 to retain
month/day or hour/minute information even when another date component is not
present.

`fractionalSecondNanoseconds` stores the fractional part scaled to nanoseconds.
`fractionalSecondDigits` records the source semantic precision from 1 through
9 when `hasFractionalSecond` is true. For example, `.125` is represented as
125_000_000 nanoseconds with three fractional digits.

`hasUtcOffset` distinguishes an unspecified/floating time from one whose UTC
offset is known. An offset of zero therefore represents UTC explicitly.

This value type intentionally does not impose calendar, clock, component-
dependency or offset-range invariants. Native syntax and semantic validation
belong to codec/mapping layers, as with `MetadataPosition`. The canonical type
only preserves semantic components that a mapper has already validated.
+/
struct MetadataDateTime
{
    bool hasYear;
    long year;

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

    bool hasFractionalSecond;
    uint fractionalSecondNanoseconds;
    ubyte fractionalSecondDigits;

    bool hasUtcOffset;
    int utcOffsetMinutes;


    /// Constructs a year-only temporal value.
    static MetadataDateTime yearOnly(long year)
        @safe pure nothrow @nogc
    {
        MetadataDateTime result;
        result.hasYear = true;
        result.year = year;
        return result;
    }


    /// Constructs a year-and-month temporal value.
    static MetadataDateTime yearMonth(
        long year,
        ubyte month
    )
        @safe pure nothrow @nogc
    {
        auto result =
            yearOnly(
                year
            );

        result.hasMonth = true;
        result.month = month;
        return result;
    }


    /// Constructs a complete calendar date without a clock value.
    static MetadataDateTime calendarDate(
        long year,
        ubyte month,
        ubyte day
    )
        @safe pure nothrow @nogc
    {
        auto result =
            yearMonth(
                year,
                month
            );

        result.hasDay = true;
        result.day = day;
        return result;
    }


    /// Whether any calendar component is present.
    @property
    bool hasDate() const
        @safe pure nothrow @nogc
    {
        return
            hasYear ||
            hasMonth ||
            hasDay;
    }


    /// Whether any clock/subsecond component is present.
    @property
    bool hasTime() const
        @safe pure nothrow @nogc
    {
        return
            hasHour ||
            hasMinute ||
            hasSecond ||
            hasFractionalSecond;
    }


    /// Whether no temporal component or UTC offset is present.
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return
            !hasDate &&
            !hasTime &&
            !hasUtcOffset;
    }
}


/++
Canonical ordered list of partial date/time values.

A list is explicit because several metadata systems can carry multiple
temporal values for one semantic field. Keeping those values in one canonical
field avoids inferring separators and permits native mappers to preserve
source order.
+/
struct MetadataDateTimeList
{
    MetadataDateTime[] values;

    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return values.length == 0;
    }
}


/++
Canonical URL value.

No URL syntax validation is implied by this type. It distinguishes a
URL semantically from ordinary text while preserving the decoded
string exactly.
+/
struct MetadataUrl
{
    /// Decoded URL.
    string value;
}


/++
Owned canonical binary value.

Binary canonical metadata must not depend on the lifetime of a parser
input buffer. Construction through `copyFrom` duplicates source bytes
into immutable storage.

`mediaType` is optional. It may describe payloads such as embedded
image data while remaining empty for opaque binary metadata such as
private identifiers.
+/
struct MetadataBinary
{
    private immutable(ubyte)[] _data;

    /// Optional media type associated with the binary payload.
    string mediaType;

    /++
    Creates an owned immutable copy of binary metadata.

    Params:
        data = Bytes to copy.
        mediaType = Optional media type.

    Returns:
        Independent canonical binary value.
    +/
    static MetadataBinary copyFrom(
        const(ubyte)[] data,
        string mediaType = ""
    )
        @safe
    {
        return MetadataBinary(
            data.idup,
            mediaType
        );
    }

    /++
    Returns the immutable binary payload.
    +/
    @property
    const(ubyte)[] data() const
        @safe pure nothrow @nogc
    {
        return _data;
    }

    /++
    Returns the binary payload length.
    +/
    @property
    size_t length() const
        @safe pure nothrow @nogc
    {
        return _data.length;
    }

    /++
    Returns whether the binary payload is empty.
    +/
    @property
    bool empty() const
        @safe pure nothrow @nogc
    {
        return _data.length == 0;
    }

    private this(
        immutable(ubyte)[] data,
        string mediaType
    )
        @safe pure nothrow @nogc
    {
        _data = data;
        this.mediaType = mediaType;
    }
}


/++
Source of canonical picture content.

An image may either contain embedded binary data or refer to an
external URL. The distinction is semantic and therefore belongs in
the canonical value model.
+/
alias MetadataPictureSource =
    SumType!(
        MetadataBinary,
        MetadataUrl
    );


/++
Canonical picture/artwork value.

Picture role, scope and other qualifiers intentionally do not belong
to this initial value object. They can be represented by the
surrounding canonical field/qualifier model without making image bytes
ID3-specific.
+/
struct MetadataPicture
{
    /// Human-readable image description, if present.
    string description;

    /// Embedded binary data or linked image URL.
    MetadataPictureSource source;
}


/++
Canonical metadata value.

Wrapper structs intentionally distinguish values that share the same
underlying D representation. In particular, ordinary text and URLs
are not interchangeable merely because both contain `string`.
+/
alias MetadataValue =
    SumType!(
        MetadataText,
        MetadataTextList,
        MetadataInteger,
        MetadataUrl,
        MetadataBinary,
        MetadataPicture,
        MetadataPosition,
        MetadataDateTimeList
    );


/// Scalar text remains distinguishable from other string-like values.
unittest
{
    MetadataValue value =
        MetadataText("Track title");

    const isText =
        value.match!(
            (MetadataText text) =>
                text.value == "Track title",
            _ => false
        );

    assert(isText);
}


/// Ordered text lists retain multiplicity and ordering.
unittest
{
    MetadataValue value =
        MetadataTextList(
            ["one", "two", "three"]
        );

    const matches =
        value.match!(
            (MetadataTextList list) =>
                list.values ==
                ["one", "two", "three"],
            _ => false
        );

    assert(matches);
}


/// Integer metadata remains a distinct canonical value type.
unittest
{
    MetadataValue value =
        MetadataInteger(42);

    const matches =
        value.match!(
            (MetadataInteger integer) =>
                integer.value == 42,
            _ => false
        );

    assert(matches);
}


/// Position values distinguish number-only, paired and total-only shapes.
unittest
{
    const numberOnly =
        MetadataPosition.numberOnly(3);

    assert(!numberOnly.empty);
    assert(numberOnly.hasNumber);
    assert(numberOnly.number == 3);
    assert(!numberOnly.hasTotal);

    const pair =
        MetadataPosition.numberAndTotal(
            3,
            12
        );

    assert(!pair.empty);
    assert(pair.hasNumber);
    assert(pair.number == 3);
    assert(pair.hasTotal);
    assert(pair.total == 12);

    const totalOnly =
        MetadataPosition.totalOnly(12);

    assert(!totalOnly.empty);
    assert(!totalOnly.hasNumber);
    assert(totalOnly.hasTotal);
    assert(totalOnly.total == 12);
}


/// Explicit zero remains distinguishable from an absent component.
unittest
{
    const explicitZero =
        MetadataPosition.numberAndTotal(
            0,
            0
        );

    assert(explicitZero.hasNumber);
    assert(explicitZero.number == 0);
    assert(explicitZero.hasTotal);
    assert(explicitZero.total == 0);

    const absent =
        MetadataPosition.init;

    assert(absent.empty);
    assert(!absent.hasNumber);
    assert(!absent.hasTotal);
}


/// Position metadata remains a distinct MetadataValue alternative.
unittest
{
    MetadataValue value =
        MetadataPosition.numberAndTotal(
            4,
            9
        );

    const matches =
        value.match!(
            (MetadataPosition position) =>
                position.hasNumber &&
                position.number == 4 &&
                position.hasTotal &&
                position.total == 9,

            _ => false
        );

    assert(matches);
}



/// Partial date/time values preserve component presence independently.
unittest
{
    const yearOnly =
        MetadataDateTime.yearOnly(
            1999
        );

    assert(!yearOnly.empty);
    assert(yearOnly.hasDate);
    assert(!yearOnly.hasTime);
    assert(yearOnly.hasYear);
    assert(yearOnly.year == 1999);
    assert(!yearOnly.hasMonth);
    assert(!yearOnly.hasDay);
    assert(!yearOnly.hasUtcOffset);

    MetadataDateTime partial;

    partial.hasMonth = true;
    partial.month = 6;
    partial.hasDay = true;
    partial.day = 12;

    assert(!partial.empty);
    assert(partial.hasDate);
    assert(!partial.hasYear);
    assert(partial.month == 6);
    assert(partial.day == 12);
}


/// Full temporal detail can retain subsecond precision and UTC offset.
unittest
{
    auto value =
        MetadataDateTime.calendarDate(
            2026,
            9,
            10
        );

    value.hasHour = true;
    value.hour = 13;

    value.hasMinute = true;
    value.minute = 8;

    value.hasSecond = true;
    value.second = 42;

    value.hasFractionalSecond = true;
    value.fractionalSecondNanoseconds = 125_000_000;
    value.fractionalSecondDigits = 3;

    value.hasUtcOffset = true;
    value.utcOffsetMinutes = 120;

    assert(value.hasDate);
    assert(value.hasTime);
    assert(value.hasUtcOffset);
    assert(value.utcOffsetMinutes == 120);

    assert(
        value.fractionalSecondNanoseconds ==
        125_000_000
    );

    assert(value.fractionalSecondDigits == 3);
}


/// The default temporal value contains no invented date/time semantics.
unittest
{
    const value =
        MetadataDateTime.init;

    assert(value.empty);
    assert(!value.hasDate);
    assert(!value.hasTime);
    assert(!value.hasUtcOffset);
}


/// Ordered temporal lists are one distinct canonical MetadataValue family.
unittest
{
    MetadataValue value =
        MetadataDateTimeList(
            [
                MetadataDateTime.yearOnly(
                    1999
                ),
                MetadataDateTime.calendarDate(
                    2001,
                    6,
                    12
                )
            ]
        );

    const matches =
        value.match!(
            (MetadataDateTimeList list) =>
                list.values.length == 2 &&
                list.values[0].hasYear &&
                list.values[0].year == 1999 &&
                list.values[1].hasDay &&
                list.values[1].day == 12,

            _ => false
        );

    assert(matches);
}


/// URLs remain semantically distinct from ordinary text.
unittest
{
    MetadataValue value =
        MetadataUrl("https://example.invalid/item");

    const isUrl =
        value.match!(
            (MetadataUrl url) =>
                url.value ==
                "https://example.invalid/item",
            _ => false
        );

    assert(isUrl);
}


/// Canonical binary data is copied away from mutable source storage.
unittest
{
    ubyte[] source =
        [0x01, 0x02, 0x03];

    auto binary =
        MetadataBinary.copyFrom(
            source,
            "application/octet-stream"
        );

    assert(binary.length == 3);
    assert(!binary.empty);

    assert(
        binary.data ==
        [0x01, 0x02, 0x03]
    );

    assert(
        binary.mediaType ==
        "application/octet-stream"
    );

    source[0] = 0xFF;

    assert(binary.data[0] == 0x01);
}


/// Empty binary metadata is a valid owned value.
unittest
{
    const ubyte[] source = [];

    auto binary =
        MetadataBinary.copyFrom(source);

    assert(binary.empty);
    assert(binary.length == 0);
    assert(binary.mediaType.length == 0);
}


/// Pictures may contain embedded binary image data.
unittest
{
    auto binary =
        MetadataBinary.copyFrom(
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8,
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD9
            ],
            "image/jpeg"
        );

    MetadataPictureSource source =
        binary;

    MetadataValue value =
        MetadataPicture(
            "Front cover",
            source
        );

    const matches =
        value.match!(
            (MetadataPicture picture) =>
                picture.description == "Front cover" &&
                picture.source.match!(
                    (MetadataBinary data) =>
                        data.mediaType == "image/jpeg" &&
                        data.length == 4,
                    _ => false
                ),
            _ => false
        );

    assert(matches);
}


/// Pictures may alternatively refer to an external image URL.
unittest
{
    MetadataPictureSource source =
        MetadataUrl(
            "https://example.invalid/cover.jpg"
        );

    MetadataValue value =
        MetadataPicture(
            "",
            source
        );

    const matches =
        value.match!(
            (MetadataPicture picture) =>
                picture.source.match!(
                    (MetadataUrl url) =>
                        url.value ==
                        "https://example.invalid/cover.jpg",
                    _ => false
                ),
            _ => false
        );

    assert(matches);
}
