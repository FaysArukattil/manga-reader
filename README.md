# Shelfmark

A manga tracker: one shelf for every series you read, on any site. It stores
links and progress only - no content is copied or hosted. Tap a card to resume
exactly where you stopped.

## Setup
1. Install Flutter, then in this folder run `./setup.sh`
   (generates `android/` + `ios/`, applies the share-intent manifest, runs `pub get`).
2. `dart pub global activate flutterfire_cli && flutterfire configure`
3. Firebase console steps below.
4. `flutter run`

## Firebase console checklist
1. Create/choose a project; add the Android app `com.faysarukattil.shelfmark`
   (or whatever id you set in `setup.sh`).
2. Authentication -> Sign-in method -> enable **Google**; set a support email.
3. Add SHA-1 and SHA-256 fingerprints (Project settings -> your Android app):
   - debug: `cd android && ./gradlew signingReport`
   - release/upload key: `keytool -list -v -keystore <your.jks>`
   - after the first Play upload, also add the **Play App Signing** SHA-1/SHA-256
     from Play Console -> Setup -> App signing.
4. Re-run `flutterfire configure` (or re-download `google-services.json`) after
   adding SHA keys so the OAuth client is included.
5. Firestore Database -> Create database (production mode, nearest region).
6. Deploy rules: `firebase deploy --only firestore:rules` (uses `firestore.rules`).

## Data model
`users/{uid}/series/{id}`: title, url (last-read page), host, coverUrl, chapter,
status, scroll (0..1), mode (0 off / 1 dark / 2 warm), dim, titleAuto,
createdAt, updatedAt.

## Behaviour notes
- Offline: Firestore persistence keeps the shelf readable offline; edits sync later.
- Progress writes: once when a new page URL settles, once on leaving/backgrounding.
- Ads/popups/trackers are blocked inside the reader only.
- Redirects to a different site are blocked (snackbar offers "Allow").
