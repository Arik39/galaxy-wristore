# Galaxy Wristore

**For Tizen and Galaxy Watch.** Install, back up and restore the faces and apps on a Samsung Tizen watch from your
phone, over Wi-Fi. It works with an iPhone or an Android phone.

Samsung stopped Tizen downloads on 30 September 2025, so the Galaxy Store can no longer give back a face or an app
once a watch is reset. Galaxy Wristore replaces the parts of Samsung's watch app that went with it:

- **Discover** uses [Tizen Archive](https://tizen-archive.com) in place of the Galaxy Store. Search faces and apps,
  look at the pictures inside a package, and install in one tap. Every download is checked against the archive's
  SHA-256 and size before it reaches the watch.
- **Backup** replaces Samsung account backup. One `.twbackup` file holds copies of the faces and apps you added, the
  music and pictures on the watch, and a fingerprint of every app. The app tells you plainly what a reset would
  remove for good.
- **Restore** puts back only what you pick, item by item, with each face's pictures full size.
- **Faces and Apps** show what is on the watch with its real pictures, and remove what you added.
- **Install a file you have:** open a `.tpk` or `.wgt` from Discover. The app shows what it is and whether its
  signature looks store-signed. The watch has the last word on what it accepts.

It talks to the watch directly over its Wi-Fi debugging link (`sdb`), so it needs neither Galaxy Wearable nor an
Android phone.

## What it cannot do

These run over Samsung's Bluetooth protocols, which other apps cannot use, so they stay with Samsung's app:
pairing, notifications from the phone, health sync and software updates.

Some limits come from the watch itself:

- It installs only packages signed for the store. Samsung no longer issues developer certificates, so a face that
  was rebuilt or changed cannot be installed.
- Installed packages cannot be copied off a watch. A backup keeps a copy only of what Tizen Archive has, or of
  package files you add yourself.
- The data inside watch apps, health data included, cannot be read.

## Setting up the watch

1. On the watch, open **Settings → About watch → Software**, then tap **Software version** five times.
2. Back in **About watch**, turn on **Debugging**.
3. Restart the watch. Debugging starts answering only after a restart.
4. Keep the watch on the same Wi-Fi as the phone (not a guest network). The first time the app connects, the watch
   asks **Allow debugging**: tap the check mark.

The watch serves one device at a time. Close other tools that connect to it, such as the Mac app or `sdb`, before
using the phone.

## Building

The app is written in Flutter (3.47 or later).

```sh
flutter pub get
flutter run                                   # on a connected phone
flutter run --dart-define=WRISTORE_DEMO=true  # with a built-in demo watch, no watch needed
flutter test
```

- **Android:** `flutter build apk --release` builds an APK to install directly.
- **iPhone:** without a paid Apple Developer account, open `ios/Runner.xcworkspace` in Xcode, choose your Personal
  Team under Signing, and run it on your iPhone. A personal build must be re-installed every 7 days. iOS asks for
  Local Network access the first time the app looks for the watch; the app needs it.

## Privacy

There are no ads, analytics or trackers. The app connects only to Tizen Archive and to your watch on your own
network. Backups stay on your phone until you share them.

## Credits and licence

Galaxy Wristore is licensed under the [Apache License 2.0](LICENSE).

Its watch connection, package reader, catalog client and backup format are ported from
[Tizen Companion Installer](https://github.com/Tizen-Archive/tizen-companion-installer) by Tizen Archive (Apache
License 2.0). Backups made by its Mac app open here, and the other way round. See [NOTICE](NOTICE).

The Archivo typeface is used under the SIL Open Font License 1.1.

Samsung, Galaxy, Galaxy Watch, Gear and Tizen are trademarks of their respective owners. This project is not
affiliated with or endorsed by Samsung.
