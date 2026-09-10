/++
Planning of one newly introduced canonical field as an ID3v2.4 frame.

The reverse target registry identifies the deterministic native frame
family for a canonical semantic key. This module adds field-level
representability checks before serialization begins.

The planner verifies:

- a canonical ID3v2.4 target exists;
- the canonical value has the expected value family;
- no canonical context would be silently discarded;
- required native context is present;
- simple native constraints already known at planning time are met.

No bytes are emitted here.
+/
module audiotag.id3v2.v24.new_frame_plan;

import std.sumtype :
    match;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

import audiotag.metadata.registry :
    MetadataValueKind;

import audiotag.metadata.value :
    MetadataBinary,
    MetadataDateTimeList,
    MetadataInteger,
    MetadataPicture,
    MetadataPosition,
    MetadataText,
    MetadataTextList,
    MetadataUrl;

import audiotag.id3v2.v24.text_information_write :
    measureId3v24Utf8TextInformationPayload;

import audiotag.id3v2.v24.user_text_write :
    measureId3v24Utf8UserTextPayload;

import audiotag.id3v2.v24.user_url_write :
    measureId3v24Utf8UserUrlPayload;

import audiotag.id3v2.v24.url_link_write :
    measureId3v24UrlLinkPayload;

import audiotag.id3v2.v24.attached_picture :
    Id3v24PictureType;

import audiotag.id3v2.v24.canonical_target :
    Id3v24CanonicalTargetDefinition,
    Id3v24CanonicalTargetFamily,
    findId3v24CanonicalTarget;


/++
Planning outcome for one new canonical field.

Only `ready` may proceed to a future serializer.
+/
enum Id3v24CanonicalFieldPlanStatus : ubyte
{
    /// A deterministic, lossless native target is currently available.
    ready,

    /// No ID3v2.4 reverse target exists for the canonical semantic key.
    unsupportedCanonicalKey,

    /// The field's value family disagrees with its canonical target.
    invalidValueKind,

    /// Native information required for lossless encoding is absent.
    missingRequiredContext,

    /// Canonical context is present that the native target cannot retain.
    unsupportedContext,

    /// Required context exists but violates a known native constraint.
    nativeConstraintViolation
}


/++
Compatibility name for the status used by new-frame planning.

The status is fundamentally a property of one canonical field, not of
whether that field is new or replaces source-derived metadata.
+/
alias Id3v24NewFramePlanStatus =
    Id3v24CanonicalFieldPlanStatus;


/++
Representability plan for one canonical field targeting ID3v2.4.

This type is independent of whether the field is newly inserted or is a
replacement for source-derived canonical metadata.
+/
struct Id3v24CanonicalFieldPlan
{
    /// Planning outcome.
    Id3v24CanonicalFieldPlanStatus status;

    /// Deterministic native target when one was found.
    Id3v24CanonicalTargetDefinition target;

    /++
    Returns whether the field may proceed to ID3v2.4 serialization.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return status ==
            Id3v24CanonicalFieldPlanStatus.ready;
    }
}


/++
Write plan for one newly introduced canonical field.

`newFieldIndex` refers to its position in `MetadataTreeEdit.newFields`.
The field itself is deliberately not copied into the plan.
+/
struct Id3v24NewFramePlan
{
    /// Index in the canonical edit overlay's new-field sequence.
    size_t newFieldIndex;

    /// Planning outcome.
    Id3v24CanonicalFieldPlanStatus status;

    /// Native target when one was found.
    Id3v24CanonicalTargetDefinition target;

    /++
    Returns whether this new field may proceed to serialization.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return status ==
            Id3v24NewFramePlanStatus.ready;
    }
}


