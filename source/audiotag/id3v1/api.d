/++
High-level consumer API for same-version ID3v1 editing and serialization.

A caller supplies one canonically parsed ID3v1 tag and one canonical edit
overlay. This module performs semantic write planning internally and, when the
plan is losslessly writable, serializes the resulting exact 128-byte ID3v1
block.

Detailed planning diagnostics remain available through
`audiotag.id3v1.write_plan` for advanced callers. This high-level API maps
planning failures into the existing `SerializationError` domain.

No MP3/container placement or file I/O is performed here.
+/
module audiotag.id3v1.api;

import audiotag.core.serialization :
    SerializationError,
    SerializationErrorCode,
    SerializationResult;

import audiotag.id3v1.canonical :
    Id3v1CanonicalTag;

import audiotag.id3v1.tag_write :
    serializeId3v1NativeTag;

import audiotag.id3v1.write_plan :
    Id3v1CanonicalTagWritePlan,
    Id3v1CanonicalTagWriteStatus,
    planId3v1CanonicalTagWrite;

import audiotag.metadata.edit :
    MetadataTreeEdit;


/++
Maps a detailed ID3v1 planning failure into the common serialization domain.

Advanced callers that need the exact planning reason should call
`planId3v1CanonicalTagWrite` directly.
+/
private SerializationError
serializationErrorForPlan(
    const(Id3v1CanonicalTagWritePlan) plan
)
    @safe pure nothrow @nogc
{
    assert(!plan.writable);

    final switch (plan.status)
    {
        case Id3v1CanonicalTagWriteStatus.unrepresentableField:
            return plan.error;

        case Id3v1CanonicalTagWriteStatus.multiplicityExceeded:
            return
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    0,
                    cast(ulong)
                        plan.multiplicity.count,
                    1
                );

        case Id3v1CanonicalTagWriteStatus.slotConflict:
            return
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    plan.fieldIndex,
                    cast(ulong)
                        plan.conflictTarget,
                    1
                );

        case Id3v1CanonicalTagWriteStatus.inconsistentProjection:
            return
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure,
                    plan.fieldIndex
                );

        case Id3v1CanonicalTagWriteStatus.nativeTransitionWouldDiscardData:
            return
                SerializationError(
                    SerializationErrorCode
                        .unsupportedRepresentation,
                    125
                );

        case Id3v1CanonicalTagWriteStatus.ready:
            /*
             * `writable` can only be false for ready when the embedded
             * multiplicity result is invalid. The planner currently promotes
             * that condition to `multiplicityExceeded`, so reaching here is
             * defensive only.
             */
            return
                SerializationError(
                    SerializationErrorCode
                        .inconsistentStructure
                );
    }

    assert(false);
}


/++
Serializes one canonically parsed ID3v1 tag after applying a canonical edit.

Semantic planning is performed internally. Unchanged source-native bytes are
preserved according to `planId3v1CanonicalTagWrite`, including native-only
year/genre data that had no canonical projection.

Params:
    tag = Parsed native-plus-canonical ID3v1 source tag.
    edit = Canonical edit overlay associated with `tag.metadata`.

Returns:
    Complete owned 128-byte ID3v1 tag bytes or a structured serialization
    failure.
+/
SerializationResult!(ubyte[])
serializeId3v1Tag(
    const(Id3v1CanonicalTag) tag,
    const(MetadataTreeEdit) edit
)
    @safe
{
    const plan =
        planId3v1CanonicalTagWrite(
            tag,
            edit
        );

    if (!plan.writable)
    {
        return
            SerializationResult!(ubyte[])
                .failure(
                    serializationErrorForPlan(
                        plan
                    )
                );
    }

    return
        serializeId3v1NativeTag(
            plan.nativeFields
        );
}


