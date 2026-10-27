# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Flutter (the user's choice): one Dart codebase, mainly for Android and iOS phones. Desktop (macOS, Windows, Linux) is possible later; it is not the first target.

The watch protocol and catalog logic are ported to Dart from the Kotlin `core` and `cli` modules in `../tizen-companion-installer`:
- `sdb` over TCP with RSA authorization, `shell:` and `sync:` push and pull;
- reading Tizen packages;
- the Tizen Archive client;
- the `.twbackup` format.

## Users

- **First user:** the project owner. They have an original Galaxy Watch 46 mm (SM-R800, Tizen 5.5) that they moved from an Android phone to an iPhone, then reset.
- **Intended audience of the open-source release:** owners of Samsung's Tizen watches (Gear S2/S3/Sport, Galaxy Watch, Watch Active/Active2, Watch3) who keep using them after Samsung ended Tizen store downloads on 2025-09-30. Many of them have switched to an iPhone or have to reset the watch, and many are not technical.

Typical scene: at home, phone in hand, watch on the same Wi-Fi. They are getting their watch faces and apps back after a reset, backing up before one, or looking for an app the store no longer offers.

## Product Purpose

Galaxy Wristore replaces Samsung's watch app (Galaxy Wearable on Android, the Galaxy Watch app on iPhone). It is the everyday home for a Tizen watch, and it brings every feature of the original app that can be reached over the watch's Wi-Fi debugging link. It also replaces Samsung's services:
- the Galaxy Store with Tizen Archive;
- Samsung account backup with Galaxy Wristore's own one-file backup.

From the phone, directly over Wi-Fi, it:
- browses and installs apps and watch faces from Tizen Archive;
- installs package files the user has;
- shows and manages what is on the watch;
- saves everything a reset erases into one backup file, and puts back exactly what the user picks.

People open it whenever they manage their watch, not only after a reset. Success means:
- the original app and the closed store are never missed;
- a reset or a new phone costs minutes, not a user's favourite faces.

## Positioning

- It works with an iPhone. It talks to the watch itself (`sdb` over Wi-Fi), so it needs neither Galaxy Wearable nor an Android phone.
- It is backup-first. One `.twbackup` file holds:
  - verified copies of the downloaded apps and faces, from Tizen Archive or the user's own package files;
  - the user's files on the watch;
  - a fingerprint of every app.

  A restore lets the user choose item by item, seeing each face's pictures full size.
- It is verification-first. Downloads are checked against Tizen Archive's SHA-256 and size. Fingerprints from the user's own watch can confirm that a package found later is the genuine one. Packages and signatures are never modified.

## Operating Context

The watch:
- Debugging must be on: Settings → About watch → Software, tap the software version five times, then Debugging.
  - With Debugging off, the watch accepts the TCP connection but never answers.
  - After switching Debugging on, a watch restart may be needed before it answers.
- The watch asks "Allow debugging" once per key. The trust survives Debugging toggles and restarts, but not a reset.
- The watch serves one host at a time; another connected device makes it busy.
- Its Wi-Fi dozes when the screen is off.
- Phone and watch must be on the same Wi-Fi, not a guest network. Port 26101, private IPv4 addresses only.

The catalog is Tizen Archive (`https://tizen-archive.com`) and its REST API:
- search (`/api/catalog`);
- package details (`/api/packages/{id}`);
- versions with builds, artifacts, SHA-256 and download URLs;
- icons.

The API is described at `/api/docs`.

Backups are the existing `.twbackup` format, made by the Mac app; the phone app must read and write it compatibly. A backup is a zip holding `backup.json`, `packages/`, `media/`, `fingerprints/` and `report.txt`.

iPhone:
- needs the Local Network permission;
- the owner declined the paid Apple Developer Program, so iPhone installs are personal builds (free provisioning, re-signed every 7 days) or sideloading.

## Capabilities and Constraints

Feature parity with the Mac app (`tizen-companion-installer/cli`, the `tizen-watch` CLI and GUI):
- **Connecting:** find the watch on the Wi-Fi network, or type its address; test the connection.
  - A guided setup covers Debugging and the "Allow debugging" prompt.
  - Every watch state gets a clear next step: asleep, Debugging off, not allowed yet, busy with another device.
- **Catalog:** browse and search Tizen Archive (watch faces or apps, installable only).
  - A store-like details page shows the icon, description, author, versions and the pictures inside the package, zoomable.
  - Install from the catalog: download, check SHA-256 and size, then install with the watch's package manager (`pkgcmd -w`).
- **Files:** install `.tpk` and `.wgt` files the user picks, opens with the app or shares to it.
- **On the watch:** list the packages as built-in, built-in updated or downloaded, and check Tizen Archive for each one (available, newer version).
- **Backup:** one file holds:
  - copies of the downloaded apps and faces, from Tizen Archive or the user's own package files;
  - the user's files from the watch's media folder;
  - fingerprints (`pkginfo`, manifest, author signature, icon) and the certificate database;
  - a report of what has no copy.
