/// Orders Tizen package versions such as "1.0.5" and "1.0.10": numbers by value, other parts as text.
abstract final class VersionCompare {
  /// Negative when [a] is older than [b], zero when they are the same version, positive when [a] is newer. Missing
  /// parts count as zero ("1.0" equals "1.0.0"); a leading `v` and the kind of separators do not matter.
  static int compare(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    for (var i = 0; i < left.length || i < right.length; i++) {
      final x = i < left.length ? left[i] : null;
      final y = i < right.length ? right[i] : null;
      final int result;
      if (x == null) {
        result = _number(y!) == 0 ? 0 : -1;
      } else if (y == null) {
        result = _number(x) == 0 ? 0 : 1;
      } else {
        final nx = _number(x);
        final ny = _number(y);
        result = nx != null && ny != null ? nx.compareTo(ny) : x.toLowerCase().compareTo(y.toLowerCase());
      }
      if (result != 0) return result;
    }
    return 0;
  }

  static bool isNewer(String candidate, String installed) => compare(candidate, installed) > 0;

  static List<String> _parts(String version) => version
      .trim()
      .replaceFirst(RegExp('^[vV]+'), '')
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList();

  /// The value of a part made of digits only (not too many for an int); null for any other part.
  static int? _number(String part) => RegExp(r'^\d{1,18}$').hasMatch(part) ? int.parse(part) : null;
}