version (unittest)
{
    import audiotag.core.span :
        ByteSpan;

    import audiotag.id3v1.canonical :
        parseId3v1CanonicalTag;

    import audiotag.metadata.field :
        MetadataField,
        MetadataKey;

    import audiotag.metadata.value :
        MetadataDateTime,
        MetadataDateTimeList,
        MetadataPosition,
        MetadataText,
        MetadataValue;


    private void
    setSignature(
        ref ubyte[128] bytes
    )
        @safe pure nothrow @nogc
    {
        bytes[0] = 'T';
        bytes[1] = 'A';
        bytes[2] = 'G';

        bytes[127] = 255;
    }


    private MetadataField
    textField(
        string key,
        string text
    )
        @safe
    {
        MetadataValue value =
            MetadataText(text);

        return
            MetadataField(
                MetadataKey(key),
                value
            );
    }


    private MetadataField
    trackField(
        ulong number
    )
        @safe
    {
        MetadataValue value =
            MetadataPosition.numberOnly(
                number
            );

        return
            MetadataField(
                MetadataKey("track"),
                value
            );
    }
}


/// A no-op edit roundtrips the complete 128-byte source, including native-only data.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'T';

    bytes[93] = '2';
    bytes[94] = '0';
    bytes[95] = 'X';
    bytes[96] = '6';

    bytes[127] = 250;

    auto parsed =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value.metadata
        );

    auto written =
        serializeId3v1Tag(
            parsed.value,
            edit
        );

    assert(written.hasValue);
    assert(written.value == bytes[]);
}


/// Editing one canonical field preserves unrelated native-only year and genre bytes.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[3] = 'A';

    bytes[93] = 'X';
    bytes[94] = 'X';
    bytes[95] = 'X';
    bytes[96] = 'X';

    bytes[127] = 250;

    auto parsed =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);
    assert(parsed.value.metadata.length == 1);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value.metadata
        );

    edit.replaceSourceField(
        0,
        textField(
            "title",
            "B"
        )
    );

    auto written =
        serializeId3v1Tag(
            parsed.value,
            edit
        );

    assert(written.hasValue);
    assert(written.value.length == 128);

    assert(written.value[3] == 'B');
    assert(written.value[4] == 0);

    assert(
        written.value[93 .. 97] ==
        bytes[93 .. 97]
    );

    assert(written.value[127] == 250);
}


/// Adding a track upgrades a compatible v1.0 tag to v1.1.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    bytes[97] = 'C';
    bytes[125] = 0;
    bytes[126] = 0;

    auto parsed =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value.metadata
        );

    edit.appendNewField(
        trackField(7)
    );

    auto written =
        serializeId3v1Tag(
            parsed.value,
            edit
        );

    assert(written.hasValue);

    assert(written.value[97] == 'C');
    assert(written.value[125] == 0);
    assert(written.value[126] == 7);

    auto reparsed =
        parseId3v1CanonicalTag(
            ByteSpan(
                written.value
            )
        );

    assert(reparsed.hasValue);
    assert(reparsed.value.native.hasTrack);
    assert(reparsed.value.native.track == 7);
}


/// A physical slot collision becomes an ordinary structured serialization failure.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);
    bytes[97] = 'A';

    auto parsed =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value.metadata
        );

    edit.appendNewField(
        textField(
            "comment",
            "B"
        )
    );

    auto written =
        serializeId3v1Tag(
            parsed.value,
            edit
        );

    assert(written.hasError);

    assert(
        written.error.code ==
        SerializationErrorCode
            .inconsistentStructure
    );
}


/// Canonical date precision that ID3v1 cannot represent is rejected end-to-end.
unittest
{
    ubyte[128] bytes;

    setSignature(bytes);

    auto parsed =
        parseId3v1CanonicalTag(
            ByteSpan(bytes[])
        );

    assert(parsed.hasValue);

    auto edit =
        MetadataTreeEdit.forSource(
            parsed.value.metadata
        );

    MetadataValue value =
        MetadataDateTimeList(
            [
                MetadataDateTime.calendarDate(
                    2001,
                    6,
                    12
                )
            ]
        );

    edit.appendNewField(
        MetadataField(
            MetadataKey("releaseDate"),
            value
        )
    );

    auto written =
        serializeId3v1Tag(
            parsed.value,
            edit
        );

    assert(written.hasError);

    assert(
        written.error.code ==
        SerializationErrorCode
            .unsupportedRepresentation
    );
}
