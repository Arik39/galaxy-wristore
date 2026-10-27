/// Galaxy Wristore's core: the contract in `api.dart` and the classes that fulfil it.
///
/// - [SdbWatchConnector] opens [WatchConnection]s over sdb with the app's key, which [SecureKeyStore] keeps;
/// - [NetworkWatchFinder] looks for watches in the phone's Wi-Fi network;
/// - [ArchiveCatalog] talks to Tizen Archive;
/// - [ZipPackageInspector] reads `.tpk` and `.wgt` files;
/// - [TwBackupService] makes, opens and restores `.twbackup` files.
library;

export 'api.dart';
export 'backup/tw_backup_service.dart' show TwBackupService;
export 'catalog/archive_catalog.dart' show ArchiveCatalog;
export 'catalog/version_compare.dart' show VersionCompare;
export 'package/zip_package_inspector.dart' show ZipPackageInspector;
export 'sdb/key_store.dart' show KeyStore, MemoryKeyStore;
export 'sdb/network_watch_finder.dart' show NetworkWatchFinder;
export 'sdb/sdb_watch_connection.dart' show SdbWatchConnector;
export 'sdb/secure_key_store.dart' show SecureKeyStore;
