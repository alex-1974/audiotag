/++
Shared semantic decoding for ID3v2 content-type (`TCON`) values.

ID3v2.3 and ID3v2.4 use different native encodings for legacy numeric genre
references. The canonical metadata layer should not duplicate those rules, so
this module resolves them into an ordered list of genre strings while leaving
the original native frame untouched.

ID3v2.3 supports parenthesized references such as `(17)`, multiple references
such as `(51)(39)`, the `RX`/`CR` keywords in the same parenthesized form, and
an optional free-text refinement. A doubled opening parenthesis escapes a
refinement that begins with `(`.

ID3v2.4 uses separate text values and represents ID3v1 references as plain
numeric strings, e.g. `21`, while retaining `RX` and `CR` as keywords.

For broad interoperability, ID3v2.3 also accepts a complete plain decimal value
as a numeric genre reference, and ID3v2.4 accepts legacy parenthesized v2.3
syntax. Unknown explicit numeric/reference tokens are reported as
unrepresentable rather than converted into invented genre names.

Free text is preserved exactly and list order is retained. No trimming,
case-folding, deduplication or separator heuristics are applied here.
+/
module audiotag.id3v2.common.genre;

import audiotag.id3.genre :
    findId3GenreByCode;


/++ Result of decoding native ID3v2 genre semantics. +/
struct Id3v2GenreDecodeResult
{
    /// Whether every explicit native reference could be represented.
    bool representable;

    /// Ordered canonical genre strings when `representable` is true.
    string[] values;

    private static Id3v2GenreDecodeResult success(
        string[] values
    )
        @safe
    {
        return
            Id3v2GenreDecodeResult(
                true,
                values
            );
    }

    private static Id3v2GenreDecodeResult unrepresentable()
        @safe
    {
        return
            Id3v2GenreDecodeResult(
                false,
                []
            );
    }
}


/++
Decodes one ID3v2.3 `TCON` information string.

