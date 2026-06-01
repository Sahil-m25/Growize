# Release keystore setup

This doc covers the Growize Android release keystore — generation, password rotation, backup, and the gradle wiring that loads it.

## TL;DR — what's in the repo

| Path | Committed? | Purpose |
| --- | --- | --- |
| `android/app/release-keystore.jks` | **NO** (gitignored) | Generated signing key — placeholder password, must rotate before real release |
| `android/key.properties` | **NO** (gitignored) | User-supplied credentials, points gradle at the keystore |
| `android/key.properties.template` | yes | Template to copy into `key.properties` |
| `android/app/build.gradle.kts` | yes | Loads `key.properties` if present and wires `signingConfigs.release` |

A keystore was generated with placeholder values:

- alias: `growize-release`
- algorithm: RSA, keysize 2048, validity 10000 days
- storepass / keypass: `CHANGE_ME_BEFORE_RELEASE`
- dname: `CN=Growize, OU=ARL, O=AgResearch Labs, L=Pune, ST=Maharashtra, C=IN`

**This keystore must not be used for a real Play Store release until passwords are rotated.** See "Rotate before production" below.

## Setting the real password

1. Pick a strong password. Use a password manager — losing this means you can never ship an update.
2. Re-generate the keystore with the real password (the placeholder one cannot be changed in place without re-keying):
   ```bash
   cd android/app
   keytool -genkeypair -v \
     -keystore release-keystore.jks \
     -alias growize-release \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -dname "CN=Growize, OU=ARL, O=AgResearch Labs, L=Pune, ST=Maharashtra, C=IN"
   # keytool will prompt for storepass and keypass — enter the real one
   ```
   Or change the password on the existing keystore:
   ```bash
   keytool -storepasswd -keystore release-keystore.jks
   keytool -keypasswd -alias growize-release -keystore release-keystore.jks
   ```
3. Copy `android/key.properties.template` to `android/key.properties` and fill in the real values:
   ```
   storePassword=<real-password>
   keyPassword=<real-password>
   keyAlias=growize-release
   storeFile=release-keystore.jks
   ```
4. Confirm gradle picks it up:
   ```bash
   flutter build apk --release
   ```
   Successful build = keystore is wired correctly. A debug-signed APK = `key.properties` wasn't loaded (check filename + location).

## Backup — DO NOT SKIP

Losing the keystore is unrecoverable. Google Play will not let you publish updates under the same package name with a different signing key. Investors who installed the app would have to uninstall and reinstall a renamed app.

Minimum backup posture:

- Store the `.jks` file in at least two locations off this machine — e.g. a password-manager file attachment (1Password / Bitwarden) and an encrypted offline drive.
- Store the passwords in a password manager, never in the same place as the keystore file.
- Record the SHA-256 fingerprint somewhere recoverable so you can verify a restored keystore matches the original:
  ```bash
  keytool -list -v -keystore android/app/release-keystore.jks
  ```
- Tell at least one other trusted person at AgResearch Labs where the backup lives and how to access it.

## Verify

Confirm alias, validity, and fingerprint:

```bash
keytool -list -v -keystore android/app/release-keystore.jks
```

Expected output includes:

- `Alias name: growize-release`
- `Valid from: ... until: ...` (~27 years from generation)
- `Certificate fingerprints:` SHA-256

## Gradle wiring (reference)

`android/app/build.gradle.kts` reads `key.properties` at configure time and creates a `release` signing config only if the file exists. When `key.properties` is absent (fresh checkout, CI without secrets), release builds fall back to the debug keystore so `flutter run --release` still works for local dev. The release artifact will not be Play-uploadable in that fallback case — it's a development convenience only.

## Rotate before production

Anyone with read access to `CHANGE_ME_BEFORE_RELEASE` could sign builds claiming to be Growize. Until rotation:

- Do not upload an APK signed with this keystore to the Play Store.
- Do not distribute the APK outside the team.
- Treat the keystore as compromised the moment a real password isn't in place.

After rotation, also wipe the placeholder keystore from any laptops it was shared on (`shred` / SecureDelete) and regenerate from scratch.
