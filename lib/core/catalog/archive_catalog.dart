import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api.dart';
import '../util/hashing.dart';
import '../util/text.dart';

/// Package ids and versions end up in URLs and file names, so only a narrow alphabet is accepted: letters, digits,
/// `.`, `_`, `-` and `+`, at most 128 of them, and not only dots (a URL would read those as a step up).
bool isCatalogIdentifier(String value) =>
    RegExp(r'^[A-Za-z0-9._+-]{1,128}$').hasMatch(value) && value.replaceAll('.', '').isNotEmpty;

/// Tizen Archive's REST API at [baseUrl], which nothing a user, a link or a response supplies can change: only paths
/// on the catalog itself are followed, never an absolute URL from a response, and redirects are not followed either.
///
/// Every failure is a [CatalogException]; ids and versions Tizen Archive cannot have are one with status 404, sent
/// nowhere. Everything in a response is untrusted: sizes are bounded and the text shown is cleaned.
class ArchiveCatalog implements CatalogApi {
  ArchiveCatalog({http.Client? client, this.userAgent = defaultUserAgent}) : _client = client ?? http.Client();

  static const String baseUrl = 'https://tizen-archive.com';
  static const String defaultUserAgent = 'galaxy-wristore/1.0.0';

  final String userAgent;
  final http.Client _client;

  static const Duration _answerTimeout = Duration(seconds: 30);
  static const Duration _readTimeout = Duration(seconds: 30);
  static const int _maxJsonBytes = 5 * 1024 * 1024;
  static const int _maxArtifactBytes = 512 * 1024 * 1024;
  static const int _maxIconBytes = 512 * 1024;
  static const int _maxQuery = 100;
  static const int _maxPageItems = 100;
  static const int _maxName = 80;
  static const int _maxDescription = 4000;
  static const int _maxVersions = 50;
  static final RegExp _iconPath = RegExp(r'^/api/icons/[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');

  @override
  Future<CatalogPage> search({String query = '', CatalogKind? kind, bool installableOnly = true, int page = 1}) async {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Pages count from 1');
    final text = takeRunes(query.trim(), _maxQuery);
    final json = await _getJson('/api/catalog', [
      if (text.isNotEmpty) ('q', text),
      if (kind != null) ('kind', kind == CatalogKind.watchFace ? 'watchface' : 'app'),
      if (installableOnly) ('installable', 'true'),
      ('page', '$page'),
    ]);
    return _parse(() {
      final items = [
        for (final item in _list(json, 'items').take(_maxPageItems).map(_object))
          if (isCatalogIdentifier(_string(item, 'packageId')))
            CatalogEntry(
              id: _string(item, 'packageId'),
              name: _line(item, 'name') ?? _string(item, 'packageId'),
              kind: switch (_optionalString(item, 'kind')) {
                'watchface' => CatalogKind.watchFace,
                'app' => CatalogKind.app,
                _ => null,
              },
              iconPath: _icon(item),
              verdict: _verdict(item['verdict']),
              latestVersion: _identifier(item, 'latestVersion'),
            ),
      ];
      final pages = _optionalInt(json, 'pages') ?? 1;
      final total = _optionalInt(json, 'total');
      // The page asked for wins over what the answer claims, so "more" always moves on
      return CatalogPage(
        items: items,
        page: page,
        hasMore: page < pages,
        total: total == null || total < 0 ? null : total,
      );
    });
  }

  @override
  Future<PackageDetails> details(String packageId) async {
    _checkIdentifier(packageId, 'package id');
    final json = await _getJson('/api/packages/$packageId');
    return _parse(() {
      final description = _optionalString(json, 'description');
      return PackageDetails(
        id: packageId,
        name: _line(json, 'name') ?? packageId,
        description: description == null ? null : cleanParagraphs(description, _maxDescription),
        authorName: _line(json, 'authorName'),
        iconPath: _icon(json),
        latestVersion: _identifier(json, 'latestVersion'),
        versions: [
          for (final version in _list(json, 'versions').map(_object))
            if (isCatalogIdentifier(_string(version, 'version')))
              VersionSummary(version: _string(version, 'version'), verdict: _verdict(version['verdict'])),
        ].take(_maxVersions).toList(),
      );
    });
  }

