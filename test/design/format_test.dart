import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/design/format.dart';

void main() {
  final now = DateTime(2026, 10, 26, 18, 0);

  test('dates read like people say them', () {
    expect(formatWhen(DateTime(2026, 10, 26, 11, 47), now: now), 'Today, 11:47');
    expect(formatWhen(DateTime(2026, 10, 25, 8, 5), now: now), 'Yesterday, 08:05');
    expect(formatWhen(DateTime(2026, 3, 2, 9, 0), now: now), '2 Mar, 09:00');
    expect(formatWhen(DateTime(2025, 12, 31, 23, 59), now: now), '31 Dec 2025');
  });

  test('sizes use the unit that keeps the number short', () {
    expect(formatBytes(1717986918), '1.6 GB');
    expect(formatBytes(12 * 1024 * 1024 * 1024), '12 GB');
    expect(formatBytes(860 * 1024 * 1024), '860 MB');
    expect(formatBytes(1500), '2 KB');
    expect(formatBytes(10), '1 KB');
  });

  test('counts and lists of names', () {
    expect(count(1, 'face'), '1 face');
    expect(count(9, 'face'), '9 faces');
    expect(count(2, 'app or face', 'apps and faces'), '2 apps and faces');
    expect(listNames(['GS Hybrid 7']), 'GS Hybrid 7');
    expect(listNames(['GS Hybrid 7', 'MD210']), 'GS Hybrid 7 and MD210');
    expect(listNames(['A', 'B', 'C', 'D']), 'A, B and 2 more');
  });
}
