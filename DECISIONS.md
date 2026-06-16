# CardboardPress — Decisions Log

A running record of non-obvious design/architecture decisions, why they were
made, and their status. Newest at the top.

---

## 2026-06-16 — Color usage scoping via per-swatch tags

**Status:** Accepted; implementation deferred.

**Context.** Colors are a single flat palette, usable anywhere (card tint, field
fill, rarity, watermark, text). As a palette grows, picking the right color for a
given context (text vs card bg vs symbol) gets noisy. Three approaches were
considered:
1. Fixed, exclusive categories (card / symbol / text).
2. User-defined categories, possibly scoped per set, with a two-step
   category→color picker.
3. Per-swatch tags: each swatch carries text / symbol / card flags.

**Decision.** Go with option 3 (tags), with two qualifiers:
- Tags **filter, not forbid.** A color picker opened in a given context defaults
  to showing swatches tagged for that context, but always offers "show all" so a
  color is never hard-blocked. This preserves the spec's "any color anywhere"
  principle.
- New swatches default to **all tags on**, so existing behavior is unchanged
  until a user chooses to curate.

**Rationale.**
- Option 1 is too rigid: a color wanted for two uses must be duplicated, and the
  copies drift. It also contradicts the spec's "no single-purpose color sites."
- Option 2 is powerful but heavy (a new entity + CRUD + two-step picker) and
  drags in the much larger, separate question of per-set vs global palettes —
  premature before we know it's needed.
- Option 3 keeps one flat palette (no duplication), treats usage as additive
  metadata on the swatch, and is the cheapest to build (three boolean columns +
  a picker filter).

**Timing.** Tags only do work when there is an in-context color picker to filter,
and none exists yet (colors currently appear only in the Customize list and the
hardcoded sample card). Implementing now would ship a producer with no consumer.
Implement alongside the first real color picker (Card Editor tint selection or
the text-color reference UI). The cost of waiting is negligible: adding the
columns later is an additive migration (bump schemaVersion to 2; add three
boolean columns defaulting to true; existing rows untouched).

**Parked.** Per-set (vs global) palettes — option 2's scoping idea — is a larger,
unrelated decision tied to how Sets work. Revisit when Sets are real entities.
