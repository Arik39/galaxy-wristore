# Contributing to Galaxy Wristore

Thank you for helping. Galaxy Wristore keeps Tizen watches useful now that Samsung has stopped Tizen downloads, and
every report, test and fix helps someone keep their watch.

## Ways to help

- **Report a bug** with the [bug report form](https://github.com/Arik39/galaxy-wristore/issues/new?template=bug_report.yml).
  Say which watch, which phone and which version of the app, and what you saw.
- **Test with your watch.** Tizen watches differ by model and software version, so reports from any Galaxy Watch or
  Gear, good or bad, are very useful.
- **Suggest a feature** with the [feature request form](https://github.com/Arik39/galaxy-wristore/issues/new?template=feature_request.yml).
- **Send a fix or a feature** as a pull request, as described below. For anything large, open an issue first so we
  can agree on the approach before you spend time on it.

## Set up the project

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or later. For Android builds, add Android
Studio or the Android SDK; for iPhone builds, a Mac with Xcode.

```sh
git clone https://github.com/Arik39/galaxy-wristore.git
cd galaxy-wristore
flutter pub get
flutter run --dart-define=WRISTORE_DEMO=true   # a built-in demo watch, no watch needed
flutter run                                    # the real thing, with a watch on your Wi-Fi
```

The demo watch is the quickest way to work on the screens. It stands in for a watch, Tizen Archive and backups, and
the app marks itself **Demo** while it runs. Two more switches open the app where you are working:

```sh
flutter run --dart-define=WRISTORE_DEMO=true --dart-define=WRISTORE_TAB=backup --dart-define=WRISTORE_OPEN=restore
```

`WRISTORE_TAB` is `watch`, `faces`, `apps`, `discover` or `backup`; `WRISTORE_OPEN` is `face`, `app`, `package` or
`restore`.

To try a real watch, set it up as the [README](README.md#set-up-the-watch) explains.

## How the code is laid out

| Folder | What is in it |
| --- | --- |
| `lib/core/` | Everything that talks to the watch, Tizen Archive and backup files, in plain Dart. `api.dart` is the contract the screens use. |
| `lib/core/sdb/` | The `sdb` protocol over TCP: finding the watch, RSA authorisation, shell commands, file transfer, installing. |
| `lib/core/package/` | Reading `.tpk` and `.wgt` packages: manifest, pictures and signature. |
| `lib/core/catalog/` | The Tizen Archive client. |
| `lib/core/backup/` | The `.twbackup` format, shared with the Tizen Companion Installer Mac app. |
| `lib/app/` | The app shell and tabs, `WatchController` (the app's state) and how the services are put together. |
| `lib/features/` | One folder per part of the app: `home` (the Watch tab), `faces`, `apps`, `discover`, `backup`, `setup`. |
| `lib/design/` | The design system: colours, type, controls, icons and the face disc. [DESIGN.md](DESIGN.md) describes it. |
| `lib/demo/` | The demo watch and catalog. |
| `test/` | Tests, laid out like `lib/`. `test/core/support/fake_sdbd.dart` is a fake watch to test the protocol against. |
| `tool/` | Scripts: the app icon and the README screenshots. |

[PRODUCT.md](PRODUCT.md) explains who the app is for and the principles behind it. Read it before proposing a new
feature.

## Before you send a pull request

Run the same checks as CI:

```sh
dart format lib test tool     # 120 columns, set in analysis_options.yaml
flutter analyze
flutter test
```

Then:

- **Keep it focused.** One fix or feature per pull request is easier to review and to undo.
- **Add or update tests.** Code in `lib/core/` needs them; the fakes in `test/` let you test without a watch.
- **Show changes to the screens.** Add before-and-after screenshots, from the demo watch if you like.
- **Say how you tested it.** Mention the watch model and phone if you tried it on real hardware.
- **Follow [DESIGN.md](DESIGN.md)** for anything on screen: the colours, type and spacing are deliberate.
- **Write for people.** Text in the app is short and plain, with no jargon: "Back up now", not "Initiate backup".

The watch protocol, package reader, catalog client and backup format are ported from
[Tizen Companion Installer](https://github.com/Tizen-Archive/tizen-companion-installer). Keep the backup format
compatible with it, so backups still open in both apps.

## Licence

Galaxy Wristore is licensed under the [Apache License 2.0](LICENSE). By sending a contribution, you agree that it is
licensed under the same terms.

## Releasing

This part is for maintainers.

Releases are built by [`.github/workflows/release.yml`](.github/workflows/release.yml) when a version tag is pushed.
It signs the APK with the release key and publishes it with its checksum on the
[releases page](https://github.com/Arik39/galaxy-wristore/releases).

### One-time setup: the signing secrets

Every release must be signed with the same key, or Android refuses it as an update. The key is a keystore file that
never goes in the repository. Keep it and its password backed up somewhere safe, such as a password manager: if they
are lost, no update can ever install over the existing app.

In the repository on GitHub, open **Settings → Secrets and variables → Actions** and add four repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The keystore file in base64: `base64 -i release.jks \| pbcopy` on a Mac copies it. |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password. |
| `ANDROID_KEY_ALIAS` | The key's alias, `release`. |
| `ANDROID_KEY_PASSWORD` | The key password; for a PKCS12 keystore, the same as the keystore password. |

To build a signed release on your own computer, create `android/key.properties` (Git ignores it):

```properties
storeFile=/absolute/path/to/release.jks
storePassword=…
keyAlias=release
keyPassword=…
```

Without that file, release builds are signed with the debug key.

### Publish a version

1. Raise `version` in `pubspec.yaml`: the name and the build number, which must always go up. For example, from
   `1.0.0+1` to `1.0.1+2`.
2. Commit, then tag and push:

   ```sh
   git tag v1.0.1
   git push origin main v1.0.1
   ```

3. Watch the **Release** workflow under **Actions**. When it finishes, the release is live and the README's download
   link points at it.

The tag must match the version in `pubspec.yaml`, or the workflow stops. A tag with a hyphen, such as `v1.1.0-beta.1`,
is published as a pre-release.
