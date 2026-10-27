/// Reading what a Tizen package says about itself from its manifest: `tizen-manifest.xml` for a native package
/// (`.tpk`), `config.xml` for a web package (`.wgt`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../api.dart';
import '../util/text.dart';

const String nativeManifest = 'tizen-manifest.xml';
const String webManifest = 'config.xml';

const String _tizenWidgetsNamespace = 'http://tizen.org/ns/widgets';
const String _wearableClock = 'http://tizen.org/category/wearable_clock';
const int _maxName = 200;
const int _maxField = 255;

/// The package a `tizen-manifest.xml` describes; its icon lives under `shared/res/`.
TizenPackageInfo parseNativeManifest(Uint8List xml) {
  final root = _parse(xml).rootElement;
  final applications = root.name.local == 'manifest' ? root.childElements.toList() : const <XmlElement>[];
  String? label;
  String? icon;
  for (final element in applications.expand((application) => application.childElements)) {
    final local = element.name.local;
    if (local == 'label' && label == null && element.getAttribute('xml:lang') == null) {
      label = _text(element);
    } else if (local == 'icon' && icon == null) {
      icon = _text(element);
    }
  }
  return TizenPackageInfo(
    packageId: _packageId(
      root.name.local == 'manifest' ? root.getAttribute('package') : null,
      '$nativeManifest has no package id',
    ),
    type: 'tpk',
    version: _field(root.name.local == 'manifest' ? root.getAttribute('version') : null),
    displayName: label == null ? null : cleanLine(label, _maxName),
    iconPath: icon == null ? null : 'shared/res/$icon',
    kind: applications.any((element) => element.name.local == 'watch-application')
        ? PackageKind.watchFace
        : PackageKind.app,
  );
}

/// The package a `config.xml` describes; its icon path is relative to the package's root.
TizenPackageInfo parseWebManifest(Uint8List xml) {
  final root = _parse(xml).rootElement;
  final children = root.childElements.toList();
  String? packageId;
  String? icon;
  String? name;
  var face = false;
  for (final element in children) {
    final local = element.name.local;
    final tizen = element.name.namespaceUri == _tizenWidgetsNamespace;
    if (local == 'application' && tizen) {
      packageId = element.getAttribute('package');
    } else if (local == 'icon' && icon == null) {
      icon = _field(element.getAttribute('src'));
    } else if (local == 'name' && name == null && element.getAttribute('xml:lang') == null) {
      name = _text(element);
    } else if (local == 'category' && tizen && element.getAttribute('name')?.trim() == _wearableClock) {
      face = true;
    }
  }
  return TizenPackageInfo(
    packageId: _packageId(packageId, '$webManifest has no tizen:application package id'),
    type: 'wgt',
    version: _field(root.name.local == 'widget' ? root.getAttribute('version') : null),
    displayName: name == null ? null : cleanLine(name, _maxName),
    iconPath: icon,
    kind: face ? PackageKind.watchFace : PackageKind.app,
  );
}

XmlDocument _parse(Uint8List bytes) {
  // A DTD can define entities that expand without end, so manifests with one are refused before parsing
  final head = latin1.decode(bytes).toLowerCase();
  if (head.contains('<!doctype') || head.contains('<!entity')) {
    throw const InvalidPackageException('Manifest contains a DTD');
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const InvalidPackageException('Manifest is not UTF-8 text');
  }
  try {
    return XmlDocument.parse(text.startsWith('\ufeff') ? text.substring(1) : text);
  } on XmlException {
    throw const InvalidPackageException('Manifest is not well-formed XML');
  }
}

/// The text inside [element], trimmed; null when there is none.
String? _text(XmlElement element) {
  final text = element.innerText.trim();
  return text.isEmpty ? null : text;
}

/// An attribute value as stored, trimmed; null when it is missing, empty, too long or holds control characters.
String? _field(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty || text.length > _maxField || hasIsoControl(text) ? null : text;
}

String _packageId(String? value, String missing) => _field(value) ?? (throw InvalidPackageException(missing));
