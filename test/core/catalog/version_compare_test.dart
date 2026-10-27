import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/catalog/version_compare.dart';

void main() {
  test('numbers are compared by value', () {
    expect(VersionCompare.isNewer('1.0.10', '1.0.5'), isTrue);
    expect(VersionCompare.isNewer('1.0.5', '1.0.10'), isFalse);
    expect(VersionCompare.isNewer('2.0', '1.9.9'), isTrue);
  });

  test('equal versions and trailing zeros are not newer', () {
    expect(VersionCompare.compare('1.0', '1.0.0'), 0);
    expect(VersionCompare.isNewer('1.0.0', '1.0'), isFalse);
    expect(VersionCompare.isNewer('1.0.1', '1.0'), isTrue);
  });

  test('a leading v and other separators are ignored', () {
    expect(VersionCompare.compare('v1.2.3', '1-2-3'), 0);
    expect(VersionCompare.isNewer('1.2.4', 'v1.2.3'), isTrue);
  });

  test('text parts fall back to text order, ignoring case', () {
    expect(VersionCompare.compare('1.0.beta', '1.0.alpha'), greaterThan(0));
    expect(VersionCompare.compare('1.0.Beta', '1.0.beta'), 0);
    // Not hexadecimal, and not too large for a number to break the order
    expect(VersionCompare.compare('1.0x10', '1.0x9'), lessThan(0));
    expect(VersionCompare.compare('1.${'9' * 30}', '1.2'), greaterThan(0));
  });
}
