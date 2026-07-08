// lib/model/font_catalog.dart
//
// The bundled font families a template's text aspect can pick from. Every
// entry maps 1:1 to a `fonts:` family in pubspec.yaml (TTFs under
// assets/fonts/, all SIL Open Font License — commercial use + app bundling
// allowed; the per-family OFL texts ship in assets/fonts/licenses/ and are
// registered with Flutter's LicenseRegistry in main.dart).
//
// TextStyleSpec.fontFamily stores the FAMILY string (null = app default), so
// removing an entry here only removes it from the picker — templates that
// already reference a removed family keep the string and fall back to the
// default font at render time, which is Flutter's built-in behaviour for
// unknown families. To fully drop a font: remove it here, from pubspec, and
// delete the asset.

class FontChoice {
  /// pubspec family name — the value stored in TextStyleSpec.fontFamily.
  final String family;

  /// Short flavour note shown next to the name in the picker.
  final String note;

  const FontChoice(this.family, this.note);
}

const List<FontChoice> kFontCatalog = [
  // Display / fantasy
  FontChoice('Cinzel', 'roman capitals'),
  FontChoice('Uncial Antiqua', 'celtic manuscript'),
  FontChoice('Almendra', 'fantasy serif'),
  FontChoice('Almendra SC', 'small caps'),
  // Body / readable
  FontChoice('EB Garamond', 'book serif'),
  FontChoice('Alegreya', 'warm serif'),
  FontChoice('Alegreya SC', 'small caps'),
  FontChoice('Inter', 'clean sans'),
  // Script
  FontChoice('Dancing Script', 'casual cursive'),
  FontChoice('Great Vibes', 'calligraphy'),
  // Genre
  FontChoice('VT323', 'pixel terminal'),
  FontChoice('Orbitron', 'sci-fi'),
  FontChoice('Bangers', 'comic shout'),
];
