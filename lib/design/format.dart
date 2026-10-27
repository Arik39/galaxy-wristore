/// Plain-language dates and sizes for the screens.
library;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int v) => v.toString().padLeft(2, '0');

/// "Today, 11:47", "Yesterday, 18:02", "26 Oct, 11:47", or with the year when it is not this year.
String formatWhen(DateTime when, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final time = '${_two(when.hour)}:${_two(when.minute)}';
  final day = DateTime(when.year, when.month, when.day);
  final days = DateTime(today.year, today.month, today.day).difference(day).inDays;
  if (days == 0) return 'Today, $time';
  if (days == 1) return 'Yesterday, $time';
  final date = '${when.day} ${_months[when.month - 1]}';
  return when.year == today.year ? '$date, $time' : '$date ${when.year}';
}

/// "1.6 GB", "820 MB", "12 KB".
String formatBytes(int bytes) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 0 : 1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
  return '${(bytes / kb).ceil().clamp(1, 1023)} KB';
}

/// "1 face", "9 faces".
String count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// "GS Hybrid 7", "GS Hybrid 7 and MD210", "GS Hybrid 7, MD210 and 3 more".
String listNames(List<String> names, {int max = 2}) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length <= max) return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  return '${names.take(max).join(', ')} and ${names.length - max} more';
}