  /// The latest version is the one the package page names; a package without one is a [CatalogException] with
  /// status 404, as is a version Tizen Archive cannot have.
  @override
  Future<VersionInfo> version(String packageId, [String? version]) async {
    _checkIdentifier(packageId, 'package id');
    final String resolved;
    if (version != null) {
      resolved = version;
    } else {
      final package = await _getJson('/api/packages/$packageId');
      resolved =
          _parse(() => _optionalString(package, 'latestVersion')) ??
          (throw const CatalogException('The package has no published versions', statusCode: 404));
    }
    _checkIdentifier(resolved, 'version');
    final json = await _getJson('/api/packages/$packageId/versions/$resolved');
    return _parse(() {
      final id = _string(json, 'packageId');
      final number = _string(json, 'version');
      if (!isCatalogIdentifier(id) || !isCatalogIdentifier(number)) {
        throw const CatalogException('The catalog returned an unexpected identifier');
      }
      final artifacts = <Artifact>[];
      final verdicts = <Verdict>[];
      for (final build in _list(json, 'builds').map(_object)) {
        final verdict = _verdict(build['verdict']);
        verdicts.add(verdict);
        for (final artifact in _list(build, 'artifacts').map(_object)) {
          final sha256 = _string(artifact, 'sha256');
          final size = _optionalInt(artifact, 'size') ?? (throw const _BadResponse());
          if (!_sha256.hasMatch(sha256)) throw const CatalogException('The catalog returned a malformed SHA-256');
          if (size < 0) throw const CatalogException('The catalog returned a negative size');
          final url = _optionalString(artifact, 'downloadUrl');
          if (url != null) {
            artifacts.add(
              Artifact(downloadUrl: url, sha256: sha256, size: size, fileName: _fileName(artifact), verdict: verdict),
            );
          }
        }
      }
      return VersionInfo(
        id: id,
        version: number,
        name: _line(json, 'name'),
        artifacts: artifacts,
        buildVerdicts: verdicts,
      );
    });
  }

  @override
  ArtifactChoice choose(VersionInfo info) {
    for (final artifact in info.artifacts) {
      if (artifact.verdict == Verdict.installable) return ArtifactFound(artifact);
    }
    final verdicts = info.buildVerdicts.isNotEmpty ? info.buildVerdicts : [for (final a in info.artifacts) a.verdict];
    if (verdicts.contains(Verdict.installable)) return const ArtifactNone(NotInstallableReason.notDownloadable);
    return ArtifactNone(switch (verdicts.firstOrNull) {
      null => NotInstallableReason.noBuilds,
      Verdict.deviceBound => NotInstallableReason.deviceBound,
      Verdict.expired => NotInstallableReason.expired,
      Verdict.notInstallable => NotInstallableReason.rejectedByWatch,
      _ => NotInstallableReason.unverified,
    });
  }

  @override
  Future<Uint8List> icon(String path) async {
    if (!_isIconPath(path)) throw const CatalogException('The catalog returned an unexpected icon URL');
    return _readAll(await _open(path), _maxIconBytes, 'The icon is too large');
  }

  @override
  Future<void> download(Artifact artifact, File target, {void Function(int received)? onProgress}) async {
    if (artifact.size > _maxArtifactBytes) throw const CatalogException('The package is too large');
    IOSink? sink;
    try {
      final response = await _open(artifact.downloadUrl);
      final output = sink = target.openWrite();
      final digest = Sha256Builder();
      var total = 0;
      final chunks = StreamIterator(response.stream.timeout(_readTimeout));
      try {
        while (await chunks.moveNext()) {
          total += chunks.current.length;
          // More than announced is a mismatch, found out without writing the rest
          if (total > artifact.size) break;
          digest.add(chunks.current);
          output.add(chunks.current);
          onProgress?.call(total);
        }
      } finally {
        await chunks.cancel();
      }
      sink = null;
      await output.close();
      if (total != artifact.size) throw CatalogException('Expected ${artifact.size} bytes, got $total');
      if (digest.finish() != artifact.sha256.toLowerCase()) throw const CatalogException('SHA-256 mismatch');
    } catch (error) {
      await sink?.close().catchError((Object _) {});
      if (await target.exists()) await target.delete();
      if (error is CatalogException) rethrow;
      throw CatalogException(
        error is TimeoutException ? 'The catalog stopped answering' : 'The download failed: $error',
      );
    }
  }

  bool _isIconPath(String path) => _iconPath.hasMatch(path) && !path.contains('..');

  void _checkIdentifier(String value, String what) {
    if (!isCatalogIdentifier(value)) throw CatalogException('Not a $what Tizen Archive can have', statusCode: 404);
  }

  Future<Map<String, Object?>> _getJson(String path, [List<(String, String)> parameters = const []]) async {
    final bytes = await _readAll(
      await _open(path, accept: 'application/json', parameters: parameters),
      _maxJsonBytes,
      'The response is too large',
    );
    try {
      return _object(jsonDecode(utf8.decode(bytes, allowMalformed: true)));
    } on FormatException {
      throw const CatalogException('Unexpected response from the catalog');
    } on _BadResponse {
      throw const CatalogException('Unexpected response from the catalog');
    }
  }

