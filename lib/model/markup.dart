// lib/model/markup.dart
//
// Inline content tokenizer. Recognises {tag} symbol references (including the
// composite forms below) and treats everything else as literal text. The rich
// text engine will extend this SAME token stream with bold/italic/size runs, so
// symbols and styling share one parser.
//
// Symbol forms (spec §3.2):
//   {R}     a single symbol            -> AtomSymbol('r')
//   {2}     an all-digit token         -> AtomSymbol('2') (rendered as a numeric
//                                          pip when no image symbol exists)
//   {A/B}   two symbols, split in one  -> SplitSymbol(a, b)
//   {2^B}   a number over a symbol     -> OverlaySymbol('2', base)
// Composites nest: each side of a split / the base of an overlay is itself a
// symbol spec.

sealed class InlineToken {
  const InlineToken();
}

class TextRun extends InlineToken {
  final String text;
  const TextRun(this.text);
}

class SymbolRun extends InlineToken {
  final SymbolSpec spec;
  const SymbolRun(this.spec);
}

/// A (possibly composite) symbol reference.
sealed class SymbolSpec {
  const SymbolSpec();
}

/// A leaf: an image-backed symbol tag, or an all-digit numeric pip.
class AtomSymbol extends SymbolSpec {
  final String token; // lower-cased, trimmed
  const AtomSymbol(this.token);
}

/// Two symbols combined into one pip, divided on the anti-diagonal
/// (top-left = [a], bottom-right = [b]).
class SplitSymbol extends SymbolSpec {
  final SymbolSpec a;
  final SymbolSpec b;
  const SplitSymbol(this.a, this.b);
}

/// A [number] drawn over a [base] symbol.
class OverlaySymbol extends SymbolSpec {
  final String number;
  final SymbolSpec base;
  const OverlaySymbol(this.number, this.base);
}

/// Parses the inside of a `{…}` into a (possibly composite) symbol spec.
SymbolSpec parseSymbol(String body) {
  final b = body.trim().toLowerCase();

  // Split: exactly two non-empty halves around a single '/'.
  if (b.contains('/')) {
    final parts = b.split('/');
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return SplitSymbol(parseSymbol(parts[0]), parseSymbol(parts[1]));
    }
  }

  // Overlay: number ^ base.
  final caret = b.indexOf('^');
  if (caret > 0 && caret < b.length - 1) {
    return OverlaySymbol(
        b.substring(0, caret).trim(), parseSymbol(b.substring(caret + 1)));
  }

  return AtomSymbol(b);
}

/// Splits [s] into literal text and symbol references. An unmatched '{' (or
/// empty braces) is kept as literal text, so stray braces never break rendering.
List<InlineToken> tokenizeInline(String s) {
  final out = <InlineToken>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isNotEmpty) {
      out.add(TextRun(buf.toString()));
      buf.clear();
    }
  }

  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == '{') {
      final close = s.indexOf('}', i + 1);
      if (close > i) {
        final body = s.substring(i + 1, close);
        if (body.trim().isNotEmpty) {
          flush();
          out.add(SymbolRun(parseSymbol(body)));
          i = close + 1;
          continue;
        }
      }
      // no closing brace / empty tag -> treat the '{' as literal
    }
    buf.write(ch);
    i++;
  }
  flush();
  return out;
}

/// The distinct image-symbol tags referenced in [s] (lower-cased), including
/// those nested inside composites. Numeric atoms are included too; callers map
/// them through the symbol table and simply skip any without an image.
Set<String> referencedTags(String s) {
  final tags = <String>{};
  void walk(SymbolSpec spec) {
    switch (spec) {
      case AtomSymbol(:final token):
        tags.add(token);
      case SplitSymbol(:final a, :final b):
        walk(a);
        walk(b);
      case OverlaySymbol(:final base):
        walk(base);
    }
  }

  for (final t in tokenizeInline(s)) {
    if (t is SymbolRun) walk(t.spec);
  }
  return tags;
}
