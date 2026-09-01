# Sparkle Release Process

## Distribution model

The application source, signed `appcast.xml`, and notarized update archives all
live in the public `vincentbel/worktree-cleaner` repository. Update archives are
attached to GitHub Releases alongside `appcast.xml`. Sparkle reads the latest
appcast through GitHub's stable `releases/latest/download/appcast.xml` URL
without embedding a GitHub credential in the distributed app.

The repository must be public before publishing an update. If the update
binaries must remain private, replace the feed and download URL settings with an
authenticated update gateway. Do not add a shared personal access token to the
app.

## Join the Apple Developer Program

An Individual Apple Developer Program membership is sufficient. The app does
not need an App Store record, App Review, or an Apple Developer Enterprise
Program membership.

1. Enable two-factor authentication on the Apple Account that will own the app.
2. Enroll as an Individual with the account holder's legal name at
   <https://developer.apple.com/programs/enroll/>.
3. After the membership becomes active, record the Team ID shown in Membership
   details.
4. Create and install a `Developer ID Application` certificate. A
   `Developer ID Installer` certificate is not needed because releases contain
   a zip archive of the app rather than an installer package.
5. Verify that the certificate and its private key are available:

   ```sh
   security find-identity -v -p codesigning
   ```

6. Export the `Developer ID Application` identity and private key from
   Keychain Access as an encrypted `.p12` file. Keep an encrypted offline
   backup and never commit it.
7. Create an app-specific password for notarization at
   <https://account.apple.com/> under **Sign-In and Security**.

The project already enables Hardened Runtime and uses the bundle identifier
`dev.worktreecleaner.app`.

## Export the Sparkle signing key

The Sparkle private key is separate from the Apple Developer ID identity. The
public key is stored in the Xcode project and is safe to publish. Export and
back up the existing private key generated under the
`dev.worktreecleaner.app` account:

```sh
xcodebuild \
  -resolvePackageDependencies \
  -project WorktreeCleaner.xcodeproj \
  -scheme WorktreeCleaner \
  -derivedDataPath /tmp/worktree-cleaner-derived

/tmp/worktree-cleaner-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account dev.worktreecleaner.app \
  -x /secure/location/worktree-cleaner-sparkle-key
```

Losing this key complicates Sparkle key rotation. Treat the exported file like a
password.

## Configure GitHub Actions

The release workflow is
[`.github/workflows/release.yml`](../.github/workflows/release.yml). It only
publishes a manually dispatched release from `main`.

### Create the release environment

In the GitHub repository:

1. Open **Settings → Environments** and create an environment named
   `release`.
2. Restrict deployment branches to `main`. This restriction is required even
   though the workflow also checks its ref.
3. Add the account holder as a required reviewer. A sole maintainer must leave
   self-review enabled to approve their own release.
4. Add the environment variable `APPLE_TEAM_ID`. For compatibility, the
   workflow also accepts it as an environment secret, but a variable is
   preferred because the Team ID is not sensitive.
5. Add the environment secrets below.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ACCOUNT` | Apple Account email |
| `APPLE_APP_PASSWORD` | App-specific notarization password |
| `SPARKLE_ED_KEY_BASE64` | Base64-encoded exported Sparkle private key |

Create the Base64 values on the Mac that holds the private files:

```sh
base64 -i /secure/location/developer-id.p12 | pbcopy
base64 -i /secure/location/worktree-cleaner-sparkle-key | pbcopy
```

Paste each clipboard value into its matching GitHub environment secret. Do not
paste these values into issues, pull requests, workflow files, or command-line
arguments.

The workflow creates a random temporary keychain, imports the Developer ID
identity, stores the notarization profile, and restores the Sparkle private key
only for the duration of the GitHub-hosted runner. Fork and pull-request
workflows do not reference the `release` environment.

The job grants its built-in `GITHUB_TOKEN` only `contents: write` permission.
It does not need a personal access token.

### Test signing and notarization

Before the repository is public, run the workflow from `main` with `dry_run`
enabled. A dry run imports every configured credential, builds and signs the
app, submits it to Apple for notarization, staples the ticket, and runs the
Gatekeeper check. It does not create a GitHub Release or tag. The release
environment approval still applies.

## Publish with GitHub Actions

1. Make the repository public.
2. Open **Actions → Release → Run workflow**.
3. Select the `main` branch.
4. Enter:
   - `version`: a new `x.y.z` version, or a prerelease such as
     `0.1.0-alpha.1`.
   - `build_number`: a positive integer greater than every previous release.
   - `release_notes`: Markdown shown by GitHub and embedded in the signed
     Sparkle appcast.
   - `dry_run`: leave disabled for a real release.
5. Start the workflow and approve the `release` environment deployment.
6. Confirm that every signing, notarization, and Gatekeeper validation step
   succeeds.
7. Verify the new GitHub Release and the updated
   <https://github.com/vincentbel/worktree-cleaner/releases/latest/download/appcast.xml>.

The workflow refuses to publish from a branch other than `main`, to a private
repository, or over an existing version tag. It creates a draft release, uploads
the update archive and appcast, and only then publishes the release so clients
never see an incomplete update.

A version containing a hyphen is published as a GitHub Pre-release and is not
marked as Latest. Its appcast is pinned to that prerelease's release asset;
stable versions continue to use the `releases/latest/download/appcast.xml`
feed.

## Local fallback

To publish from the Mac instead of GitHub Actions, store the notarization
credentials in the login keychain. The command prompts for the app-specific
password so it does not enter shell history:

```sh
xcrun notarytool store-credentials worktree-cleaner-notary \
  --apple-id YOUR_APPLE_ACCOUNT \
  --team-id YOUR_TEAM_ID
```

Build and notarize:

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

Publish only after reviewing the generated appcast:

```sh
scripts/publish-release.sh 0.2.0
```

The publishing script requires an authenticated GitHub CLI.

## Verify the update path

Test the complete update path with a previously notarized build. A current
development build proves that Sparkle compiles, but it does not exercise the
production Developer ID, notarization, archive signature, and replacement path.
The first end-to-end update test therefore requires two notarized releases.