  /// Only paths on the catalog itself are fetched; an absolute URL from a response never is.
  Future<http.StreamedResponse> _open(
    String path, {
    String? accept,
    List<(String, String)> parameters = const [],
  }) async {
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw const CatalogException('The catalog returned an unexpected URL');
    }
    final query = [for (final (key, value) in parameters) '${_encode(key)}=${_encode(value)}'].join('&');
    final Uri uri;
    try {
      uri = Uri.parse('$baseUrl$path${query.isEmpty ? '' : '?$query'}');
    } on FormatException {
      throw const CatalogException('The catalog returned an unexpected URL');
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['User-Agent'] = userAgent;
    if (accept != null) request.headers['Accept'] = accept;
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_answerTimeout);
    } on TimeoutException {
      throw const CatalogException('The catalog did not answer in time');
    } catch (error) {
      throw CatalogException('Network error: $error');
    }
    if (response.statusCode == 200) return response;
    response.stream.listen(null, onError: (Object _) {}).cancel().ignore();
    if (response.statusCode == 404) throw const CatalogException('Not found', statusCode: 404);
    throw CatalogException('The catalog answered HTTP ${response.statusCode}', statusCode: response.statusCode);
  }

  Future<Uint8List> _readAll(http.StreamedResponse response, int maxBytes, String tooLarge) async {
    final bytes = BytesBuilder(copy: false);
    final chunks = StreamIterator(response.stream.timeout(_readTimeout));
    try {
      while (await chunks.moveNext()) {
        bytes.add(chunks.current);
        if (bytes.length > maxBytes) throw CatalogException(tooLarge);
      }
    } on CatalogException {
      rethrow;
    } on TimeoutException {
      throw const CatalogException('The catalog stopped answering');
    } catch (error) {
      throw CatalogException('Network error: $error');
    } finally {
      await chunks.cancel();
    }
    return bytes.takeBytes();
  }

  /// Percent-encoding for a query value, spaces as `%20`.
  static String _encode(String value) => Uri.encodeQueryComponent(value).replaceAll('+', '%20');

  static T _parse<T>(T Function() build) {
    try {
      return build();
    } on _BadResponse {
      throw const CatalogException('Unexpected response from the catalog');
    }
  }

  static Map<String, Object?> _object(Object? value) =>
      value is Map<String, Object?> ? value : throw const _BadResponse();

  static List<Object?> _list(Map<String, Object?> json, String key) => switch (json[key]) {
    null => const [],
    final List<Object?> list => list,
    _ => throw const _BadResponse(),
  };

  static String _string(Map<String, Object?> json, String key) =>
      _optionalString(json, key) ?? (throw const _BadResponse());

  static String? _optionalString(Map<String, Object?> json, String key) => switch (json[key]) {
    null => null,
    final String text => text,
    _ => throw const _BadResponse(),
  };

  static int? _optionalInt(Map<String, Object?> json, String key) => switch (json[key]) {
    null => null,
    final int number => number,
    _ => throw const _BadResponse(),
  };

  /// One line of text for the screen.
  static String? _line(Map<String, Object?> json, String key) {
    final text = _optionalString(json, key);
    return text == null ? null : cleanLine(text, _maxName);
  }

  /// A package id or version, dropped when it is not one Tizen Archive can have.
  static String? _identifier(Map<String, Object?> json, String key) {
    final text = _optionalString(json, key);
    return text != null && isCatalogIdentifier(text) ? text : null;
  }

  /// A file name to save a download under: one plain name, no path.
  static String? _fileName(Map<String, Object?> json) {
    final name = _optionalString(json, 'fileName');
    final line = name == null ? null : cleanLine(name, 128);
    return line == null || line.contains('/') || line.contains(r'\') || line.startsWith('.') ? null : line;
  }

  String? _icon(Map<String, Object?> json) {
    final path = _optionalString(json, 'iconUrl');
    return path != null && _isIconPath(path) ? path : null;
  }

  /// Any value this app does not know is [Verdict.unknown].
  static Verdict _verdict(Object? value) => switch (value) {
    'installable' => Verdict.installable,
    'device-bound' => Verdict.deviceBound,
    'expired' => Verdict.expired,
    'not-installable' => Verdict.notInstallable,
    'unverified' => Verdict.unverified,
    _ => Verdict.unknown,
  };
}

/// A response of the wrong shape, turned into a [CatalogException] where it is caught.
class _BadResponse implements Exception {
  const _BadResponse();
}
