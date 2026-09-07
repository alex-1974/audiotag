/++
Planning of one newly introduced canonical field as an ID3v2.3 frame.

The reverse target registry identifies the deterministic native frame
family for a canonical semantic key. This module adds field-level
representability checks before serialization begins.

The planner verifies:

- a canonical ID3v2.3 target exists;
- the canonical value has the expected value family;
- no canonical context would be silently discarded;
- required native context is present;
- simple native constraints already known at planning time are met.

No bytes are emitted here.
+/
module audiotag.id3v2.v23.new_frame_plan;

import std.sumtype :
    match;

import audiotag.metadata.field :
    MetadataField,
    MetadataKey;

import audiotag.metadata.registry :
    MetadataValueKind;

import audiotag.metadata.value :
    MetadataBinary,
    MetadataInteger,
    MetadataPicture,
    MetadataText,
    MetadataTextList,
    MetadataUrl;

import audiotag.id3v2.v23.text_information_write :
    measureId3v23SlashListTextInformationPayload,
    measureId3v23TextInformationPayload;

import audiotag.id3v2.v23.user_text_write :
    measureId3v23UserTextPayload;

import audiotag.id3v2.v23.user_url_write :
    measureId3v23UserUrlPayload;

import audiotag.id3v2.v23.url_link_write :
    measureId3v23UrlLinkPayload;

import audiotag.id3v2.v23.attached_picture :
    Id3v23PictureType;

import audiotag.id3v2.v23.canonical_target :
    Id3v23CanonicalTargetDefinition,
    Id3v23CanonicalTargetFamily,
    findId3v23CanonicalTarget;


/++
Planning outcome for one new canonical field.

Only `ready` may proceed to a future serializer.
+/
enum Id3v23CanonicalFieldPlanStatus : ubyte
{
    /// A deterministic, lossless native target is currently available.
    ready,

    /// No ID3v2.3 reverse target exists for the canonical semantic key.
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
alias Id3v23NewFramePlanStatus =
    Id3v23CanonicalFieldPlanStatus;


/++
Representability plan for one canonical field targeting ID3v2.3.

This type is independent of whether the field is newly inserted or is a
replacement for source-derived canonical metadata.
+/
struct Id3v23CanonicalFieldPlan
{
    /// Planning outcome.
    Id3v23CanonicalFieldPlanStatus status;

    /// Deterministic native target when one was found.
    Id3v23CanonicalTargetDefinition target;

    /++
    Returns whether the field may proceed to ID3v2.3 serialization.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return status ==
            Id3v23CanonicalFieldPlanStatus.ready;
    }
}


/++
Write plan for one newly introduced canonical field.

`newFieldIndex` refers to its position in `MetadataTreeEdit.newFields`.
The field itself is deliberately not copied into the plan.
+/
struct Id3v23NewFramePlan
{
    /// Index in the canonical edit overlay's new-field sequence.
    size_t newFieldIndex;

    /// Planning outcome.
    Id3v23CanonicalFieldPlanStatus status;

    /// Native target when one was found.
    Id3v23CanonicalTargetDefinition target;

    /++
    Returns whether this new field may proceed to serialization.
    +/
    @property
    bool writable() const
        @safe pure nothrow @nogc
    {
        return status ==
            Id3v23NewFramePlanStatus.ready;
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
            MetadataValueKind.picture
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
            auto measured =
                measureId3v23TextInformationPayload(
                    text.value
                );


            return measured.hasValue;
        },

