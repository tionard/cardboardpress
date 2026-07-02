# Layer redesign — decision note

_Settled design from a brainstorm session. Drop the relevant parts into
`references/decisions.md` (under **Resolved**) and use the phasing at the bottom to start the
build. No code written yet — this is agreed direction, ready to implement._

_This is a large change (model + serialization + render + template editor + card editor +
migration). It replaces the fixed nine-field-type system and the hardcoded layer order._

---

## The headline concept

**A template becomes a single ordered `List<Layer>`.** The list order *is* the z-order.
`paintCard` walks the list bottom→top and draws each layer. Two rigid things die at once:

- the **fixed enum of nine field types** (`name`/`alias`/`cost`/`type`/`rules`/`flavor`/`stat`/
  `art`/`footer`) → replaced by a **generic layer** plus a few special kinds; and
- the **hardcoded draw order** (base → tint → fields → border → watermark → foil) → replaced by
  the list order, reorderable by drag-and-drop.

Everything that used to be a separate concept — base colour, tint, watermark, foil, set symbol,
9-slice border — is now just a **layer** in that one list. There is no privileged "card base
colour" any more: the base is simply a fill layer that happens to sit low. A user can drop an
image layer *below* a semi-transparent fill and it shows through. That is the point.

---

## Resolved decisions

### Layer model
- **One `Layer` model.** A `kind` field distinguishes generic from the few special kinds.
  Colloquially a "field" is just a layer that has a per-card binding.
- **`LayerKind = { generic, art, rules, footer }`.** There is **no `text` kind** — plain text
  is a generic layer with a text aspect (redundant to have both). `art`, `rules`, `footer`
  stay special because they carry **bespoke per-card editors** (image import + zoom/pan; rich
  text markup + inline symbols; footer configuration).
- **No "scope" split — every layer has a `rect`.** The old whole-card-vs-rect distinction is
  gone. Whole-card/background layers simply default their rect to the full card bounds, and can
  be shrunk to cover only a region (e.g. tint just the title bar). Rect unit is **unchanged**
  from today (same normalized coordinates).
- Layer carries: `id`, `name`, `visible`, `kind`, `rect`, its opt-in **aspects**, and its
  **exposure** map.

### Aspects (opt-in; a generic layer picks any subset)
Fixed set of optional aspects, each reusing today's data where possible:
- **fill** — `ColorRef` + fill alpha + corner radius.
- **border** — 9-slice sprite + insets + tint.
- **image** — `source` (`fixed` | `setSymbol`) + image/symbol ref + tint + fit. (The `art`
  kind extends this with zoom/pan.)
- **outline** — `OutlineSpec` (includes outline colour).
- **foil** — foil parameters.
- **text** — text style (size, bold, italic, colour, align, vertical align, fit, padX, padY) +
  content (literal or bound). A text aspect **may render a text symbol**, not just characters.

**Fixed sub-order inside a single layer:** `fill → image → border → outline → foil → text`.
If a user needs a different stacking between these, they split them into separate layers — the
list gives full control; the sub-order only matters when one layer stacks multiple aspects.

### Special kinds
- **`art`** — bespoke per-card editor (import image, zoom/pan, placeholder when empty).
  **Multiple `art` layers are allowed** (the old "one art field" cap dies with the enum). Split
  cards, dual art, etc. are just two art layers.
- **`rules`** — rich text (bold/italic markup + inline symbols), as today.
- **`footer`** — footer configuration (arrangement is template-level; values resolve per card),
  as today.
- **Set symbol is NOT a special kind.** It is a generic layer with an **image aspect**,
  `source = setSymbol`. It resolves its image from the card's assigned **set** and auto-tints
  with the card's **rarity** colour. Set and rarity are *card attributes* chosen in the `set`
  tab, so the layer has no per-card editor of its own — it just renders whatever the card's set
  resolves to. That is dynamic resolution, not a new kind.

### Per-card exposure (which controls appear in the card editor)
- **Per-aspect expose toggle, and a layer may expose several aspects at once.** (This
  supersedes the earlier "one binding per layer" idea.)
- Modelled as `exposed: Map<ExposedAspect, EditorTab>`. Empty map = template-only layer, no
  card-editor control.
- **`ExposedAspect = { text, fill, image, outlineColor, visible }`.**
- **`EditorTab = { card, art, color, set, export }`** — each exposed aspect routes to one tab.
- The control type follows the aspect: text → text input; fill → colour well; image → image
  picker; outlineColor → colour well; visible → toggle.
- A **generic image aspect is exposable per-card** too (a plain picker, no zoom/pan) — distinct
  from the `art` kind, which is the full art editor. Choose `art` kind when the author swaps art
  per card with zoom/pan; choose generic image + exposure when a simple per-card picture swap is
  enough.

### Card editor tabs
- Tabs are **card / art / color / set / export** (unchanged set).
- The **export tab is unchanged**: same controls as today — DPI select (300 / 600), Save to
  Gallery, Share. It is a real card-editor tab.