private MetadataValueKind
valueKindOf(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) value) =>
            MetadataValueKind.text,

        (const(MetadataTextList) value) =>
            MetadataValueKind.textList,

        (const(MetadataInteger) value) =>
            MetadataValueKind.integer,

        (const(MetadataUrl) value) =>
            MetadataValueKind.url,

        (const(MetadataBinary) value) =>
            MetadataValueKind.binary,

        (const(MetadataPicture) value) =>
            MetadataValueKind.picture,

        (const(MetadataPosition) value) =>
            MetadataValueKind.position,

        (const(MetadataDateTimeList) value) =>
            MetadataValueKind.dateTimeList
    );
}


private bool
textInformationPayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text)
        {
            const(string)[] values =
                [text.value];

            auto measured =
                measureId3v24Utf8TextInformationPayload(
                    values
                );

            return measured.hasValue;
        },

        (const(MetadataTextList) list)
        {
            auto measured =
                measureId3v24Utf8TextInformationPayload(
                    list.values
                );

            return measured.hasValue;
        },

        _ => false
    );
}



private bool
userTextPayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataText) text)
        {
            auto measured =
                measureId3v24Utf8UserTextPayload(
                    field.description,
                    text.value
                );

            return measured.hasValue;
        },

        _ => false
    );
}


private bool
userUrlPayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataUrl) url)
        {
            auto measured =
                measureId3v24Utf8UserUrlPayload(
                    field.description,
                    url.value
                );

            return measured.hasValue;
        },

        _ => false
    );
}


private bool
urlLinkPayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataUrl) url)
        {
            auto measured =
                measureId3v24UrlLinkPayload(
                    url.value
                );

            return measured.hasValue;
        },

        _ => false
    );
}


private size_t
qualifierCount(
    ref const(MetadataField) field,
    string name
)
    @safe pure nothrow @nogc
{
    size_t result;

    foreach (const qualifier; field.qualifiers)
    {
        if (qualifier.name == name)
            ++result;
    }

    return result;
}


private bool
hasOnlyQualifier(
    ref const(MetadataField) field,
    string name
)
    @safe pure nothrow @nogc
{
    return
        field.qualifiers.length == 1 &&
        qualifierCount(field, name) == 1;
}


private bool
hasNoAdditionalContext(
    ref const(MetadataField) field
)
    @safe pure nothrow @nogc
{
    return
        !field.hasLanguage &&
        !field.hasDescription &&
        !field.hasQualifiers;
}


private bool
languageTextPayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    import audiotag.id3v2.v24.language_text_write :
        measureId3v24Utf8LanguageTextPayload;

    if (!field.hasLanguage)
        return false;

    return field.value.match!(
        (const(MetadataText) text)
        {
            auto measured =
                measureId3v24Utf8LanguageTextPayload(
                    field.language.tag,
                    field.description,
                    text.value
                );

            return measured.hasValue;
        },

        _ => false
    );
}


private bool
languageIsNativeThreeByteCode(
    ref const(MetadataField) field
)
    @safe pure nothrow @nogc
{
    if (!field.hasLanguage)
        return false;

    const tag =
        field.language.tag;

    if (tag.length != 3)
        return false;

    foreach (ubyte value; tag)
    {
        if (value > 0x7F)
            return false;
    }

    return true;
}


private bool
artworkSourceHasRequiredContext(
    ref const(MetadataField) field
)
    @safe
{
    return field.value.match!(
        (const(MetadataPicture) picture) =>
            picture.source.match!(
                (const(MetadataBinary) binary) =>
                    binary.mediaType.length != 0,

                (const(MetadataUrl) url) =>
                    true
            ),

        _ => false
    );
}


private bool
artworkPayloadRepresentable(
    ref const(MetadataField) field,
    Id3v24PictureType pictureType
)
    @safe
{
    import audiotag.id3v2.v24.attached_picture_write :
        measureId3v24Utf8EmbeddedPicturePayload,
        measureId3v24Utf8LinkedPicturePayload;

    return field.value.match!(
        (const(MetadataPicture) picture)
        {
            return picture.source.match!(
                (const(MetadataBinary) binary)
                {
                    auto measured =
                        measureId3v24Utf8EmbeddedPicturePayload(
                            binary.mediaType,
                            pictureType,
                            picture.description,
                            binary.data
                        );

                    return measured.hasValue;
                },

                (const(MetadataUrl) url)
                {
                    auto measured =
                        measureId3v24Utf8LinkedPicturePayload(
                            pictureType,
                            picture.description,
                            url.value
                        );

                    return measured.hasValue;
                }
            );
        },

        _ => false
    );
}


