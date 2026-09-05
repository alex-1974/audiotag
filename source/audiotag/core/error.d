/++
Structured low-level parse errors used by audiotag parsers.

Malformed or truncated external input is reported through `ParseError`
rather than through assertions or contracts.

The low-level error representation contains only compact numeric
context and does not allocate. Higher parser layers may translate
these errors into richer human-readable diagnostics.
+/
module audiotag.core.error;


/++
Identifies a low-level binary parsing failure.
+/
enum ParseErrorCode : ubyte
{
    /// An exact read or skip would exceed the current bounded span.
    endOfSpan,

    /// A required byte pattern was not found within the allowed region.
    patternNotFound,

    /// A length value is invalid for the surrounding structure.
    invalidLength,

    /// An integer operation or decoded size would overflow.
    integerOverflow,

    /// A byte in a synchsafe integer has its most significant bit set.
    invalidSynchsafeInteger,

    /// An encoding marker or discriminator is not valid.
    invalidEncodingMarker
}


/++
Compact context for a low-level parsing failure.

`offset` is the absolute source offset at which the failed operation
was attempted.

`requested` and `available` provide size context where meaningful.
They are zero when the corresponding values do not apply to a
particular error.

This type is allocation-free and suitable for the parser core.
+/
struct ParseError
{
    /// Kind of parsing failure.
    ParseErrorCode code;

    /// Absolute source offset associated with the failure.
    size_t offset;

    /// Number of bytes or elements requested, when applicable.
    size_t requested;

    /// Number of bytes or elements available, when applicable.
    size_t available;

    /++
    Constructs a structured parse error.

    Params:
        code = Kind of parsing failure.
        offset = Absolute source offset associated with the failure.
        requested = Requested size or count, if applicable.
        available = Available size or count, if applicable.
    +/
    this(
        ParseErrorCode code,
        size_t offset,
        size_t requested = 0,
        size_t available = 0
    )
        @safe pure nothrow @nogc
    {
        this.code = code;
        this.offset = offset;
        this.requested = requested;
        this.available = available;
    }
}


/// ParseError preserves complete bounded-read failure context.
unittest
{
    const error = ParseError(
        ParseErrorCode.endOfSpan,
        104,
        10,
        4
    );

    assert(error.code == ParseErrorCode.endOfSpan);
    assert(error.offset == 104);
    assert(error.requested == 10);
    assert(error.available == 4);
}


/// Optional numeric context defaults to zero.
unittest
{
    const error = ParseError(
        ParseErrorCode.patternNotFound,
        512
    );

    assert(error.code == ParseErrorCode.patternNotFound);
    assert(error.offset == 512);
    assert(error.requested == 0);
    assert(error.available == 0);
}
