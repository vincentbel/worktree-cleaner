#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: DEVELOPMENT_TEAM=TEAM_ID $0 <version> <build-number>" >&2
  exit 64
fi

release_version="$1"
build_number="$2"

if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use x.y.z format: $release_version" >&2
  exit 64
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build number must be a positive integer: $build_number" >&2
  exit 64
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "DEVELOPMENT_TEAM is required." >&2
  exit 64
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
release_repository="${RELEASE_REPOSITORY:-vincentbel/worktree-cleaner-releases}"
feed_url="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/${release_repository}/main/appcast.xml}"
download_url_base="${SPARKLE_UPDATE_BASE_URL:-https://github.com/${release_repository}/releases/download/v${release_version}}"
download_url_prefix="${download_url_base%/}/"
sparkle_account="${SPARKLE_ACCOUNT:-dev.worktreecleaner.app}"
notary_profile="${NOTARY_KEYCHAIN_PROFILE:-worktree-cleaner-notary}"
output_root="${RELEASE_OUTPUT_DIR:-$repository_root/build/release/$release_version}"
derived_data="$output_root/DerivedData"
archive_path="$output_root/WorktreeCleaner.xcarchive"
export_directory="$output_root/export"
updates_directory="$output_root/updates"
notarization_archive="$output_root/WorktreeCleaner-notarization.zip"
update_archive_name="WorktreeCleaner-${release_version}.zip"
update_archive="$updates_directory/$update_archive_name"

if [[ -e "$output_root" ]]; then
  echo "Release output already exists; choose a new version or remove it explicitly:" >&2
  echo "  $output_root" >&2
  exit 73
fi

mkdir -p "$updates_directory"

existing_appcast="$updates_directory/appcast.xml.download"
if curl --fail --location --silent --show-error "$feed_url" --output "$existing_appcast"; then
  mv "$existing_appcast" "$updates_directory/appcast.xml"
  echo "Reusing the published appcast history."
else
  rm -f "$existing_appcast"
  echo "No published appcast found; generating the first feed."
fi

xcodebuild \
  -resolvePackageDependencies \
  -project "$repository_root/WorktreeCleaner.xcodeproj" \
  -scheme WorktreeCleaner \
  -derivedDataPath "$derived_data"

xcodebuild \
  -project "$repository_root/WorktreeCleaner.xcodeproj" \
  -scheme WorktreeCleaner \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$derived_data" \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$release_version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  SPARKLE_FEED_URL="$feed_url" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_directory" \
  -exportOptionsPlist "$repository_root/Config/ExportOptions.plist" \
  -allowProvisioningUpdates

application_path="$export_directory/WorktreeCleaner.app"
if [[ ! -d "$application_path" ]]; then
  echo "Export did not produce the expected app: $application_path" >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "$application_path"
ditto -c -k --sequesterRsrc --keepParent "$application_path" "$notarization_archive"
xcrun notarytool submit \
  "$notarization_archive" \
  --keychain-profile "$notary_profile" \
  --wait
xcrun stapler staple "$application_path"
xcrun stapler validate "$application_path"
spctl --assess --type execute --verbose=4 "$application_path"

ditto -c -k --sequesterRsrc --keepParent "$application_path" "$update_archive"

generate_appcast="$(find "$derived_data/SourcePackages/artifacts" -type f -path '*/Sparkle/bin/generate_appcast' -print -quit)"
if [[ -z "$generate_appcast" || ! -x "$generate_appcast" ]]; then
  echo "Could not locate Sparkle's generate_appcast tool." >&2
  exit 69
fi

appcast_options=(
  --download-url-prefix "$download_url_prefix"
  --link "https://github.com/$release_repository"
  --maximum-versions 10
  --maximum-deltas 0
  -o "$updates_directory/appcast.xml"
)

if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  appcast_options+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
else
  appcast_options+=(--account "$sparkle_account")
fi

if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
  if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    echo "Release notes file does not exist: $RELEASE_NOTES_FILE" >&2
    exit 66
  fi
  cp "$RELEASE_NOTES_FILE" "$updates_directory/WorktreeCleaner-${release_version}.md"
  appcast_options+=(--embed-release-notes)
fi

"$generate_appcast" "${appcast_options[@]}" "$updates_directory"

echo
echo "Release artifacts are ready:"
echo "  $update_archive"
echo "  $updates_directory/appcast.xml"
echo
echo "Publish them only after reviewing the generated appcast:"
echo "  $repository_root/scripts/publish-release.sh $release_version $updates_directory"
