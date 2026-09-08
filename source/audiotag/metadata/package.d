/++
Public consumer surface for format-independent canonical metadata.

This package provides the common metadata model shared by tag codecs
and container formats:

- typed canonical metadata values;
- ordered fields and trees;
- native provenance;
- canonical field registry information;
- non-destructive edit overlays;
- edit multiplicity validation.

It deliberately contains no tag-format, container or conversion logic.
Importing `audiotag.metadata` therefore does not require ID3, MP3, FLAC,
Ogg or any other metadata system.
+/
module audiotag.metadata;


/*
 * Typed canonical values.
 */
public import audiotag.metadata.value :
    MetadataText,
    MetadataTextList,
    MetadataInteger,
    MetadataUrl,
    MetadataBinary,
    MetadataPictureSource,
    MetadataPicture,
    MetadataValue;


/*
 * Canonical fields and semantic qualifiers.
 */
public import audiotag.metadata.field :
    MetadataKey,
    MetadataLanguage,
    MetadataQualifier,
    MetadataField;


/*
 * Ordered canonical tree.
 */
public import audiotag.metadata.tree :
    MetadataFieldLookup,
    MetadataTree;


/*
 * Native-source provenance retained alongside canonical metadata.
 */
public import audiotag.metadata.provenance :
    MetadataSystem,
    MetadataConfidence,
    NativeMetadataIdentifier,
    MetadataProvenance;


/*
 * Canonical field registry.
 *
 * The registry describes currently defined semantic keys and their
 * expected value kinds/multiplicity. It remains format-independent.
 */
public import audiotag.metadata.registry :
    MetadataValueKind,
    MetadataMultiplicity,
    MetadataFieldDefinition,
    MetadataFieldDefinitionLookup,
    metadataValueKind,
    metadataFieldDefinitions;


/*
 * Non-destructive canonical editing.
 */
public import audiotag.metadata.edit :
    MetadataSourceFieldEditState,
    MetadataSourceFieldEdit,
    MetadataTreeEdit;


/*
 * Validation of the effective tree produced by an edit overlay.
 */
public import audiotag.metadata.edit_validation :
    MetadataTreeEditMultiplicityStatus,
    MetadataTreeEditMultiplicityResult,
    validateMetadataTreeEditMultiplicity;


version (unittest)
{
    /*
     * This test intentionally uses only names exported by this package.
     * It verifies the ordinary format-independent consumer workflow.
     */
    unittest
    {
        MetadataValue titleValue =
            MetadataText("Original");

        auto tree =
            MetadataTree.init;

        tree.append(
            MetadataField(
                MetadataKey("title"),
                titleValue
            )
        );

        assert(tree.length == 1);
        assert(!tree.empty);

        const lookup =
            tree.firstIndex(
                MetadataKey("title")
            );

        assert(lookup.found);
        assert(lookup.index == 0);

        assert(
            metadataValueKind(tree[0].value) ==
            MetadataValueKind.text
        );

        auto edit =
            MetadataTreeEdit.forSource(tree);

        MetadataValue replacementValue =
            MetadataText("Replacement");

        edit.replaceSourceField(
            0,
            MetadataField(
                MetadataKey("title"),
                replacementValue
            )
        );

        assert(!edit.unchanged);

        const validation =
            validateMetadataTreeEditMultiplicity(
                tree,
                edit
            );

        assert(validation.valid);
    }
}
