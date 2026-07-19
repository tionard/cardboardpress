// lib/model/template_share.dart
//
// Shareable single-template JSON — export/import so users can trade templates.
//
// The payload's `spec` is the EXACT serialization.dart encoding of
// TemplateData (the same JSON the DB's spec column stores), wrapped in a small
// envelope: a format marker (so a random .json is rejected with a friendly
// message), a format version (gate against files from a newer app), the
// template's display name, and an export timestamp. Because import decodes
// through templateFromJson, every legacy fixup runs and future template fields
// flow through with zero changes here.
//
// Images are deliberately NOT included (they live in the ImageStore, not the
// spec): imported templates render missing sprites/backgrounds as placeholders
// or skip them. Two things still travel intact by architecture: ColorRefs
// carry snapshots, and border aspects carry full frame SNAPSHOTS — so
// templates built on the SEEDED frames (whose sprites ship with every install)
// look complete on arrival.

import 'dart:convert';

import 'card_model.dart';
import 'serialization.dart';

const _kFormat = 'cardboardpress-template';
const _kFormatVersion = 1;

/// A decoded template share: display name + the layout.
class TemplateShare {
  final String name;
  final TemplateData data;
  const TemplateShare({required this.name, required this.data});
}

/// Encode one template for sharing (pretty-printed for humans and diffs).
String templateShareToJson(String name, TemplateData data) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': _kFormat,
      'version': _kFormatVersion,
      'name': name,
      'exported': DateTime.now().toIso8601String(),
      'spec': jsonDecode(templateToJson(data)),
    });

/// Decode a shared template. Throws [FormatException] with a user-showable
/// message on anything that isn't a valid CardboardPress template export.
TemplateShare templateShareFromJson(String src) {
  Object? root;
  try {
    root = jsonDecode(src);
  } catch (_) {
    throw const FormatException("This file isn't valid JSON.");
  }
  if (root is! Map<String, dynamic> || root['format'] != _kFormat) {
    throw const FormatException(
        "This file isn't a CardboardPress template export.");
  }
  final version = root['version'];
  if (version is! int || version > _kFormatVersion) {
    throw const FormatException(
        'This template was exported by a newer version of CardboardPress — '
        'update the app to import it.');
  }
  final spec = root['spec'];
  if (spec is! Map<String, dynamic>) {
    throw const FormatException(
        'This template file is incomplete (missing its layout data).');
  }
  final TemplateData data;
  try {
    // Round-trip through the canonical decoder: legacy fixups included.
    data = templateFromJson(jsonEncode(spec));
  } catch (_) {
    throw const FormatException(
        "This template file couldn't be read — it may be corrupted.");
  }
  final name = (root['name'] is String) ? (root['name'] as String).trim() : '';
  return TemplateShare(
      name: name.isEmpty ? 'Imported template' : name, data: data);
}