private bool
privatePayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    import audiotag.id3v2.v24.private_write :
        measureId3v24PrivatePayload;

    if (
        field.qualifiers.length != 1 ||
        field.qualifiers[0].name != "owner"
    )
    {
        return false;
    }

    return field.value.match!(
        (const(MetadataBinary) binary)
        {
            /*
             * PRIV has no native media-type field. Accepting one here
             * would silently discard canonical information.
             */
            if (binary.mediaType.length != 0)
                return false;

            auto measured =
                measureId3v24PrivatePayload(
                    field.qualifiers[0].value,
                    binary.data
                );

            return measured.hasValue;
        },

        _ => false
    );
}


private bool
ufidPayloadRepresentable(
    ref const(MetadataField) field
)
    @safe
{
    import audiotag.id3v2.v24.unique_file_identifier_write :
        measureId3v24UniqueFileIdentifierPayload;

    if (
        field.qualifiers.length != 1 ||
        field.qualifiers[0].name != "owner"
    )
    {
        return false;
    }

    return field.value.match!(
        (const(MetadataBinary) binary)
        {
            /*
             * UFID has no native media-type field. Accepting one would
             * silently discard canonical information.
             */
            if (binary.mediaType.length != 0)
                return false;

            auto measured =
                measureId3v24UniqueFileIdentifierPayload(
                    field.qualifiers[0].value,
                    binary.data
                );

            return measured.hasValue;
        },

        _ => false
    );
}

/++
Plans one canonical field for lossless ID3v2.4 representation.

The function is intentionally conservative. Context that cannot yet be
encoded losslessly rejects planning rather than being silently dropped.

Rules by target family:

- ordinary T*** and W***: no language, description or qualifiers;
- TXXX/WXXX: description is permitted, language and qualifiers are not;
- COMM/USLT: exactly one three-byte language code is required;
  description is permitted;
- APIC: exactly one known `pictureRole` is required as the sole field
  qualifier; field-level language/description contexts are unsupported
  because APIC description belongs to `MetadataPicture`; embedded
  binary artwork requires a media type; both embedded and linked
  payloads must satisfy the concrete APIC codec;
- PRIV/UFID: exactly one `owner` is required as the sole qualifier;
  language and description are unsupported;
- UFID owner identifiers must satisfy the concrete native owner codec,
  identifier data must not exceed 64 bytes, and binary media type
  context is unsupported because UFID has no native media-type field.

Params:
    field = Canonical field to represent as ID3v2.4 metadata.

Returns:
    Explicit canonical field representability plan.
