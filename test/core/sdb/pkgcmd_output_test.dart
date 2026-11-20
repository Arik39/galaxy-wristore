import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/sdb/pkgcmd_output.dart';

/// The sample lines were captured from `pkgcmd` on a Galaxy Watch (SM-R800, Tizen 5.5).
(InstallResult, List<int>) _parse(String text) {
  final output = PkgcmdOutput();
  final percents = [for (final line in text.split('\n')) ?output.feed(line)];
  return (output.result(), percents);
}

void main() {
  test('a successful install reports growing percentages and ok', () {
    const text = '''path is /home/owner/share/tmp/sdk_tools/spike-install.wgt
__return_cb req_id[1] pkg_type[wgt] pkgid[55V5m8QGTw] key[start] val[install]
__return_cb req_id[1] pkg_type[wgt] pkgid[55V5m8QGTw] key[install_percent] val[11]
__return_cb req_id[1] pkg_type[wgt] pkgid[55V5m8QGTw] key[install_percent] val[55]
__return_cb req_id[1] pkg_type[wgt] pkgid[55V5m8QGTw] key[install_percent] val[100]
__return_cb req_id[1] pkg_type[wgt] pkgid[55V5m8QGTw] key[end] val[ok]
spend time for pkgcmd is [4514]ms''';
    final (result, percents) = _parse(text);
    expect(result.success, isTrue);
    expect(percents, [11, 55, 100]);
  });

  test('a broken package gives code -24 and the text from the watch', () {
    const text = '''__return_cb req_id[1] pkg_type[wgt] pkgid[] key[error] val[-24]
__return_cb req_id[1] pkg_type[wgt] pkgid[] key[end] val[fail]
processing result : Image error [-24] failed
spend time for pkgcmd is [16648]ms''';
    final (result, _) = _parse(text);
    expect(result.success, isFalse);
    expect(result.code, '-24');
    expect(result.message, 'Image error');
    expect(result.detail, isNull);
    expect(result.reason, 'Image error (-24)');
  });

  // Built from the format in Tizen 4.0 and 5.5's pkg_cmd.c and app-installers, not captured from a watch: the
  // installer sends "<code>:<reason>" and pkgcmd prints it from the colon on.
  test('the installer\'s own reason comes from the error line', () {
    const text = '''__return_cb req_id[1] pkg_type[tpk] pkgid[com.example.face] key[start] val[install]
__return_cb req_id[1] pkg_type[tpk] pkgid[com.example.face] key[error] val[-12] error message: :Invalid certificate chain with certificate in signature.:<-6>\r
__return_cb req_id[1] pkg_type[tpk] pkgid[com.example.face] key[end] val[fail]
processing result : Check certificate error [-12] failed
spend time for pkgcmd is [2210]ms''';
    final (result, _) = _parse(text);
    expect(result.success, isFalse);
    expect(result.code, '-12');
    expect(result.message, 'Check certificate error');
    expect(result.detail, 'Invalid certificate chain with certificate in signature.');
    expect(result.reason, 'Check certificate error (-12): Invalid certificate chain with certificate in signature');
  });

  test('a reason without the certificate check\'s number is kept whole', () {
    final (result, _) = _parse(
      'key[error] val[-12] error message: :Package with the same id and different certificate has been already '
      'installed\nkey[end] val[fail]',
    );
    expect(result.code, '-12');
    expect(result.message, isNull);
    expect(result.detail, 'Package with the same id and different certificate has been already installed');
    expect(result.reason, 'code -12: Package with the same id and different certificate has been already installed');
  });

  test('an empty reason and the watch\'s control characters are dropped', () {
    expect(_parse('key[error] val[-27] error message: :\nkey[end] val[fail]').$1.detail, isNull);
    final (result, _) = _parse('key[error] val[-1] error message: :Bad\u0007 thing${' x' * 500}\nkey[end] val[fail]');
    expect(result.detail, startsWith('Bad thing x x'));
    expect(result.detail!.length, 300);
  });

  test('a missing file gives code -5', () {
    final (result, _) = _parse('processing result : Package not found [-5] failed\nspend time for pkgcmd is [57]ms');
    expect(result.success, isFalse);
    expect(result.code, '-5');
    expect(result.message, 'Package not found');
  });

  test('removing a package that is not installed gives code -999', () {
    final (result, _) = _parse(
      'Undefined error(-1)processing result : Undefined Error [-999] failed\nspend time for pkgcmd is [258]ms',
    );
    expect(result.success, isFalse);
    expect(result.code, '-999');
  });

  test('a successful removal is ok', () {
    final (result, percents) = _parse(
      '__return_cb req_id[1] pkg_type[wgt] pkgid[55V5m8QGTw] key[end] val[ok]\nspend time for pkgcmd is [2135]ms',
    );
    expect(result.success, isTrue);
    expect(percents, isEmpty);
  });

  test('no output at all is a failure, not a success', () {
    final (result, _) = _parse('');
    expect(result.success, isFalse);
    expect(result.code, isNull);
    expect(result.message, 'pkgcmd gave no result');
  });

  test('ok followed by a failure message is a failure', () {
    final (result, _) = _parse('key[end] val[ok]\nprocessing result : Something [-3] failed');
    expect(result.success, isFalse);
    expect(result.code, '-3');
  });

  test('percentages are limited to 0 to 100', () {
    final output = PkgcmdOutput();
    expect(output.feed('key[install_percent] val[250]'), 100);
    expect(output.feed('key[install_percent] val[0]'), 0);
    expect(output.feed('key[install_percent] val[x]'), isNull);
    expect(output.feed('key[install_percent] val[99999999999999999999]'), isNull);
  });

  test('the watch\'s words are kept to one plain line', () {
    final (result, _) = _parse('processing result : Bad\u0007 thing${' x' * 500} [-1] failed');
    expect(result.message, startsWith('Bad thing x x'));
    expect(result.message!.length, 300);
  });

  group('reason', () {
    test('names the outcome with its code', () {
      expect(const InstallResult(success: false, message: 'Image error', code: '-24').reason, 'Image error (-24)');
      expect(const InstallResult(success: false, code: '-27').reason, 'code -27');
      expect(const InstallResult(success: false, message: 'pkgcmd gave no result').reason, 'pkgcmd gave no result');
      expect(const InstallResult(success: false).reason, 'no reason given');
    });

    test('adds the installer\'s reason unless it only repeats the name', () {
      const signed = InstallResult(success: false, message: 'Signature error', code: '-14', detail: 'Unsigned app.');
      expect(signed.reason, 'Signature error (-14): Unsigned app');
      const same = InstallResult(success: false, message: 'Image error', code: '-24', detail: 'image error.');
      expect(same.reason, 'Image error (-24)');
      expect(const InstallResult(success: false, detail: 'Out of space').reason, 'Out of space');
    });

    test('never ends in a full stop, so a sentence can close it', () {
      const result = InstallResult(success: false, message: 'Error.', code: '-1', detail: 'It failed. ');
      expect(result.reason, 'Error. (-1): It failed');
    });
  });
}
