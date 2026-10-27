import 'dart:convert';
import 'dart:typed_data';

/// Decodes Base64 the way a MIME decoder does: line breaks and any other characters outside the alphabet are skipped,
/// and missing padding is added. [FormatException] when what is left is not Base64.
Uint8List decodeMimeBase64(String text) =>
    base64.decode(base64.normalize(text.replaceAll(RegExp('[^A-Za-z0-9+/=]'), '')));
