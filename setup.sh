#!/usr/bin/env bash
# One-time setup: generates the Android/iOS platform folders around the Dart
# code in this repo, then applies the Android overrides (share intent, manifest).
set -euo pipefail
cd "$(dirname "$0")"

ORG="com.faysarukattil"   # application id becomes $ORG.shelfmark - change if you like

command -v flutter >/dev/null || { echo "Flutter SDK not found on PATH"; exit 1; }

rm -rf .sm_backup && mkdir .sm_backup
cp -r lib pubspec.yaml analysis_options.yaml .sm_backup/

flutter create --org "$ORG" --project-name shelfmark --platforms=android,ios .

rm -rf lib && cp -r .sm_backup/lib lib
cp .sm_backup/pubspec.yaml pubspec.yaml
cp .sm_backup/analysis_options.yaml analysis_options.yaml
rm -rf .sm_backup test/widget_test.dart

PKG_DIR="android/app/src/main/kotlin/$(echo "$ORG" | tr . /)/shelfmark"
mkdir -p "$PKG_DIR"
cp android_overrides/MainActivity.kt "$PKG_DIR/MainActivity.kt"
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml

# Firebase + WebView need minSdk >= 23
if [ -f android/app/build.gradle.kts ]; then
  sed -i.bak 's/minSdk = flutter\.minSdkVersion/minSdk = maxOf(23, flutter.minSdkVersion)/' android/app/build.gradle.kts
  rm -f android/app/build.gradle.kts.bak
fi
if [ -f android/app/build.gradle ]; then
  sed -i.bak 's/minSdkVersion flutter\.minSdkVersion/minSdkVersion Math.max(23, flutter.minSdkVersion)/' android/app/build.gradle
  rm -f android/app/build.gradle.bak
fi

flutter pub get

cat <<'MSG'

Platform folders generated. Next:
  1. dart pub global activate flutterfire_cli
  2. flutterfire configure        (pick/create your Firebase project, select Android)
  3. Do the Firebase console steps in README.md (Google sign-in, Firestore, SHA keys)
  4. flutter run
MSG