Recognized forms include:

    Rock
    17
    (17)
    (51)(39)
    (4)Eurodisco
    (RX)
    (CR)
    ((Custom starting with parenthesis)
    (55)((Refinement starting with parenthesis)

An explicit parenthesized or complete decimal numeric reference must resolve
through the shared ID3 genre registry. Otherwise the result is
unrepresentable.
+/
Id3v2GenreDecodeResult
decodeId3v23Genre(
    string value
)
    @safe
{
    if (value.length == 0)
    {
        return
            Id3v2GenreDecodeResult
                .success(
                    [""]
                );
    }

    if (value[0] != '(')
    {
        if (isDecimal(value))
            return decodeNumericGenre(value);

        return
            Id3v2GenreDecodeResult
                .success(
                    [value]
                );
    }

    string[] values;
    size_t offset;

    while (
        offset < value.length &&
        value[offset] == '('
    )
    {
        /*
         * "((" escapes a free-text refinement whose first character is
         * "(". Drop exactly one of the two opening parentheses.
         */
        if (
            offset + 1 < value.length &&
            value[offset + 1] == '('
        )
        {
            values ~=
                value[
                    offset + 1 ..
                    value.length
                ];

            return
                Id3v2GenreDecodeResult
                    .success(
                        values
                    );
        }

        size_t closing =
            offset + 1;

        while (
            closing < value.length &&
            value[closing] != ')'
        )
        {
            ++closing;
        }

        if (closing == value.length)
        {
            return
                Id3v2GenreDecodeResult
                    .unrepresentable();
        }

        const token =
            value[
                offset + 1 ..
                closing
            ];

        const reference =
            decodeReferenceToken(
                token
            );

        if (!reference.representable)
        {
            return
                Id3v2GenreDecodeResult
                    .unrepresentable();
        }

        values ~=
            reference.values;

        offset =
            closing + 1;
    }

    if (offset < value.length)
    {
        values ~=
            value[
                offset ..
                value.length
            ];
    }

    return
        Id3v2GenreDecodeResult
            .success(
                values
            );
}


/++
Decodes the ordered native value list of an ID3v2.4 `TCON` frame.

Each value is interpreted independently. Plain decimal values resolve through
the shared ID3 genre registry, `RX` and `CR` map to their defined content
types, and all other values remain free text.

Legacy parenthesized ID3v2.3 syntax is also accepted for interoperability and
may therefore expand one native value into multiple canonical genre strings.
+/
Id3v2GenreDecodeResult
decodeId3v24Genres(
    string[] nativeValues
)
    @safe
{
    string[] values;

    foreach (value; nativeValues)
    {
        Id3v2GenreDecodeResult decoded;

        if (
            value.length > 0 &&
            value[0] == '('
        )
        {
            decoded =
                decodeId3v23Genre(
                    value
                );
        }
        else if (
            value == "RX" ||
            value == "CR"
        )
        {
            decoded =
                decodeReferenceToken(
                    value
                );
        }
        else if (isDecimal(value))
        {
            decoded =
                decodeNumericGenre(
                    value
                );
        }
        else
        {
            decoded =
                Id3v2GenreDecodeResult
                    .success(
                        [value]
                    );
        }

        if (!decoded.representable)
        {
            return
                Id3v2GenreDecodeResult
                    .unrepresentable();
        }

        values ~=
            decoded.values;
    }

    return
        Id3v2GenreDecodeResult
            .success(
                values
            );
}


private Id3v2GenreDecodeResult
decodeReferenceToken(
    string token
)
    @safe
{
    if (token == "RX")
    {
        return
            Id3v2GenreDecodeResult
                .success(
                    ["Remix"]
                );
    }

    if (token == "CR")
    {
        return
            Id3v2GenreDecodeResult
                .success(
                    ["Cover"]
                );
    }

    if (!isDecimal(token))
    {
        return
            Id3v2GenreDecodeResult
                .unrepresentable();
    }

    return
        decodeNumericGenre(
            token
        );
}


private Id3v2GenreDecodeResult
decodeNumericGenre(
    string digits
)
    @safe
{
    uint code;

    foreach (character; digits)
    {
        const digit =
            cast(uint)
                (character - '0');

        if (
            code >
            (uint.max - digit) / 10
        )
        {
            return
                Id3v2GenreDecodeResult
                    .unrepresentable();
        }

        code =
            code * 10 +
            digit;
    }

    if (code > ubyte.max)
    {
        return
            Id3v2GenreDecodeResult
                .unrepresentable();
    }

    const genre =
        findId3GenreByCode(
            cast(ubyte)
                code
        );

    if (!genre.found)
    {
        return
            Id3v2GenreDecodeResult
                .unrepresentable();
    }

    return
        Id3v2GenreDecodeResult
            .success(
                [genre.name]
            );
}


private bool
isDecimal(
    string value
)
    @safe pure nothrow @nogc
{
    if (value.length == 0)
        return false;

    foreach (character; value)
    {
        if (
            character < '0' ||
            character > '9'
        )
        {
            return false;
        }
    }

    return true;
}


/// ID3v2.3 free text remains one exact genre string.
unittest
{
    const result =
        decodeId3v23Genre(
            "Eurodisco"
        );

    assert(result.representable);
    assert(result.values == ["Eurodisco"]);
}


/// ID3v2.3 resolves numeric references, keywords and ordered references.
unittest
{
    const numeric =
        decodeId3v23Genre(
            "(17)"
        );

    assert(numeric.representable);
    assert(numeric.values == ["Rock"]);

    const several =
        decodeId3v23Genre(
            "(51)(39)"
        );

    assert(several.representable);
    assert(
        several.values ==
        [
            "Techno-Industrial",
            "Noise"
        ]
    );

    const keywords =
        decodeId3v23Genre(
            "(RX)(CR)"
        );

    assert(keywords.representable);
    assert(
        keywords.values ==
        [
            "Remix",
            "Cover"
        ]
    );
}


/// ID3v2.3 refinement text follows resolved legacy references.
unittest
{
    const result =
        decodeId3v23Genre(
            "(4)Eurodisco"
        );

    assert(result.representable);
    assert(
        result.values ==
        [
            "Disco",
            "Eurodisco"
        ]
    );
}


/// Doubled opening parentheses retain a literal refinement parenthesis.
unittest
{
    const onlyText =
        decodeId3v23Genre(
            "((Custom)"
        );

    assert(onlyText.representable);
    assert(onlyText.values == ["(Custom)"]);

    const afterReference =
        decodeId3v23Genre(
            "(55)((I think...)"
        );

    assert(afterReference.representable);
    assert(
        afterReference.values ==
        [
            "Dream",
            "(I think...)"
        ]
    );
}


/// Plain numeric v2.3 values are accepted as a compatibility form.
unittest
{
    const result =
        decodeId3v23Genre(
            "191"
        );

    assert(result.representable);
    assert(result.values == ["Psybient"]);
}


/// Unknown or malformed explicit v2.3 references are not invented.
unittest
{
    foreach (
        value;
        [
            "(192)",
            "(255)",
            "(999)",
            "()",
            "(NOPE)",
            "(17"
        ]
    )
    {
        const result =
            decodeId3v23Genre(
                value
            );

        assert(!result.representable);
    }
}


/// ID3v2.4 preserves free text while resolving numeric values and keywords.
unittest
{
    const result =
        decodeId3v24Genres(
            [
                "17",
                "Ambient",
                "RX",
                "CR"
            ]
        );

    assert(result.representable);

    assert(
        result.values ==
        [
            "Rock",
            "Ambient",
            "Remix",
            "Cover"
        ]
    );
}


/// ID3v2.4 also accepts legacy parenthesized values for interoperability.
unittest
{
    const result =
        decodeId3v24Genres(
            [
                "(26)",
                "(4)Eurodisco"
            ]
        );

    assert(result.representable);

    assert(
        result.values ==
        [
            "Ambient",
            "Disco",
            "Eurodisco"
        ]
    );
}


/// Unknown explicit v2.4 numeric references remain unrepresentable.
unittest
{
    foreach (
        value;
        [
            "192",
            "255",
            "999999999999999999999999999999"
        ]
    )
    {
        const result =
            decodeId3v24Genres(
                [value]
            );

        assert(!result.representable);
    }
}