+/
Id3v24CanonicalFieldPlan
planId3v24CanonicalField(
    ref const(MetadataField) field
)
    @safe
{
    const lookup =
        findId3v24CanonicalTarget(
            MetadataKey(
                field.key.name
            )
        );

    if (!lookup.found)
    {
        return
            Id3v24CanonicalFieldPlan(
                Id3v24CanonicalFieldPlanStatus
                    .unsupportedCanonicalKey,
                Id3v24CanonicalTargetDefinition.init
            );
    }

    const target =
        lookup.definition;

    if (
        valueKindOf(field) !=
        target.valueKind
    )
    {
        return
            Id3v24CanonicalFieldPlan(
                Id3v24CanonicalFieldPlanStatus
                    .invalidValueKind,
                target
            );
    }

    Id3v24CanonicalFieldPlanStatus status;

    final switch (target.family)
    {
                case Id3v24CanonicalTargetFamily.textInformation:
        {
            if (!hasNoAdditionalContext(field))
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                textInformationPayloadRepresentable(field)
                ? Id3v24CanonicalFieldPlanStatus.ready
                : Id3v24CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v24CanonicalTargetFamily.urlLink:
        {
            if (!hasNoAdditionalContext(field))
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                urlLinkPayloadRepresentable(field)
                ? Id3v24CanonicalFieldPlanStatus.ready
                : Id3v24CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v24CanonicalTargetFamily.userText:
        {
            if (
                field.hasLanguage ||
                field.hasQualifiers
            )
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                userTextPayloadRepresentable(field)
                ? Id3v24CanonicalFieldPlanStatus.ready
                : Id3v24CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v24CanonicalTargetFamily.userUrl:
        {
            if (
                field.hasLanguage ||
                field.hasQualifiers
            )
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                userUrlPayloadRepresentable(field)
                ? Id3v24CanonicalFieldPlanStatus.ready
                : Id3v24CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v24CanonicalTargetFamily.languageText:
        {
            if (!field.hasLanguage)
            {
                status =
                    Id3v24NewFramePlanStatus
                        .missingRequiredContext;

                break;
            }

            if (!languageIsNativeThreeByteCode(field))
            {
                status =
                    Id3v24NewFramePlanStatus
                        .nativeConstraintViolation;

                break;
            }

            if (field.hasQualifiers)
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                languageTextPayloadRepresentable(field)
                ? Id3v24CanonicalFieldPlanStatus.ready
                : Id3v24CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v24CanonicalTargetFamily.attachedPicture:
        {
            if (
                field.hasLanguage ||
                field.hasDescription
            )
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            const roleCount =
                qualifierCount(
                    field,
                    "pictureRole"
                );

            if (roleCount == 0)
            {
                status =
                    Id3v24NewFramePlanStatus
                        .missingRequiredContext;

                break;
            }

            if (
                roleCount != 1 ||
                !hasOnlyQualifier(
                    field,
                    "pictureRole"
                )
            )
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            import audiotag.id3v2.v24.picture_role :
                findId3v24PictureRole;

            const role =
                findId3v24PictureRole(
                    field.qualifiers[0].value
                );

            if (!role.found)
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .nativeConstraintViolation;

                break;
            }

            if (!artworkSourceHasRequiredContext(field))
            {
                status =
                    Id3v24NewFramePlanStatus
                        .missingRequiredContext;

                break;
            }

            status =
                artworkPayloadRepresentable(
                    field,
                    role.definition.pictureType
                )
                ? Id3v24CanonicalFieldPlanStatus.ready
                : Id3v24CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v24CanonicalTargetFamily.privateData:
        case Id3v24CanonicalTargetFamily.uniqueFileIdentifier:
        {
            if (
                field.hasLanguage ||
                field.hasDescription
            )
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            const ownerCount =
                qualifierCount(
                    field,
                    "owner"
                );

            if (ownerCount == 0)
            {
                status =
                    Id3v24NewFramePlanStatus
                        .missingRequiredContext;

                break;
            }

            if (
                !hasOnlyQualifier(
                    field,
                    "owner"
                )
            )
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            if (
                target.family ==
                    Id3v24CanonicalTargetFamily
                        .privateData &&
                ownerCount != 1
            )
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            if (
                target.family ==
                    Id3v24CanonicalTargetFamily
                        .privateData &&
                !privatePayloadRepresentable(field)
            )
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .nativeConstraintViolation;

                break;
            }

            if (
                target.family ==
                    Id3v24CanonicalTargetFamily
                        .uniqueFileIdentifier &&
                ownerCount != 1
            )
            {
                status =
                    Id3v24NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            if (
                target.family ==
                    Id3v24CanonicalTargetFamily
                        .uniqueFileIdentifier &&
                !ufidPayloadRepresentable(field)
            )
            {
                status =
                    Id3v24CanonicalFieldPlanStatus
                        .nativeConstraintViolation;

                break;
            }

            status =
                Id3v24CanonicalFieldPlanStatus.ready;

            break;
        }
    }

    return
        Id3v24CanonicalFieldPlan(
            status,
            target
        );
}


/++
Plans one newly introduced canonical field for ID3v2.4 output.

This is the edit-overlay-specific wrapper around
`planId3v24CanonicalField`.

Params:
    newFieldIndex = Position in `MetadataTreeEdit.newFields`.
    field = Newly introduced canonical field.

Returns:
    New-frame plan retaining the edit-overlay index.
+/
Id3v24NewFramePlan
planId3v24NewCanonicalFrame(
    size_t newFieldIndex,
    ref const(MetadataField) field
)
    @safe
{
    const fieldPlan =
        planId3v24CanonicalField(
            field
        );

    return
        Id3v24NewFramePlan(
            newFieldIndex,
            fieldPlan.status,
            fieldPlan.target
        );
}


version (unittest)
{
    import audiotag.metadata.field :
        MetadataLanguage,
        MetadataQualifier;

    import audiotag.metadata.value :
        MetadataPictureSource,
        MetadataValue;


    private MetadataField textField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataText(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField textListField(
        string key,
        string[] values
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataTextList(values);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField urlField(
        string key,
        string value
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataUrl(value);

        return
            MetadataField(
                MetadataKey(key),
                wrapped
            );
    }


    private MetadataField binaryField(
        string key,
        const(ubyte)[] data,
        string qualifierName = "",
        string qualifierValue = ""
    )
        @safe
    {
        MetadataValue wrapped =
            MetadataBinary.copyFrom(data);

        auto field =
            MetadataField(
                MetadataKey(key),
                wrapped
            );

        if (qualifierName.length != 0)
        {
            field.qualifiers =
                [
                    MetadataQualifier(
                        qualifierName,
                        qualifierValue
                    )
                ];
        }

        return field;
    }
}


/// Canonical representability can be checked without new-field context.
unittest
{
    const field =
        textField(
            "title",
            "Canonical title"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus.ready
    );

    assert(plan.target.frameId == "TIT2");
}


/// Canonical replacement validation rejects unsupported context directly.
unittest
{
    auto field =
        textField(
            "title",
            "Canonical title"
        );

    field.description =
        "cannot-be-stored-in-TIT2";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .unsupportedContext
    );
}


/// A normal new title has one deterministic writable target.
unittest
{
    const field =
        textField(
            "title",
            "New title"
        );

    const plan =
        planId3v24NewCanonicalFrame(
            3,
            field
        );

    assert(plan.writable);
    assert(plan.newFieldIndex == 3);
    assert(plan.target.frameId == "TIT2");
}


/// Artist lists target TPE1 without collapsing ordered values.
unittest
{
    const field =
        textListField(
            "artist",
            ["Artist A", "Artist B"]
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "TPE1");
}


/// Empty artist lists cannot be represented losslessly as TPE1.
unittest
{
    const field =
        textListField(
            "artist",
            []
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "TPE1");
}


/// Embedded NUL text cannot silently become multiple native values.
unittest
{
    const field =
        textField(
            "title",
            "A\0B"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "TIT2");
}


/// Ordinary ASCII URLs remain writable W*** targets.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "https://example.test/"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus.ready
    );

    assert(plan.target.frameId == "WCOM");
}


/// ISO-8859-1 URL characters remain losslessly representable.
unittest
{
    const field =
        urlField(
            "artistUrl",
            "https://example.test/\u00E9"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "WOAR");
}


/// Empty URLs retain a valid non-zero native W*** representation.
unittest
{
    const field =
        urlField(
            "publisherUrl",
            ""
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "WPUB");
}


/// Unicode outside ISO-8859-1 blocks ordinary W*** planning.
unittest
{
    const field =
        urlField(
            "commercialUrl",
            "https://example.test/\u20AC"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "WCOM");
}


/// Embedded NUL cannot silently truncate an ordinary native URL.
unittest
{
    const field =
        urlField(
            "audioFileUrl",
            "abc\0def"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "WOAF");
}


/// Unsupported canonical context takes precedence over payload encoding.
unittest
{
    auto field =
        urlField(
            "commercialUrl",
            "https://example.test/\u20AC"
        );

    field.description =
        "not-representable-in-WCOM";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .unsupportedContext
    );
}


/// Unknown canonical semantics remain explicitly unsupported.
unittest
{
    const field =
        textField(
            "futureSemantic",
            "x"
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .unsupportedCanonicalKey
    );
}


/// A known canonical key with the wrong value family is rejected.
unittest
{
    const field =
        textField(
            "artist",
            "Not a text list"
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .invalidValueKind
    );
}


/// WXXX planning consults the concrete user-URL payload codec.
unittest
{
    auto field =
        urlField(
            "userUrl",
            "https://example.test/"
        );

    field.description =
        "homepage";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus.ready
    );

    assert(plan.target.frameId == "WXXX");
}


/// WXXX permits both an empty description and an empty URL.
unittest
{
    const field =
        urlField(
            "userUrl",
            ""
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "WXXX");
}


/// A WXXX URL outside ISO-8859-1 is rejected during planning.
unittest
{
    auto field =
        urlField(
            "userUrl",
            "https://example.test/\u20AC"
        );

    field.description =
        "homepage";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "WXXX");
}


/// Embedded NUL cannot silently terminate a WXXX description early.
unittest
{
    auto field =
        urlField(
            "userUrl",
            "https://example.test/"
        );

    field.description =
        "home\0page";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );
}


