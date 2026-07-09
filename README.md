# CardboardPress

**A free, offline card-face designer for trading card games.**

Design templates, fill them with card content, and export print-ready PNGs — no
account, no internet connection, no subscription. Everything lives on your
device. Runs on **Android** and **Windows** desktop.

> Built with Flutter. Currently in active development — expect rough edges.

---

## What it does

- **Templates define layout, cards carry content.** Build a template once —
  layers, colours, fonts, art zones, borders, foil, watermarks — then create
  as many cards from it as you like. Edit the template later and every card
  built from it updates.
- **A real layer system**, not a fixed set of fields. Each layer is a fill,
  an image, an outline, text, a 9-slice border, foil, or a watermark, freely
  reordered and combined. Pick per-layer which controls (if any) show up in
  the card editor.
- **One render path.** The exact same drawing code produces the on-screen
  preview, the collection thumbnails, and the exported PNG — what you see is
  always what you get, at whatever print resolution you export to.
- **A built-in palette, symbol library, and rarity/set system**, so recolours
  and reskins are fast across a whole collection.
- **13 bundled, license-cleared fonts** (see [Fonts](#fonts) below) selectable
  per text layer, from clean sans and classic book serifs to fantasy display
  faces, script, and pixel styles.
- **Local backup & restore** as a single zip — your templates, cards, and
  images, portable between machines.
- **No network access, no accounts, no tracking.** The app doesn't know you
  exist.

## Getting it

Pre-built binaries: see the [Releases](../../releases) page (or, once
published, the [itch.io page](#) — link coming soon).

Building it yourself is below.

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable channel).

```bash
git clone https://github.com/tionard/cardboardpress.git
cd cardboardpress
flutter pub get
flutter run                 # pick a connected device / Windows
```

Release builds:

```bash
flutter build apk --release            # Android, single APK
flutter build windows --release        # Windows desktop
```

## Tech stack

| Layer | Choice |
|---|---|
| UI framework | Flutter (Android + Windows desktop) |
| State management | [Riverpod](https://riverpod.dev) |
| Local database | [Drift](https://drift.simonbinder.eu) over SQLite |
| Rendering | Raw `dart:ui` — no dependency on Flutter's widget layer for card drawing |
| Backup format | Zip, via [`archive`](https://pub.dev/packages/archive) |

Nothing calls out to a server. The heaviest dependencies (`file_picker`,
`share_plus`, `gal`) exist purely for OS-level "save/share this file" dialogs.

## Project structure

```
lib/
  model/       data classes + JSON (de)serialization — no Flutter imports
  rendering/   the one true render path (dart:ui), used by preview & export alike
  data/        Drift database, repositories, image store, backup/restore
  state/       Riverpod providers
  features/    one folder per screen: collection, template editor, card editor,
               customization (palette/symbols/rarities), settings
  widgets/     shared UI: card preview, colour picker, sliders, etc.
test/          render-parity and persistence tests
```

If you're digging into the codebase, the `references/` folder and the
project's Claude skill (`cardboardpress-guide`, if you use Claude) document
the architecture — the layer/exposure system in particular — in more depth
than fits here.

## Fonts

CardboardPress bundles 13 fonts for use in card templates, all under the
[SIL Open Font License](https://openfontlicense.org/) — free for personal and
commercial use, redistributable, embeddable in an app. **The OFL is a
separate license from this project's MIT license**: the font files under
`assets/fonts/` are governed by the license texts alongside them in
`assets/fonts/licenses/`, not by `LICENSE` at the repo root. Full attribution
is also surfaced in-app under Settings → Licenses.

Cinzel · Uncial Antiqua · Almendra · Almendra SC · EB Garamond · Alegreya ·
Alegreya SC · Inter · Dancing Script · Great Vibes · VT323 · Orbitron ·
Bangers — all from [Google Fonts](https://fonts.google.com).

## Contributing

Issues and pull requests are welcome. If you're proposing a larger change,
opening an issue first to discuss the approach is appreciated — the layer
rendering system in particular has some non-obvious invariants worth checking
in on before diving in.

## License

CardboardPress's source code is licensed under the [MIT License](LICENSE).

Bundled fonts are licensed separately under the SIL Open Font License — see
[Fonts](#fonts) above.
