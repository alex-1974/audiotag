/++
Root package for the audiotag library.

The root package deliberately does not re-export format modules.

Consumers should import only the library surfaces they need, for example:

---
import audiotag.core;
import audiotag.metadata;
import audiotag.id3v2.v23;
import audiotag.id3v2.v24;
---

This keeps format support modular and avoids implicit dependencies on
unrelated tag systems, containers or conversion layers.
+/
module audiotag;