/// Embedded NUL cannot silently truncate the WXXX URL.
unittest
{
    auto field =
        urlField(
            "userUrl",
            "abc\0def"
        );

    field.description =
        "homepage";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );
}


/// Unsupported WXXX context takes precedence over payload failure.
unittest
{
    auto field =
        urlField(
            "userUrl",
            "https://example.test/\u20AC"
        );

    field.description =
        "homepage";

    field.language =
        MetadataLanguage("eng");

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .unsupportedContext
    );
}


/// TXXX planning consults the concrete UTF-8 payload codec.
unittest
{
    auto field =
        textField(
            "userText",
            "abc-123"
        );

    field.description =
        "MusicBrainz Album Id";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus.ready
    );

    assert(plan.target.frameId == "TXXX");
}


/// TXXX remains writable when its canonical description is unspecified.
unittest
{
    const field =
        textField(
            "userText",
            "value"
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "TXXX");
}


/// Embedded NUL in a TXXX scalar value has no supported canonical encoding.
unittest
{
    auto field =
        textField(
            "userText",
            "a\0b"
        );

    field.description =
        "key";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "TXXX");
}


/// Embedded NUL cannot silently terminate a TXXX description early.
unittest
{
    auto field =
        textField(
            "userText",
            "value"
        );

    field.description =
        "a\0b";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "TXXX");
}


