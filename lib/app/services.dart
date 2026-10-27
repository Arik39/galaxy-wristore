import '../core/api.dart';

/// Everything the screens talk to: the watch, Tizen Archive, package files and backups. Built once at start-up.
class Services {
  const Services({
    required this.connector,
    required this.finder,
    required this.catalog,
    required this.inspector,
    required this.backups,
    this.demo = false,
  });

  final WatchConnector connector;
  final WatchFinder finder;
  final CatalogApi catalog;
  final PackageInspector inspector;
  final BackupService backups;

  /// True when a demo watch stands in for a real one (development builds only, never by default); the app says so on
  /// screen.
  final bool demo;
}
