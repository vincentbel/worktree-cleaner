# Sparkle Release Process

## Distribution model

The application source remains in the `vincentbel/worktree-cleaner`
repository. Sparkle reads a signed `appcast.xml` and notarized update archives
from the separate public `vincentbel/worktree-cleaner-releases` repository.
That repository contains binaries and update metadata only.

This separation is intentional: a GitHub token embedded in a distributed app
cannot be kept secret. If the update binaries must also remain private, replace
the feed and download URL settings with an authenticated update gateway. Do not
add a shared personal access token to the app.

## One-time setup

1. Join the Apple Developer Program and install a `Developer ID Application`
   certificate in the login keychain.
2. Create `vincentbel/worktree-cleaner-releases` as a public repository and
   initialize its `main` branch. It does not need GitHub Pages.
3. Store notarization credentials in the keychain:

   ```sh
   xcrun notarytool store-credentials worktree-cleaner-notary \
     --apple-id YOUR_APPLE_ID \
     --team-id YOUR_TEAM_ID \
     --password YOUR_APP_SPECIFIC_PASSWORD
   ```

4. Back up the Sparkle private key generated under the
   `dev.worktreecleaner.app` account to a secure location. Never commit the
   exported file:

   ```sh
   /tmp/worktree-cleaner-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account dev.worktreecleaner.app \
     -x /secure/location/worktree-cleaner-sparkle-key
   ```

The public key is stored in the Xcode project and is safe to publish. Losing the
private key complicates key rotation, so keep an encrypted backup.

## Build and notarize

Every release needs an increasing numeric build number. The marketing version
uses `x.y.z` format.

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
RELEASE_NOTES_FILE=/path/to/release-notes.md \
scripts/build-release.sh 0.2.0 2
```

The script archives and exports with Developer ID signing, submits the app to
Apple for notarization, staples the ticket, validates Gatekeeper acceptance,
creates the update zip, and generates a signed appcast. Delta updates are
intentionally disabled so the release process does not need to retain previous
application archives.

For a different notarization credential profile, set
`NOTARY_KEYCHAIN_PROFILE`. CI may set `SPARKLE_ED_KEY_FILE` to a temporary file
created from an encrypted secret instead of reading the signing key from the
login keychain.

## Publish

Review the generated appcast and then publish the release asset before the
appcast:

```sh
scripts/publish-release.sh 0.2.0
```

The publishing script requires an authenticated GitHub CLI. It refuses to
publish to a private release repository because the app intentionally contains
no GitHub credential.

Test the complete update path with a previously notarized build. A current
development build proves that Sparkle compiles, but it does not exercise the
production Developer ID, notarization, archive signature, and replacement path.