/// Unsupported TXXX context takes precedence over payload encoding failure.
unittest
{
    auto field =
        textField(
            "userText",
            "a\0b"
        );

    field.description =
        "key";

    field.language =
        MetadataLanguage("eng");

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .unsupportedContext
    );
}


/// TXXX permits its canonical description but not language context.
unittest
{
    auto field =
        textField(
            "userText",
            "value"
        );

    field.description =
        "custom-key";

    auto plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "TXXX");

    field.language =
        MetadataLanguage("eng");

    plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .unsupportedContext
    );
}


/// COMM requires a native three-byte language code.
unittest
{
    auto field =
        textField(
            "comment",
            "Example"
        );

    auto plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .missingRequiredContext
    );

    field.language =
        MetadataLanguage("eng");

    field.description =
        "short";

    plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "COMM");

    field.language =
        MetadataLanguage("english");

    plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// PRIV requires exactly one owner qualifier.
unittest
{
    auto field =
        binaryField(
            "privateData",
            [cast(ubyte) 0x01]
        );

    auto plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .missingRequiredContext
    );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "example.invalid/private"
            )
        ];

    plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "PRIV");
}


/// PRIV owner must be representable by the concrete native payload codec.
unittest
{
    auto field =
        binaryField(
            "privateData",
            [cast(ubyte) 0x01]
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "owner/\u20AC"
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "PRIV");
}


