#!/bin/zsh
# Makes the icon files of every platform from the pictures tool/app_icon_test.dart draws into assets/icon.
# Run from the repository root on a Mac: flutter test tool/app_icon_test.dart && tool/app_icons.sh
set -euo pipefail

# Resizes picture $1 to a square of $2 pixels at $3.
resize() { sips --resampleHeightWidth $2 $2 $1 --out $3 >/dev/null; }

# Android: the adaptive icon's layers at 108 units, and the plain icon at 48 for Android 7.
res=android/app/src/main/res
for density in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  name=${density%%:*} factor=${density#*:}
  resize assets/icon/app_icon_rounded.png $(( 48 * factor )) $res/mipmap-$name/ic_launcher.png
  resize assets/icon/app_icon_foreground.png $(( 108 * factor )) $res/mipmap-$name/ic_launcher_foreground.png
  resize assets/icon/app_icon_monochrome.png $(( 108 * factor )) $res/mipmap-$name/ic_launcher_monochrome.png
done

# iOS: every size its asset catalog lists, from the opaque square.
ios=ios/Runner/Assets.xcassets/AppIcon.appiconset
for spec in 20:1 20:2 20:3 29:1 29:2 29:3 40:1 40:2 40:3 60:2 60:3 76:1 76:2 83.5:2 1024:1; do
  points=${spec%%:*} scale=${spec#*:}
  resize assets/icon/app_icon.png $(( points * scale )) $ios/Icon-App-${points}x${points}@${scale}x.png
done

# macOS.
for px in 16 32 64 128 256 512 1024; do
  resize assets/icon/app_icon_macos.png $px macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$px.png
done

# Windows: one icon file with a picture per size, each stored as a PNG.
sizes=(16 20 24 32 40 48 64 128 256)
tmp=$(mktemp -d)
for px in $sizes; do resize assets/icon/app_icon_rounded.png $px $tmp/$px.png; done
python3 - $tmp windows/runner/resources/app_icon.ico $sizes <<'PY'
import struct
import sys

folder, out, sizes = sys.argv[1], sys.argv[2], [int(s) for s in sys.argv[3:]]
pictures = [open(f'{folder}/{s}.png', 'rb').read() for s in sizes]
offset = 6 + 16 * len(sizes)
with open(out, 'wb') as f:
    f.write(struct.pack('<HHH', 0, 1, len(sizes)))
    for size, data in zip(sizes, pictures):
        # Width and height take one byte each; 0 stands for 256.
        f.write(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    for data in pictures:
        f.write(data)
PY
rm -rf $tmp
echo "Android, iOS, macOS and Windows icons written."
