/// What the watch tells about itself over the debugging shell: its model and Tizen version, its battery and storage.
///
/// The commands here are read-only and best effort, and have not yet been tried on a watch: every value that does not
/// come back as expected is left out (null) rather than guessed.
library;

import '../api.dart';

/// Prints the Tizen version and model lines of the watch's system information.
const String identityCommand =
    r'''grep -h -e 'platform.version"' -e 'model_name"' /etc/config/model-config.xml 2>/dev/null''';

/// Prints `capacity=<percent>`, `status=<charging state>` and what `df` reports for the user data partition.
const String statusCommand =
    r'echo "capacity=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"; '
    r'echo "status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)"; '
    'df -k /opt/usr 2>/dev/null';

final RegExp _modelPattern = RegExp(r'^SM-[A-Z][0-9A-Z]{3,10}$');
final RegExp _version = RegExp(r'tizen\.org/feature/platform\.version"[^>]*>\s*(\d{1,3}(?:\.\d{1,3}){0,3})\s*<');
final RegExp _modelName = RegExp(r'tizen\.org/system/model_name"[^>]*>\s*([^<\s]{1,32})\s*<');

/// The names Samsung sold its Tizen watches under, by the start of the model number.
const Map<String, String> _names = {
  'SM-R720': 'Gear S2',
  'SM-R732': 'Gear S2 classic',
  'SM-R600': 'Gear Sport',
  'SM-R760': 'Gear S3 frontier',
  'SM-R765': 'Gear S3 frontier LTE',
  'SM-R770': 'Gear S3 classic',
  'SM-R775': 'Gear S3 classic LTE',
  'SM-R800': 'Galaxy Watch 46 mm',
  'SM-R805': 'Galaxy Watch 46 mm LTE',
  'SM-R810': 'Galaxy Watch 42 mm',
  'SM-R815': 'Galaxy Watch 42 mm LTE',
  'SM-R500': 'Galaxy Watch Active',
  'SM-R820': 'Galaxy Watch Active2 44 mm',
  'SM-R825': 'Galaxy Watch Active2 44 mm LTE',
  'SM-R830': 'Galaxy Watch Active2 40 mm',
  'SM-R835': 'Galaxy Watch Active2 40 mm LTE',
  'SM-R840': 'Galaxy Watch3 45 mm',
  'SM-R845': 'Galaxy Watch3 45 mm LTE',
  'SM-R850': 'Galaxy Watch3 41 mm',
  'SM-R855': 'Galaxy Watch3 41 mm LTE',
};

/// The watch's identity from its connection [banner] (`device::SM-R800::0`) and what [identityCommand] printed.
WatchIdentity identityFrom(String banner, String identityOutput) {
  final parts = banner.split('::');
  final fromBanner = parts.length >= 2 && _modelPattern.hasMatch(parts[1]) ? parts[1] : null;
  final fromSystem = _modelName.firstMatch(identityOutput)?.group(1);
  final model = fromBanner ?? (fromSystem != null && _modelPattern.hasMatch(fromSystem) ? fromSystem : null);
  final version = _version.firstMatch(identityOutput)?.group(1)?.split('.');
  return WatchIdentity(
    banner: banner,
    model: model,
    tizenVersion: version?.take(2).join('.'),
    name: model == null || model.length < 7 ? null : _names[model.substring(0, 7)],
  );
}

/// Battery and storage from what [statusCommand] printed.
WatchStatus statusFrom(String output) {
  int? battery;
  bool? charging;
  int? free;
  int? total;
  final lines = output.split('\n').map((line) => line.trim()).toList();
  for (final line in lines) {
    if (line.startsWith('capacity=')) {
      final value = int.tryParse(line.substring('capacity='.length).trim());
      if (value != null && value >= 0 && value <= 100) battery = value;
    } else if (line.startsWith('status=')) {
      charging = switch (line.substring('status='.length).trim().toLowerCase()) {
        'charging' || 'full' => true,
        'discharging' || 'not charging' => false,
        _ => null,
      };
    }
  }
  // `df` prints a header, then the file system's name, its size, what is used and what is available, in KiB; a
  // long name may push the numbers onto a line of their own
  final header = lines.indexWhere((line) => line.startsWith('Filesystem'));
  if (header >= 0) {
    final words = lines.skip(header + 1).join(' ').split(RegExp(r'\s+'));
    for (var i = 0; i + 2 < words.length; i++) {
      final size = _kib(words[i]);
      final used = _kib(words[i + 1]);
      final available = _kib(words[i + 2]);
      if (size == null || used == null || available == null) continue;
      if (used <= size && available <= size) {
        total = size * 1024;
        free = available * 1024;
      }
      break;
    }
  }
  return WatchStatus(batteryPercent: battery, charging: charging, storageFreeBytes: free, storageTotalBytes: total);
}

/// A count of KiB as `df` prints it; null for anything else, including numbers too large for any watch.
int? _kib(String word) => RegExp(r'^\d{1,15}$').hasMatch(word) ? int.parse(word) : null;