        (const(MetadataTextList) list)
        {
            auto measured =
                measureId3v23SlashListTextInformationPayload(
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
                measureId3v23UserTextPayload(
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
                measureId3v23UserUrlPayload(
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
                measureId3v23UrlLinkPayload(
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
    import audiotag.id3v2.v23.language_text_write :
        measureId3v23LanguageTextPayload;

    if (!field.hasLanguage)
        return false;

    return field.value.match!(
        (const(MetadataText) text)
        {
            auto measured =
                measureId3v23LanguageTextPayload(
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
artworkPayloadRepresentable(
    ref const(MetadataField) field,
    Id3v23PictureType pictureType
)
    @safe
{
    import audiotag.id3v2.v23.attached_picture_write :
        measureId3v23EmbeddedPicturePayload,
        measureId3v23LinkedPicturePayload;

    return field.value.match!(
        (const(MetadataPicture) picture)
        {
            return picture.source.match!(
                (const(MetadataBinary) binary)
                {
                    auto measured =
                        measureId3v23EmbeddedPicturePayload(
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
                        measureId3v23LinkedPicturePayload(
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
    import audiotag.id3v2.v23.private_write :
        measureId3v23PrivatePayload;

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
                measureId3v23PrivatePayload(
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
    import audiotag.id3v2.v23.unique_file_identifier_write :
        measureId3v23UniqueFileIdentifierPayload;

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
                measureId3v23UniqueFileIdentifierPayload(
                    field.qualifiers[0].value,
                    binary.data
                );

            return measured.hasValue;
        },

        _ => false
    );
}

/++
Plans one canonical field for lossless ID3v2.3 representation.

The function is intentionally conservative. Context that cannot yet be
encoded losslessly rejects planning rather than being silently dropped.

Rules by target family:

- ordinary T*** and W***: no language, description or qualifiers;
- TXXX/WXXX: description is permitted, language and qualifiers are not;
- COMM/USLT: exactly one three-byte language code is required;
  description is permitted;
- APIC: exactly one known `pictureRole` is required as the sole field
  qualifier; field-level language/description contexts are unsupported
  because APIC description belongs to `MetadataPicture`; embedded MIME
  spelling, including an empty MIME value, is passed to the concrete
  v2.3 APIC codec; both embedded and linked payloads must satisfy that
  codec;
- PRIV/UFID: exactly one `owner` is required as the sole qualifier;
  language and description are unsupported;
- UFID owner identifiers must satisfy the concrete native owner codec,
  identifier data must not exceed 64 bytes, and binary media type
  context is unsupported because UFID has no native media-type field.

Params:
    field = Canonical field to represent as ID3v2.3 metadata.

Returns:
    Explicit canonical field representability plan.
+/
Id3v23CanonicalFieldPlan
planId3v23CanonicalField(
    ref const(MetadataField) field
)
    @safe
{
    const lookup =
        findId3v23CanonicalTarget(
            MetadataKey(
                field.key.name
            )
        );

    if (!lookup.found)
    {
        return
            Id3v23CanonicalFieldPlan(
                Id3v23CanonicalFieldPlanStatus
                    .unsupportedCanonicalKey,
                Id3v23CanonicalTargetDefinition.init
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
            Id3v23CanonicalFieldPlan(
                Id3v23CanonicalFieldPlanStatus
                    .invalidValueKind,
                target
            );
    }

    Id3v23CanonicalFieldPlanStatus status;

    final switch (target.family)
    {
                case Id3v23CanonicalTargetFamily.textInformation:
        {
            if (!hasNoAdditionalContext(field))
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                textInformationPayloadRepresentable(field)
                ? Id3v23CanonicalFieldPlanStatus.ready
                : Id3v23CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v23CanonicalTargetFamily.urlLink:
        {
            if (!hasNoAdditionalContext(field))
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                urlLinkPayloadRepresentable(field)
                ? Id3v23CanonicalFieldPlanStatus.ready
                : Id3v23CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v23CanonicalTargetFamily.userText:
        {
            if (
                field.hasLanguage ||
                field.hasQualifiers
            )
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                userTextPayloadRepresentable(field)
                ? Id3v23CanonicalFieldPlanStatus.ready
                : Id3v23CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v23CanonicalTargetFamily.userUrl:
        {
            if (
                field.hasLanguage ||
                field.hasQualifiers
            )
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                userUrlPayloadRepresentable(field)
                ? Id3v23CanonicalFieldPlanStatus.ready
                : Id3v23CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v23CanonicalTargetFamily.languageText:
        {
            if (!field.hasLanguage)
            {
                status =
                    Id3v23NewFramePlanStatus
                        .missingRequiredContext;

                break;
            }

            if (!languageIsNativeThreeByteCode(field))
            {
                status =
                    Id3v23NewFramePlanStatus
                        .nativeConstraintViolation;

                break;
            }

            if (field.hasQualifiers)
            {
                status =
                    Id3v23NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            status =
                languageTextPayloadRepresentable(field)
                ? Id3v23CanonicalFieldPlanStatus.ready
                : Id3v23CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v23CanonicalTargetFamily.attachedPicture:
        {
            if (
                field.hasLanguage ||
                field.hasDescription
            )
            {
                status =
                    Id3v23NewFramePlanStatus
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
                    Id3v23NewFramePlanStatus
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
                    Id3v23NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            import audiotag.id3v2.v23.picture_role :
                findId3v23PictureRole;

            const role =
                findId3v23PictureRole(
                    field.qualifiers[0].value
                );

            if (!role.found)
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .nativeConstraintViolation;

                break;
            }

            status =
                artworkPayloadRepresentable(
                    field,
                    role.definition.pictureType
                )
                ? Id3v23CanonicalFieldPlanStatus.ready
                : Id3v23CanonicalFieldPlanStatus
                    .nativeConstraintViolation;

            break;
        }

        case Id3v23CanonicalTargetFamily.privateData:
        case Id3v23CanonicalTargetFamily.uniqueFileIdentifier:
        {
            if (
                field.hasLanguage ||
                field.hasDescription
            )
            {
                status =
                    Id3v23NewFramePlanStatus
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
                    Id3v23NewFramePlanStatus
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
                    Id3v23NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            if (
                target.family ==
                    Id3v23CanonicalTargetFamily
                        .privateData &&
                ownerCount != 1
            )
            {
                status =
                    Id3v23NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            if (
                target.family ==
                    Id3v23CanonicalTargetFamily
                        .privateData &&
                !privatePayloadRepresentable(field)
            )
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .nativeConstraintViolation;

                break;
            }

            if (
                target.family ==
                    Id3v23CanonicalTargetFamily
                        .uniqueFileIdentifier &&
                ownerCount != 1
            )
            {
                status =
                    Id3v23NewFramePlanStatus
                        .unsupportedContext;

                break;
            }

            if (
                target.family ==
                    Id3v23CanonicalTargetFamily
                        .uniqueFileIdentifier &&
                !ufidPayloadRepresentable(field)
            )
            {
                status =
                    Id3v23CanonicalFieldPlanStatus
                        .nativeConstraintViolation;

                break;
            }

            status =
                Id3v23CanonicalFieldPlanStatus.ready;

            break;
        }
    }

    return
        Id3v23CanonicalFieldPlan(
            status,
            target
        );
}


/++
Plans one newly introduced canonical field for ID3v2.3 output.

This is the edit-overlay-specific wrapper around
`planId3v23CanonicalField`.

Params:
    newFieldIndex = Position in `MetadataTreeEdit.newFields`.
    field = Newly introduced canonical field.

Returns:
    New-frame plan retaining the edit-overlay index.
+/
Id3v23NewFramePlan
planId3v23NewCanonicalFrame(
    size_t newFieldIndex,
    ref const(MetadataField) field
)
    @safe
{
    const fieldPlan =
        planId3v23CanonicalField(
            field
        );

    return
        Id3v23NewFramePlan(
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
        planId3v23CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus.ready
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23NewCanonicalFrame(
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
        planId3v23NewCanonicalFrame(
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "TPE1");
}


/// TPE1 cannot represent a slash inside one canonical list element.
unittest
{
    const field =
        textListField(
            "artist",
            [
                "AC/DC",
                "Guest"
            ]
        );


    const plan =
        planId3v23CanonicalField(
            field
        );


    assert(
        !plan.writable
    );


    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );


    assert(
        plan.target.frameId ==
        "TPE1"
    );
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "TIT2");
}


/// Supplementary Unicode is outside deterministic v2.3 UCS-2.
unittest
{
    const field =
        textField(
            "title",
            "A\U0001F600"
        );


    const plan =
        planId3v23CanonicalField(
            field
        );


    assert(
        !plan.writable
    );


    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );


    assert(
        plan.target.frameId ==
        "TIT2"
    );
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
        planId3v23CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus.ready
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
        planId3v23CanonicalField(
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
        planId3v23CanonicalField(
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus.ready
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
        planId3v23CanonicalField(
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .unsupportedContext
    );
}


/// TXXX planning consults the concrete ID3v2.3 payload codec.
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
        planId3v23CanonicalField(
            field
        );

    assert(plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus.ready
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
        planId3v23CanonicalField(
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "TXXX");

    field.language =
        MetadataLanguage("eng");

    plan =
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
            .missingRequiredContext
    );

    field.language =
        MetadataLanguage("eng");

    field.description =
        "short";

    plan =
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(plan.writable);
    assert(plan.target.frameId == "COMM");

    field.language =
        MetadataLanguage("english");

    plan =
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
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
        planId3v23NewCanonicalFrame(
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
        planId3v23NewCanonicalFrame(
            0,
            rejected
        );

    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
            .nativeConstraintViolation
    );
}


/// APIC requires picture-role context but permits empty embedded MIME.
unittest
{
    MetadataPictureSource source =
        MetadataBinary.copyFrom(
            [
                cast(ubyte)
                    0xFF
            ]
        );


    MetadataValue value =
        MetadataPicture(
            "Cover",
            source
        );


    auto field =
        MetadataField(
            MetadataKey(
                "artwork"
            ),
            value
        );


    auto plan =
        planId3v23NewCanonicalFrame(
            0,
            field
        );


    assert(
        plan.status ==
        Id3v23NewFramePlanStatus
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
        planId3v23NewCanonicalFrame(
            0,
            field
        );


    assert(
        plan.writable
    );


    assert(
        plan.target.frameId ==
        "APIC"
    );
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
        planId3v23NewCanonicalFrame(
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "APIC");
}


/// COMM planning consults the concrete ID3v2.3 language-text payload codec.
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
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
        planId3v23CanonicalField(
            field
        );

    assert(!plan.writable);

    assert(
        plan.status ==
        Id3v23CanonicalFieldPlanStatus
            .nativeConstraintViolation
    );

    assert(plan.target.frameId == "USLT");
}
