#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

: "${ASC_KEY_ID:?Set ASC_KEY_ID to your App Store Connect API key ID.}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID to your App Store Connect issuer ID.}"

key_path="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
if [[ ! -f "$key_path" ]]; then
  echo "App Store Connect private key not found at $key_path"
  exit 1
fi

build_number="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
output_root="/tmp/leafy-testflight-${build_number}"
archive_path="$output_root/Leafy.xcarchive"
export_path="$output_root/export"

./scripts/validate-release.sh
xcodegen generate

xcodebuild archive \
  -project Leafy.xcodeproj \
  -scheme Leafy \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$archive_path" \
  CURRENT_PROJECT_VERSION="$build_number" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "Uploaded Leafy 0.1.0 (${build_number}) as an internal-only TestFlight build."