- **Restore:** choose apps, faces and files one by one, with thumbnails and full-size zoomable pictures. It installs only what the watch lacks or has older, and copies files back into the media folder only.

Features of the original app, tested on the owner's SM-R800 (Tizen 5.5) over `sdb` on 2026-10-26. The debugging shell runs as `owner` with the Smack label `User::Shell`.
- **Works:**
  - "Find my watch" by sound: `paplay` plays the watch's own `/usr/share/feedback.wearable/sound/System/Find_my_Gear.ogg`.
  - Opening the watch's own screens with `app_launcher -s <appid>`: Sound, Volume, Ringtones and tones, Notifications, Do not disturb, Display, the quick-settings editor and the apps view. Each change is made on the watch.
  - Knowing the face on the wrist: `app_launcher -S` lists running apps, and the face is one of them.
- **Refused by the watch:**
  - Vibration: feedbackd requires the `haptic` privilege.
  - Turning the screen on: `devicectl display` fails.
  - Reading or changing settings: `vconftool` and `buxton2ctl` cannot be run.
  - Choosing the face: a face that is not showing cannot be launched.
  - Customizing the face: the watch-face editor opens blank when started without the face to edit, and the debugging link cannot pass one.
  - App order and widgets: the home screen's data is unreadable.
- **No way around it:** a helper app on the watch would need a store signature, and Samsung no longer issues certificates. Even a signed app could not change most system settings, which need Samsung's platform signature.
- **Still to verify:**
  - uninstalling apps;
  - adding music and pictures;
  - battery and storage details.

These stay with Samsung's app, because they run over Samsung's Bluetooth protocols that a third-party app cannot use:
- pairing and the Bluetooth connection;
- relaying the phone's notifications;
- health sync;
- software updates.

Galaxy Wristore says so plainly rather than imitating them.

Hard limits, never to be promised:
- The watch installs only store-signed packages.
- Samsung no longer issues developer certificates (since December 2025), so recreated or modified faces cannot be installed.
- Installed packages cannot be copied off a watch.
- The data inside watch apps, including health data, cannot be read.

Rules:
- Never modify a package or its signatures. Show the watch's own answer when it refuses something.
- Names from the catalog, the watch and backup files are untrusted text. They are never rendered as markup, and sizes are bounded.

Terms: watch face, app, package (`.tpk` native, `.wgt` web), Debugging, "Allow debugging", Tizen Archive, backup (`.twbackup`), restore, fingerprint, built-in, downloaded.

Undecided:
- whether to include the Android-only "Galaxy Wearable way" (a companion APK delivered by Samsung's Gear Plugin over Bluetooth, no Debugging needed);
- the languages at launch (the original project ships English and Russian);
- distribution channels (GitHub releases, F-Droid, App Store or TestFlight, which needs the paid Apple program);
- a desktop build;
- verifying a found package against a backup fingerprint. Fingerprints are saved, but no check is built yet.

## Brand Commitments

- **Name:** Galaxy Wristore, the owner's choice. "Wristore" is wrist + restore, and a store for the wrist. Listings carry a subtitle like "for Tizen & Galaxy Watch" so people searching for those words find it.
  - Open risk: "Galaxy", "Samsung", "Gear" and "Tizen" are third-party trademarks. App-store review may require "Wristore" alone, with "for Galaxy Watch" as descriptive text.
- **Look and feel the owner asked for, in their words:** "more modern", "production level", "fully fancy like full of animation but minimalistic".
- **Open source:** the owner's own GitHub repository, Apache-2.0. It credits Tizen Companion Installer (Apache-2.0, Tizen-Archive, https://github.com/Tizen-Archive/tizen-companion-installer), which the core logic is ported from, and carries its NOTICE.
- No ads, analytics or trackers. The network is used only for Tizen Archive and for the watch in the local network.

## Evidence on Hand

- A working, tested Kotlin implementation in `../tizen-companion-installer`, to port from and to check behaviour against:
  - `core`: the sdb session and installer, package reader, catalog client, signature inspector;
  - `cli`: backup, restore and the Swing GUI;
  - `app`: the Android app.
- Tests: 138 core, 129 app and 5 CLI tests.
- Real-device knowledge from the SM-R800 (Tizen 5.5), summarised above under Operating Context.
- A real backup from the owner's watch (38 of 55 packages with copies, 5 files) in `~/Documents/Tizen Watch Backup/`. It is private: it may be used for local testing only and must never be committed or shown in public material.
- None yet: logo, icon, screenshots, users, testimonials, ratings. Do not fabricate any of them.

## Product Principles

1. **The watch decides.** Install only what the watch accepts, never alter packages, and show its real answer.
2. **Private by construction.** Nothing leaves the phone except catalog requests; the watch is reached only in the local network.
3. **Every state has a next step.** A sleeping, busy or unconfigured watch is explained in plain words with the one action that fixes it.
4. **Save before it is lost.** Backup is a first-class flow, and the app says plainly what a reset would destroy for good.
5. **Verify, then trust.** Checksums for downloads, fingerprints for found files, and the user's choice for everything that goes back.
