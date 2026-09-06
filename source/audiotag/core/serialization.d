/++
Structured low-level serialization results.

Parsing errors and serialization errors are deliberately separate.

`ParseError` describes failures while consuming untrusted source bytes
and therefore carries absolute source-offset semantics.

`SerializationError` describes values that cannot be represented in an
output binary format. Its optional `index` identifies a destination or
field-relative byte position when meaningful; it is not a source
offset.
+/
module audiotag.core.serialization;


/++
Identifies a low-level binary serialization failure.
+/
enum SerializationErrorCode : ubyte
{
    /// A supplied value is outside the representable numeric domain.
    valueOutOfRange,

    /// A required structural identifier contains an invalid value.
    invalidValue,

    /// A length is invalid for the target structure.
    invalidLength,

    /// Reserved or otherwise invalid output flags were requested.
    invalidFlags,

    /// Related output fields contradict each other.
    inconsistentStructure,

    /// The value is valid canonically but unsupported by this serializer.
    unsupportedRepresentation
}


/++
Compact context for one low-level serialization failure.

`index` is relative to the structure being serialized when meaningful.
It is not an input/source offset.

`value` and `limit` provide numeric context where useful and otherwise
remain zero.
+/
struct SerializationError
{
    /// Kind of serialization failure.
    SerializationErrorCode code;

    /// Relative byte/field position associated with the failure.
    size_t index;

    /// Rejected numeric value when meaningful.
    ulong value;

    /// Maximum or other relevant numeric boundary when meaningful.
    ulong limit;

    /++
    Constructs one structured serialization error.
    +/
    this(
        SerializationErrorCode code,
        size_t index = 0,
        ulong value = 0,
        ulong limit = 0
    )
        @safe pure nothrow @nogc
    {
        this.code = code;
        this.index = index;
        this.value = value;
        this.limit = limit;
    }
}


/++
Value-or-error result for binary serialization primitives.

This mirrors the explicit-success/failure style of the parser core
without reusing parser-specific error semantics.
+/
struct SerializationResult(T)
{
    private bool _hasValue;
    private T _value;
    private SerializationError _error;

    /++
    Constructs a successful serialization result.
    +/
    static SerializationResult success(T value)
        @safe pure nothrow @nogc
    {
        SerializationResult result;
        result._hasValue = true;
        result._value = value;
        return result;
    }

    /++
    Constructs a failed serialization result.
    +/
    static SerializationResult failure(
        SerializationError error
    )
        @safe pure nothrow @nogc
    {
        SerializationResult result;
        result._hasValue = false;
        result._error = error;
        return result;
    }

    /// Whether a serialized value is present.
    @property
    bool hasValue() const
        @safe pure nothrow @nogc
    {
        return _hasValue;
    }

    /// Whether serialization failed.
    @property
    bool hasError() const
        @safe pure nothrow @nogc
    {
        return !_hasValue;
    }

    /++
    Returns the serialized value.

    Preconditions:
        `hasValue` must be true.
    +/
    @property
    ref const(T) value() const
        @safe pure nothrow @nogc return
    {
        assert(_hasValue);
        return _value;
    }

    /++
    Returns the serialization error.

    Preconditions:
        `hasError` must be true.
    +/
    @property
    ref const(SerializationError) error() const
        @safe pure nothrow @nogc return
    {
        assert(!_hasValue);
        return _error;
    }
}


/// Successful results expose only their value state.
unittest
{
    const result =
        SerializationResult!uint.success(
            42
        );

    assert(result.hasValue);
    assert(!result.hasError);
    assert(result.value == 42);
}


/// Failed results preserve structured serialization context.
unittest
{
    const expected =
        SerializationError(
            SerializationErrorCode
                .valueOutOfRange,
            4,
            0x1000_0000,
            0x0FFF_FFFF
        );

    const result =
        SerializationResult!uint.failure(
            expected
        );

    assert(!result.hasValue);
    assert(result.hasError);

    assert(
        result.error.code ==
        SerializationErrorCode
            .valueOutOfRange
    );

    assert(result.error.index == 4);
    assert(result.error.value == 0x1000_0000);
    assert(result.error.limit == 0x0FFF_FFFF);
}
