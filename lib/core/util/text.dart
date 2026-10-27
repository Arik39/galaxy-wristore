/// Small helpers for untrusted text: names from the catalog, the watch and backup files.
library;

/// Whether [code] is an ISO control character (U+0000 to U+001F and U+007F to U+009F), as Java's
/// `Character.isISOControl` has it.
bool isIsoControl(int code) => code <= 0x1f || (code >= 0x7f && code <= 0x9f);

/// Whether [text] holds an ISO control character.
bool hasIsoControl(String text) => text.codeUnits.any(isIsoControl);

/// The first [max] characters of [text], counted in code points so that no surrogate pair is cut in half.
String takeRunes(String text, int max) {
  if (text.length <= max) return text;
  final runes = text.runes;
  return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
}

/// Text for one line of a screen: without control characters, trimmed, at most [max] characters; null when nothing
/// is left.
String? cleanLine(String text, int max) {
  final kept = String.fromCharCodes(text.runes.where((code) => !isIsoControl(code))).trim();
  final line = takeRunes(kept, max);
  return line.isEmpty ? null : line;
}

/// Like [cleanLine], keeping line breaks: for descriptions.
String? cleanParagraphs(String text, int max) {
  final kept = String.fromCharCodes(text.runes.where((code) => code == 0x0a || !isIsoControl(code))).trim();
  final paragraphs = takeRunes(kept, max);
  return paragraphs.isEmpty ? null : paragraphs;
}
