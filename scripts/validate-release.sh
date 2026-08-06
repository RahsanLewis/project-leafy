#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Release validation failed: commit or stash all changes before archiving."
  exit 1
fi

if rg -n "example\.com|YOUR_|example\.supabase" Config/Base.xcconfig; then
  echo "Release validation failed: placeholder configuration remains."
  exit 1
fi

icon="Leafy/Resources/Assets.xcassets/AppIcon.appiconset/LeafyAppIcon.png"
if [[ ! -f "$icon" ]]; then
  echo "Release validation failed: App Store icon is missing."
  exit 1
fi

width="$(sips -g pixelWidth "$icon" | awk '/pixelWidth/ {print $2}')"
height="$(sips -g pixelHeight "$icon" | awk '/pixelHeight/ {print $2}')"
if [[ "$width" != "1024" || "$height" != "1024" ]]; then
  echo "Release validation failed: App Store icon must be 1024x1024."
  exit 1
fi

for url in \
  "https://rahsanlewis.github.io/leafy-legal/privacy/" \
  "https://rahsanlewis.github.io/leafy-legal/terms/" \
  "https://rahsanlewis.github.io/leafy-legal/support/"; do
  if ! curl --fail --silent --show-error --head "$url" >/dev/null; then
    echo "Release validation failed: $url is unavailable."
    exit 1
  fi
done

plutil -lint Leafy/Resources/Info.plist Leafy/Resources/PrivacyInfo.xcprivacy Config/ExportOptions.plist >/dev/null
echo "Leafy release configuration is ready."