### Template editor — three views over one list
- **Layout** — place and size layers (spatial editing).
- **Fields** — per-layer aspects and their exposure (which aspects, to which tab).
- **Layers** — drag-reorder the z-order + toggle visibility. **Reuse the existing card-reorder
  drag widget** (same interaction as reordering cards).

### Rendering — single path preserved
`paintCard` loops the list bottom→top; for each visible layer it draws its aspects in the fixed
sub-order, placed/clipped by the layer's rect. It keeps the current **RGBA multiply** semantics
(per-colour alpha × use-site alpha) and the **non-destructive reference + snapshot** model. No
second renderer; preview, thumbnails, and export stay on the one path.

```
for (layer in template.layers) {          // bottom -> top = list order
  if (!layer.visible) continue;
  // sub-order, each drawn only if present:
  if (layer.fill    != null) drawFill(...);
  if (layer.image   != null) drawImage(...);   // source fixed OR setSymbol
  if (layer.border  != null) drawNineSlice(...);
  if (layer.outline != null) drawOutline(...);
  if (layer.foil    != null) drawFoil(...);
  if (layer.text    != null) drawText(...);     // art/rules/footer = bespoke draw
}
```

---

## Model sketch (illustrative, not final field-for-field)

```dart
enum LayerKind { generic, art, rules, footer }
enum EditorTab { card, art, color, set, export }
enum ExposedAspect { text, fill, image, outlineColor, visible }
enum ImageSource { fixed, setSymbol }

class Layer {
  String id;
  String name;
  bool visible;
  LayerKind kind;
  Rect rect;                          // every layer; background layers default full-card

  // opt-in aspects (generic picks any; special kinds carry their own set)
  FillAspect?    fill;                // ColorRef + fillAlpha + cornerRadius
  BorderAspect?  border;             // 9-slice sprite + insets + tint
  ImageAspect?   image;              // source + ref + tint + fit (+ zoom/pan for art)
  OutlineAspect? outline;            // OutlineSpec incl. outline colour
  FoilAspect?    foil;
  TextAspect?    text;               // style + content; may render a text symbol

  Map<ExposedAspect, EditorTab> exposed; // per-aspect expose; empty = template-only
}
```

Template = ordered `List<Layer>`. The old `FieldType` enum, the separate `baseColor` / `tint` /
`watermark` / `foil` slots, and the fixed draw order are all removed.

---

## Migration v11 → v12 (the careful part)

The database schema gains layer/aspect/exposure storage → **schema v12**, which means
`dart run build_runner build --delete-conflicting-outputs`.

**Golden rule: build the new list in the exact current draw order, so every existing card
renders pixel-identical.** This is a constitution requirement, not a nicety.

Map old → new, appended in current draw order:

| Old construct | New layer |
|---|---|
| `baseColor` | generic · `fill` (full-rect, α = 1) · bottom of list |
| `tint` | generic · `fill` (full-rect, α = `tintAlpha`) · `exposed { fill → color }` |
| each field, **in current order** | one layer; `FieldType` → kind (`art`/`rules`/`footer` → bespoke kinds; everything else → generic + `text`); field fill / 9-slice / outline → the matching aspects; per-card text → `exposed { text → card }` |
| `watermark` | generic · `image` (full-rect) |
| `foil` | generic · `foil` (full-rect) |
| set symbol | generic · `image` · `source = setSymbol` (rarity tint), resolves via card set/rarity |

Additional migration rules:
- **Re-key per-card content.** Today content is keyed by field type / field id; re-key to
  `layer id + bound aspect` and migrate the content rows.
- **Auto-name** migrated layers (Base, Tint, Name, Type, Rules, Art, Footer, Watermark, Foil,
  Set, …); de-duplicate names where needed.
- **Back up the DB before migrating** and fail safe — a failed/aborted migration must leave no
  partial or corrupt state.
- **Verify pixel-identical.** Render-diff a sample of existing cards before vs after migration;
  they must match. This is the gate for shipping the migration.

---

## Implementation map / phasing (test between each stage)

1. **Model + migration, no UI.** Add `Layer` + aspects + ordered list; write the v11→v12
   migration; **verify existing cards render pixel-identical**. Nothing user-visible yet.
2. **Render.** Point `paintCard` at the list loop (single path, multiply + ref/snapshot intact).
3. **Layers tab first.** Drag-reorder + visibility, reusing the card-reorder drag widget. Cheap
   win that proves the list end-to-end.
4. **Fields tab.** Generic aspect UI + per-aspect exposure toggles (aspect → tab).
5. **Card editor.** Build per-card controls from each layer's `exposed` map, into the right tab.
6. **Layout tab** adapts to the list; retire the `FieldType` enum (art/rules/footer remain
   bespoke kinds; set symbol is generic + `source = setSymbol`).

---

## Still open (decide during build)
- Exact serialized shapes of each aspect (reuse existing `FieldSpec` / `OutlineSpec` / 9-slice /
  watermark structs where possible rather than reinventing).
- How border insets and the 9-slice reference serialize inside the border aspect.
- Whether `footer` stays a distinct bespoke kind long-term or later collapses into a generic
  layer with a footer aspect (keep it a kind for v1).
- Auto-naming collisions and how far to de-duplicate.
