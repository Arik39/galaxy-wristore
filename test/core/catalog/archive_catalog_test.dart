import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galaxy_wristore/core/api.dart';
import 'package:galaxy_wristore/core/catalog/archive_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Matcher _catalogFails([int? statusCode]) =>
    throwsA(isA<CatalogException>().having((e) => e.statusCode, 'statusCode', statusCode));

void main() {
  final file = Uint8List.fromList(List.generate(200000, (i) => i * 7));
  final sha = sha256.convert(file).toString();
  late Uint8List served;
  late List<http.BaseRequest> requests;
  late Directory dir;

  const listing = r'''{"items":[
    {"packageId":"Dice","name":"Dice\u0007 Face","kind":"watchface","type":"wgt","latestVersion":"1.0.2","verdict":"installable","iconUrl":"/api/icons/ab12.png","signatureClass":"store-public"},
    {"packageId":"../etc","name":"Bad id","verdict":"installable"},
    {"packageId":"Clock","name":"Clock","kind":"app","type":"tpk","latestVersion":"2 0","verdict":"something-new","iconUrl":"http://evil.example/i.png"},
    {"packageId":"Nameless","kind":"widget"}
    ],"page":7,"perPage":24,"total":27,"pages":2}''';

  String version(String sha, int size) =>
      '''{"packageId":"Dice","version":"1.0.2","name":"Dice","type":"wgt","extra":1,"builds":[
    {"verdict":"installable","artifacts":[
      {"sha256":"$sha","size":$size,"fileName":"Dice_1.0.2.wgt","downloadUrl":"/api/artifacts/$sha/download"},
      {"sha256":"$sha","size":$size,"downloadUrl":null}]},
    {"verdict":"something-new","artifacts":[]}]}''';

  http.Response json(String body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'application/json'});

  ArchiveCatalog catalog({Map<String, http.Response Function()> extra = const {}}) => ArchiveCatalog(
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (extra[path] case final answer?) return answer();
      if (path == '/api/artifacts/$sha/download') return http.Response.bytes(served, 200);
      return switch (path) {
        '/api/packages/Dice' => json('{"latestVersion":"1.0.2"}'),
        '/api/packages/Dice/versions/1.0.2' => json(version(sha, file.length)),
        '/api/catalog' => json(listing),
        '/api/packages/Face' => json(
          r'''{"packageId":"Face","name":"Gold\u0000 Face","description":"Line one\nLine\u0007 two",
              "authorName":" Ann ","latestVersion":"1.6.3","iconUrl":"/api/icons/f.png",
              "versions":[{"version":"1.6.3","verdict":"installable"},{"version":"bad version","verdict":"installable"},
              {"version":"1.0","verdict":"expired"}],"listings":[]}''',
        ),
        '/api/icons/ab12.png' => http.Response.bytes(List.filled(300, 1), 200),
        '/api/icons/big.png' => http.Response.bytes(Uint8List(600 * 1024), 200),
        '/api/redirect' => http.Response('', 302, headers: {'location': 'http://example.invalid/'}),
        _ => json('{}', 404),
      };
    }),
  );

  setUp(() async {
    served = file;
    requests = [];
    dir = await Directory.systemTemp.createTemp('catalog-test-');
  });
  tearDown(() => dir.delete(recursive: true));

  test('resolves the latest version over HTTPS at the fixed address and sends the user agent', () async {
    final info = await catalog().version('Dice');
    expect(info.id, 'Dice');
    expect(info.version, '1.0.2');
    expect(info.name, 'Dice');
    expect(info.buildVerdicts, [Verdict.installable, Verdict.unknown]);
    // The file without a download address is not offered
    expect(info.artifacts, hasLength(1));
    expect(info.artifacts.single.verdict, Verdict.installable);
    expect(info.artifacts.single.fileName, 'Dice_1.0.2.wgt');
    expect(info.artifacts.single.size, file.length);
    expect(requests.map((request) => request.url.toString()), [
      'https://tizen-archive.com/api/packages/Dice',
      'https://tizen-archive.com/api/packages/Dice/versions/1.0.2',
    ]);
    expect(requests.every((request) => request.headers['User-Agent'] == ArchiveCatalog.defaultUserAgent), isTrue);
    expect(requests.every((request) => !request.followRedirects), isTrue);
  });

  test('downloads and verifies a package', () async {
    final choice = catalog().choose(await catalog().version('Dice', '1.0.2'));
    final artifact = (choice as ArtifactFound).artifact;
    final target = File('${dir.path}/p.wgt');
    var last = 0;
    await catalog().download(artifact, target, onProgress: (received) => last = received);
    expect(last, file.length);
    expect(target.readAsBytesSync(), file);
  });

  test('a corrupted download is refused and removed', () async {
    final artifact = (await catalog().version('Dice', '1.0.2')).artifacts.single;
    served = Uint8List.fromList(file)..[5] += 1;
    final target = File('${dir.path}/p.wgt');
    await expectLater(catalog().download(artifact, target), _catalogFails());
    expect(target.existsSync(), isFalse);
  });

  test('a longer or shorter body is refused and removed', () async {
    final artifact = (await catalog().version('Dice', '1.0.2')).artifacts.single;
    for (final body in [
      Uint8List.fromList([...file, 1]),
      file.sublist(0, file.length - 1),
    ]) {
      served = body;
      final target = File('${dir.path}/q.wgt');
      await expectLater(catalog().download(artifact, target), _catalogFails());
      expect(target.existsSync(), isFalse);
    }
  });

  test('an unknown package is not found', () async {
    await expectLater(catalog().version('Nope', '1.0'), _catalogFails(404));
    await expectLater(catalog().details('Nope'), _catalogFails(404));
  });

  test('redirects are not followed and absolute URLs are refused', () async {
    final base = catalog();
    await expectLater(
      base.download(Artifact(downloadUrl: '/api/redirect', sha256: sha, size: file.length), File('${dir.path}/r')),
      _catalogFails(302),
    );
    requests.clear();
    for (final url in ['http://evil.example/x', '//evil.example/x', 'api/x']) {
      await expectLater(
        base.download(Artifact(downloadUrl: url, sha256: sha, size: file.length), File('${dir.path}/s')),
        _catalogFails(),
      );
    }
    expect(requests, isEmpty);
    expect(File('${dir.path}/r').existsSync() || File('${dir.path}/s').existsSync(), isFalse);
  });

  test('a package too large for a watch is refused before the download', () async {
    await expectLater(
      catalog().download(Artifact(downloadUrl: '/api/x', sha256: sha, size: 600 << 20), File('${dir.path}/big')),
      _catalogFails(),
    );
    expect(requests, isEmpty);
  });

  test('search sends the encoded query and keeps only entries the app can use', () async {
    final page = await catalog().search(query: ' gold & co ', kind: CatalogKind.watchFace, page: 2);
    expect(requests.single.url.query, 'q=gold%20%26%20co&kind=watchface&installable=true&page=2');
    expect(page.items.map((item) => item.id), ['Dice', 'Clock', 'Nameless']);
    final [dice, clock, nameless] = page.items;
    expect(dice.name, 'Dice Face');
    expect(dice.kind, CatalogKind.watchFace);
    expect(dice.iconPath, '/api/icons/ab12.png');
    expect(dice.verdict, Verdict.installable);
    expect(dice.latestVersion, '1.0.2');
    expect(clock.kind, CatalogKind.app);
    expect(clock.verdict, Verdict.unknown);
    expect(clock.iconPath, isNull);
    expect(clock.latestVersion, isNull);
    expect(nameless.name, 'Nameless');
    expect(nameless.kind, isNull);
    // The page asked for wins over what the answer claims, so "more" always moves on
    expect(page.page, 2);
    expect(page.hasMore, isFalse);
    expect(page.total, 27);
    expect((await catalog().search(page: 1)).hasMore, isTrue);
  });

  test('search without filters asks only for the page; pages count from 1', () async {
    await catalog().search(query: '   ', installableOnly: false);
    expect(requests.single.url.query, 'page=1');
    expect(() => catalog().search(page: 0), throwsArgumentError);
  });

  test('a long query is cut, never in the middle of a character', () async {
    await catalog().search(query: '😀' * 150, installableOnly: false);
    expect(requests.single.url.queryParameters['q'], '😀' * 100);
  });

  test('icons come only from the catalog\'s icon path and are size limited', () async {
    expect(await catalog().icon('/api/icons/ab12.png'), List.filled(300, 1));
    requests.clear();
    for (final bad in [
      'http://evil.example/i.png',
      '//evil.example/api/icons/a.png',
      '/api/packages/Dice',
      '/api/icons/../packages/Dice',
      '/api/icons/..',
    ]) {
      await expectLater(catalog().icon(bad), _catalogFails(), reason: bad);
    }
    expect(requests, isEmpty);
    await expectLater(catalog().icon('/api/icons/big.png'), _catalogFails());
    await expectLater(catalog().icon('/api/icons/missing.png'), _catalogFails(404));
  });

  test('the package page is cleaned like the listing', () async {
    final info = await catalog().details('Face');
    expect(info.id, 'Face');
    expect(info.name, 'Gold Face');
    expect(info.authorName, 'Ann');
    expect(info.description, 'Line one\nLine two');
    expect(info.latestVersion, '1.6.3');
    expect(info.iconPath, '/api/icons/f.png');
    expect(info.versions.map((v) => (v.version, v.verdict)), [
      ('1.6.3', Verdict.installable),
      ('1.0', Verdict.expired),
    ]);
  });

  test('ids and versions Tizen Archive cannot have are not found, and nothing is asked', () async {
    await expectLater(catalog().details('../x'), _catalogFails(404));
    await expectLater(catalog().details('..'), _catalogFails(404));
    await expectLater(catalog().version('Dice', 'bad version'), _catalogFails(404));
    await expectLater(catalog().version('Dice', '..'), _catalogFails(404));
    await expectLater(catalog().version('a/b'), _catalogFails(404));
    expect(requests, isEmpty);
  });

  test('a package without a published version has nothing to install', () async {
    final noVersions = catalog(extra: {'/api/packages/Empty': () => json('{"latestVersion":null,"versions":[]}')});
    await expectLater(noVersions.version('Empty'), _catalogFails(404));
  });

  test('answers of the wrong shape are refused', () async {
    for (final body in [
      'not json',
      '[]',
      '{"packageId":"Dice","version":"1.0.2","builds":[{"artifacts":[{"sha256":"abc","size":1,"downloadUrl":"/x"}]}]}',
      '{"packageId":"Dice","version":"1.0.2","builds":[{"artifacts":[{"sha256":"$sha","size":-1,"downloadUrl":"/x"}]}]}',
      '{"packageId":"Dice","version":"1.0.2","builds":[{"artifacts":[{"sha256":"$sha","downloadUrl":"/x"}]}]}',
      '{"packageId":"../Dice","version":"1.0.2","builds":[]}',
      '{"packageId":"Dice","version":7,"builds":[]}',
      '{"packageId":"Dice","version":"1.0.2","builds":{}}',
    ]) {
      final odd = catalog(extra: {'/api/packages/Dice/versions/1.0.2': () => json(body)});
      await expectLater(odd.version('Dice', '1.0.2'), _catalogFails(), reason: body);
    }
    final page = catalog(extra: {'/api/catalog': () => json('{"items":[{"name":"no id"}]}')});
    await expectLater(page.search(), _catalogFails());
  });

  test('a response larger than allowed is refused', () async {
    final huge = catalog(extra: {'/api/catalog': () => json('{"items":[], "x":"${'a' * (6 << 20)}"}')});
    await expectLater(huge.search(), _catalogFails());
  });

  test('network failures are catalog failures', () async {
    final offline = ArchiveCatalog(client: MockClient((_) async => throw const SocketException('no route')));
    await expectLater(offline.search(), _catalogFails());
    await expectLater(offline.icon('/api/icons/a.png'), _catalogFails());
    final target = File('${dir.path}/offline');
    await expectLater(offline.download(Artifact(downloadUrl: '/api/x', sha256: sha, size: 1), target), _catalogFails());
    expect(target.existsSync(), isFalse);
  });

  group('choosing the file to install', () {
    Artifact artifact(Verdict verdict, [String url = '/api/artifacts/a/download']) =>
        Artifact(downloadUrl: url, sha256: 'a' * 64, size: 3, verdict: verdict);

    ArtifactChoice choose(List<Artifact> artifacts, List<Verdict> builds) =>
        ArchiveCatalog().choose(VersionInfo(id: 'x', version: '1.0', artifacts: artifacts, buildVerdicts: builds));

    test('picks the first installable build with a download', () {
      final file = artifact(Verdict.installable);
      final choice = choose([artifact(Verdict.expired, '/e'), file], [Verdict.expired, Verdict.installable]);
      expect((choice as ArtifactFound).artifact, same(file));
    });

    test('explains why nothing can be installed, by the primary build', () {
      const cases = {
        Verdict.deviceBound: NotInstallableReason.deviceBound,
        Verdict.expired: NotInstallableReason.expired,
        Verdict.notInstallable: NotInstallableReason.rejectedByWatch,
        Verdict.unverified: NotInstallableReason.unverified,
        Verdict.unknown: NotInstallableReason.unverified,
      };
      for (final MapEntry(key: verdict, value: reason) in cases.entries) {
        expect((choose([artifact(verdict)], [verdict]) as ArtifactNone).reason, reason, reason: '$verdict');
      }
    });

    test('installable without a download, and no builds at all, are told apart', () {
      expect((choose([], [Verdict.installable]) as ArtifactNone).reason, NotInstallableReason.notDownloadable);
      expect((choose([], []) as ArtifactNone).reason, NotInstallableReason.noBuilds);
    });

    test('without build verdicts, the files\' own verdicts tell', () {
      expect((choose([artifact(Verdict.expired)], []) as ArtifactNone).reason, NotInstallableReason.expired);
    });
  });
}
