import '../api.dart';
import '../util/text.dart';

/// Reads the output of `pkgcmd -i` and `pkgcmd -u` line by line. Success is `key[end] val[ok]`; a failure shows as
/// `key[error] val[<code>]`, `key[end] val[fail]` or `processing result : <text> [<code>] failed`. The installer's own
/// reason, when it gives one, follows the code on the error line: `key[error] val[-12] error message: :<reason>`.
class PkgcmdOutput {
  bool _endOk = false;
  bool _failed = false;
  int? _code;
  String? _message;
  String? _detail;

  static final RegExp _percent = RegExp(r'key\[install_percent] val\[(\d+)]');
  static final RegExp _end = RegExp(r'key\[end] val\[(ok|fail)]');
  static final RegExp _error = RegExp(r'key\[error] val\[(-?\d+)](?: error message: (.*))?');
  static final RegExp _result = RegExp(r'processing result : (.*?) \[(-?\d+)] failed');

  /// The colon pkgcmd leaves before the reason, and the certificate check's own number after it (`:<-6>`).
  static final RegExp _leadingColons = RegExp(r'^[\s:]+');
  static final RegExp _checkNumber = RegExp(r':\s*<-?\d+>\s*$');

  /// Feeds one line; returns the install percentage when the line carries one.
  int? feed(String line) {
    final percent = _percent.firstMatch(line);
    if (percent != null) return int.tryParse(percent.group(1)!)?.clamp(0, 100);
    final end = _end.firstMatch(line);
    if (end != null) {
      if (end.group(1) == 'ok') {
        _endOk = true;
      } else {
        _failed = true;
      }
    }
    final error = _error.firstMatch(line);
    if (error != null) {
      _code = int.tryParse(error.group(1)!) ?? _code;
      if (error.group(2) case final reason?) {
        _detail =
            cleanLine(reason.trim().replaceFirst(_leadingColons, '').replaceFirst(_checkNumber, ''), 300) ?? _detail;
      }
    }
    final result = _result.firstMatch(line);
    if (result != null) {
      _failed = true;
      _message = cleanLine(result.group(1)!, 300);
      _code = int.tryParse(result.group(2)!) ?? _code;
    }
    return null;
  }

  InstallResult result() {
    if (_failed) return InstallResult(success: false, code: _code?.toString(), message: _message, detail: _detail);
    if (_endOk) return const InstallResult(success: true);
    return InstallResult(
      success: false,
      code: _code?.toString(),
      message: _message ?? 'pkgcmd gave no result',
      detail: _detail,
    );
  }
}