/// Embedded NUL cannot silently truncate a planned PRIV owner.
unittest
{
    auto field =
        binaryField(
            "privateData",
            [
                cast(ubyte) 0x00,
                cast(ubyte) 0xFF
            ]
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "owner\0suffix"
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// Empty PRIV owner remains representable because the reader permits it.
unittest
{
    auto field =
        binaryField(
            "privateData",
            []
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                ""
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "PRIV");
}


/// PRIV cannot silently discard a canonical binary media type.
unittest
{
    MetadataValue wrapped =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0x01],
            "application/octet-stream"
        );

    auto field =
        MetadataField(
            MetadataKey("privateData"),
            wrapped
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "example.invalid/private"
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// Duplicate PRIV owner qualifiers are unsupported canonical context.
unittest
{
    auto field =
        binaryField(
            "privateData",
            [cast(ubyte) 0x01]
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "one"
            ),
            MetadataQualifier(
                "owner",
                "two"
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .unsupportedContext
    );
}


/// UFID requires a non-empty owner identifier.
unittest
{
    const field =
        binaryField(
            "uniqueFileIdentifier",
            [cast(ubyte) 0x01],
            "owner",
            ""
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "UFID");
}


/// UFID owner must be representable as native ISO-8859-1.
unittest
{
    const field =
        binaryField(
            "uniqueFileIdentifier",
            [cast(ubyte) 0x01],
            "owner",
            "owner/\u20AC"
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// Embedded NUL cannot silently truncate a planned UFID owner.
unittest
{
    const field =
        binaryField(
            "uniqueFileIdentifier",
            [cast(ubyte) 0x01],
            "owner",
            "owner\0suffix"
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// Duplicate UFID owner qualifiers are unsupported canonical context.
unittest
{
    auto field =
        binaryField(
            "uniqueFileIdentifier",
            [cast(ubyte) 0x01]
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "one"
            ),
            MetadataQualifier(
                "owner",
                "two"
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .unsupportedContext
    );
}


/// UFID cannot silently discard canonical binary media-type context.
unittest
{
    MetadataValue wrapped =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0x01],
            "application/octet-stream"
        );

    auto field =
        MetadataField(
            MetadataKey(
                "uniqueFileIdentifier"
            ),
            wrapped
        );

    field.qualifiers =
        [
            MetadataQualifier(
                "owner",
                "example.invalid"
            )
        ];

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// Empty UFID identifier data remains natively representable.
unittest
{
    const field =
        binaryField(
            "uniqueFileIdentifier",
            [],
            "owner",
            "example.invalid"
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "UFID");
}


/// UFID retains the native 64-byte identifier limit.
unittest
{
    ubyte[64] acceptedBytes;
    ubyte[65] rejectedBytes;

    auto accepted =
        binaryField(
            "uniqueFileIdentifier",
            acceptedBytes[],
            "owner",
            "https://example.invalid/id"
        );

    auto plan =
        planId3v24NewCanonicalFrame(
            0,
            accepted
        );

    assert(plan.writable);
    assert(plan.target.frameId == "UFID");

    auto rejected =
        binaryField(
            "uniqueFileIdentifier",
            rejectedBytes[],
            "owner",
            "https://example.invalid/id"
        );

    plan =
        planId3v24NewCanonicalFrame(
            0,
            rejected
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// Embedded APIC artwork requires MIME type and picture-role context.
unittest
{
    MetadataPictureSource sourceWithoutMime =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0xFF]
        );

    MetadataValue valueWithoutMime =
        MetadataPicture(
            "Cover",
            sourceWithoutMime
        );

    auto field =
        MetadataField(
            MetadataKey("artwork"),
            valueWithoutMime
        );

    auto plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .missingRequiredContext
    );

    field.qualifiers =
        [
            MetadataQualifier(
                "pictureRole",
                "frontCover"
            )
        ];

    plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v24NewFramePlanStatus
            .missingRequiredContext
    );

    MetadataPictureSource sourceWithMime =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0xFF],
            "image/jpeg"
        );

    MetadataValue valueWithMime =
        MetadataPicture(
            "Cover",
            sourceWithMime
        );

    field =
        MetadataField(
            MetadataKey("artwork"),
            valueWithMime,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier(
                    "pictureRole",
                    "frontCover"
                )
            ]
        );

    plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "APIC");
}


