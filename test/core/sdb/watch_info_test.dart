import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/sdb/watch_info.dart';

void main() {
  test('the model comes from the banner, the version and name from what the watch tells', () {
    const output =
        '\t<key name="tizen.org/feature/platform.version" type="string">5.5.0.1</key>\n'
        '\t<key name="tizen.org/system/model_name" type="string">SM-R800</key>\n';
    final identity = identityFrom('device::SM-R800::0', output);
    expect(identity.banner, 'device::SM-R800::0');
    expect(identity.model, 'SM-R800');
    expect(identity.tizenVersion, '5.5');
    expect(identity.name, 'Galaxy Watch 46 mm');
  });

  test('without a model in the banner the system information gives it; unknown models have no name', () {
    const output = '<key name="tizen.org/system/model_name" type="string">SM-R999</key>';
    final identity = identityFrom('device::unknown::0', output);
    expect(identity.model, 'SM-R999');
    expect(identity.name, isNull);
    expect(identity.tizenVersion, isNull);
  });

  test('nothing useful gives nulls', () {
    final identity = identityFrom('host::', 'grep: /etc/config/model-config.xml: Permission denied');
    expect([identity.model, identity.tizenVersion, identity.name], [null, null, null]);
    expect(identityFrom('device::<script>::0', '').model, isNull);
  });

  test('battery and storage are read from the status output', () {
    const output =
        'capacity=87\n'
        'status=Charging\n'
        'Filesystem           1K-blocks      Used Available Use% Mounted on\n'
        '/dev/mmcblk0p20        1998672    912340   1086332  46% /opt/usr\n';
    final status = statusFrom(output);
    expect(status.batteryPercent, 87);
    expect(status.charging, isTrue);
    expect(status.storageTotalBytes, 1998672 * 1024);
    expect(status.storageFreeBytes, 1086332 * 1024);
  });

  test('a long file system name that pushes the numbers onto the next line is understood', () {
    const output =
        'capacity=5\r\nstatus=Discharging\r\n'
        'Filesystem           1K-blocks      Used Available Use% Mounted on\r\n'
        '/dev/disk/by-partlabel/user-data-with-a-long-name\r\n'
        '                       2000000   1000000   1000000  50% /opt/usr\r\n';
    final status = statusFrom(output);
    expect(status.batteryPercent, 5);
    expect(status.charging, isFalse);
    expect(status.storageTotalBytes, 2000000 * 1024);
    expect(status.storageFreeBytes, 1000000 * 1024);
  });

  test('anything unexpected is left out rather than guessed', () {
    for (final output in [
      '',
      'capacity=\nstatus=\n',
      'capacity=250\nstatus=Exploding\nFilesystem 1K-blocks Used Available\n/dev/x 10 20 30 /opt/usr\n',
      'capacity=-1\nsh: df: not found\n',
      'capacity=50%\nFilesystem\n/dev/x a b c\n',
    ]) {
      final status = statusFrom(output);
      expect(
        [status.batteryPercent, status.charging, status.storageFreeBytes, status.storageTotalBytes],
        [null, null, null, null],
        reason: output,
      );
    }
    expect(statusFrom('status=Full').charging, isTrue);
    expect(statusFrom('status=Not charging').charging, isFalse);
  });
}
