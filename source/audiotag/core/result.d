/++
Result values for fallible low-level parsing operations.

`ParseResult` represents either a successfully parsed value or a
structured `ParseError`.

The type performs no allocation and does not use exceptions for
malformed external input.
+/
module audiotag.core.result;

import audiotag.core.error : ParseError, ParseErrorCode;


/++
Represents either a successful parsing value or a `ParseError`.

A result must be constructed explicitly through `success` or
`failure`. Default construction is disabled so that an uninitialized
result cannot be mistaken for a real parsing outcome.

Params:
    T = Type returned on successful parsing.
+/
struct ParseResult(T)
{
    @disable this();

    private bool _hasValue;
    private T _value;
    private ParseError _error;

    private this(
        bool hasValue,
        T value,
        ParseError error
    )
        @safe pure nothrow @nogc
    {
        _hasValue = hasValue;
        _value = value;
        _error = error;
    }

    /++
    Constructs a successful parse result.

    Params:
        value = Successfully parsed value.

    Returns:
        A result containing `value`.
    +/
    static ParseResult success(T value)
        @safe pure nothrow @nogc
    {
        return ParseResult(
            true,
            value,
            ParseError.init
        );
    }

    /++
    Constructs a failed parse result.

    Params:
        error = Structured parsing failure.

    Returns:
        A result containing `error`.
    +/
    static ParseResult failure(ParseError error)
        @safe pure nothrow @nogc
    {
        return ParseResult(
            false,
            T.init,
            error
        );
    }

    /++
    Returns whether this result contains a successful value.
    +/
    @property
    bool hasValue() const
        @safe pure nothrow @nogc
    {
        return _hasValue;
    }

    /++
    Returns whether this result contains a parse error.
    +/
    @property
    bool hasError() const
        @safe pure nothrow @nogc
    {
        return !_hasValue;
    }

    /++
    Returns the successful value.

    Preconditions:
        `hasValue` must be true.

    Note:
        Accessing the wrong alternative is a programmer error and is
        therefore protected by an assertion.
    +/
    @property
    T value()
        @safe pure nothrow @nogc
    {
        assert(_hasValue);

        return _value;
    }

    /++
    Returns the parse error.

    Preconditions:
        `hasError` must be true.

    Note:
        Accessing the wrong alternative is a programmer error and is
        therefore protected by an assertion.
    +/
    @property
    ParseError error()
        @safe pure nothrow @nogc
    {
        assert(!_hasValue);

        return _error;
    }
}


/// Successful results expose only the successful alternative.
unittest
{
    auto result = ParseResult!size_t.success(42);

    assert(result.hasValue);
    assert(!result.hasError);
    assert(result.value == 42);
}


/// Failed results preserve the structured parse error.
unittest
{
    const expected = ParseError(
        ParseErrorCode.endOfSpan,
        104,
        10,
        4
    );

    auto result = ParseResult!size_t.failure(expected);

    assert(!result.hasValue);
    assert(result.hasError);

    const actual = result.error;

    assert(actual.code == expected.code);
    assert(actual.offset == expected.offset);
    assert(actual.requested == expected.requested);
    assert(actual.available == expected.available);
}


/// ParseResult cannot be default-constructed accidentally.
unittest
{
    static assert(
        !__traits(compiles, ParseResult!size_t())
    );
}


/++
Represents success or a structured `ParseError` for parsing operations
that do not return a value.

A status must be constructed explicitly through `success` or
`failure`. Default construction is disabled.
+/
struct ParseStatus
{
    @disable this();

    private bool _hasError;
    private ParseError _error;

    private this(bool hasError, ParseError error)
        @safe pure nothrow @nogc
    {
        _hasError = hasError;
        _error = error;
    }

    /++
    Constructs a successful parse status.

    Returns:
        A status representing successful completion.
    +/
    static ParseStatus success()
        @safe pure nothrow @nogc
    {
        return ParseStatus(
            false,
            ParseError.init
        );
    }

    /++
    Constructs a failed parse status.

    Params:
        error = Structured parsing failure.

    Returns:
        A status containing `error`.
    +/
    static ParseStatus failure(ParseError error)
        @safe pure nothrow @nogc
    {
        return ParseStatus(
            true,
            error
        );
    }

    /++
    Returns whether the operation completed successfully.
    +/
    @property
    bool succeeded() const
        @safe pure nothrow @nogc
    {
        return !_hasError;
    }

    /++
    Returns whether this status contains a parse error.
    +/
    @property
    bool hasError() const
        @safe pure nothrow @nogc
    {
        return _hasError;
    }

    /++
    Returns the parse error.

    Preconditions:
        `hasError` must be true.

    Note:
        Accessing the error of a successful status is a programmer
        error and is therefore protected by an assertion.
    +/
    @property
    ParseError error()
        @safe pure nothrow @nogc
    {
        assert(_hasError);

        return _error;
    }
}


/// Successful statuses contain no parse error.
unittest
{
    auto status = ParseStatus.success();

    assert(status.succeeded);
    assert(!status.hasError);
}


/// Failed statuses preserve the structured parse error.
unittest
{
    const expected = ParseError(
        ParseErrorCode.endOfSpan,
        104,
        10,
        4
    );

    auto status = ParseStatus.failure(expected);

    assert(!status.succeeded);
    assert(status.hasError);

    const actual = status.error;

    assert(actual.code == expected.code);
    assert(actual.offset == expected.offset);
    assert(actual.requested == expected.requested);
    assert(actual.available == expected.available);
}


/// ParseStatus cannot be default-constructed accidentally.
unittest
{
    static assert(
        !__traits(compiles, ParseStatus())
    );
}