/// Linked APIC artwork does not require an image MIME type.
unittest
{
    MetadataPictureSource source =
        MetadataUrl(
            "https://example.invalid/cover.jpg"
        );

    MetadataValue value =
        MetadataPicture(
            "Cover",
            source
        );

    const field =
        MetadataField(
            MetadataKey("artwork"),
            value,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier(
                    "pictureRole",
                    "frontCover"
                )
            ]
        );

    const plan =
        planId3v24NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
}



/// APIC planning rejects an unknown canonical picture role.
unittest
{
    MetadataPictureSource source =
        MetadataBinary.copyFrom(
            [
                cast(ubyte) 0xFF,
                cast(ubyte) 0xD8
            ],
            "image/jpeg"
        );

    MetadataValue value =
        MetadataPicture(
            "Cover",
            source
        );

    const field =
        MetadataField(
            MetadataKey("artwork"),
            value,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier(
                    "pictureRole",
                    "futurePictureRole"
                )
            ]
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "APIC");
}


/// APIC requires exactly one picture-role qualifier.
unittest
{
    MetadataPictureSource source =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0xFF],
            "image/jpeg"
        );

    MetadataValue value =
        MetadataPicture(
            "Cover",
            source
        );

    const field =
        MetadataField(
            MetadataKey("artwork"),
            value,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier(
                    "pictureRole",
                    "frontCover"
                ),
                MetadataQualifier(
                    "pictureRole",
                    "backCover"
                )
            ]
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .unsupportedContext
    );
}


/// APIC planning consults the concrete embedded-picture payload codec.
unittest
{
    MetadataPictureSource source =
        MetadataBinary.copyFrom(
            [cast(ubyte) 0xFF],
            "image/jpeg"
        );

    MetadataValue value =
        MetadataPicture(
            "Front\0cover",
            source
        );

    const field =
        MetadataField(
            MetadataKey("artwork"),
            value,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier(
                    "pictureRole",
                    "frontCover"
                )
            ]
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "APIC");
}


/// APIC planning consults the concrete linked-picture payload codec.
unittest
{
    MetadataPictureSource source =
        MetadataUrl(
            "https://example.test/€"
        );

    MetadataValue value =
        MetadataPicture(
            "Cover",
            source
        );

    const field =
        MetadataField(
            MetadataKey("artwork"),
            value,
            [],
            MetadataLanguage.init,
            "",
            [
                MetadataQualifier(
                    "pictureRole",
                    "frontCover"
                )
            ]
        );

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "APIC");
}


/// COMM planning consults the concrete UTF-8 language-text payload codec.
unittest
{
    auto field =
        textField(
            "comment",
            "a\0b"
        );

    field.language =
        MetadataLanguage("eng");

    field.description =
        "short";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "COMM");
}


/// USLT planning uses the shared language-text payload codec.
unittest
{
    auto field =
        textField(
            "lyrics",
            "lyrics body"
        );

    field.language =
        MetadataLanguage("eng");

    field.description =
        "verse\0one";

    const plan =
        planId3v24CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v24CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "USLT");
}
