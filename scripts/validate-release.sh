#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Release validation failed: commit or stash all changes before archiving."
  exit 1
fi

if rg -n "example\.com|YOUR_|example\.supabase" Config/Base.xcconfig Config/Production.xcconfig; then
  echo "Release validation failed: placeholder configuration remains."
  exit 1
fi

google_ios_client_id="$(awk -F ' = ' '/^GOOGLE_IOS_CLIENT_ID =/ { print $2 }' Config/Production.xcconfig)"
google_server_client_id="$(awk -F ' = ' '/^GOOGLE_SERVER_CLIENT_ID =/ { print $2 }' Config/Production.xcconfig)"
google_reversed_client_id="$(awk -F ' = ' '/^GOOGLE_REVERSED_CLIENT_ID =/ { print $2 }' Config/Production.xcconfig)"
if [[ "$google_ios_client_id" != *.apps.googleusercontent.com || \
      "$google_server_client_id" != *.apps.googleusercontent.com || \
      "$google_reversed_client_id" != com.googleusercontent.apps.* ]]; then
  echo "Release validation failed: Google OAuth client IDs are missing or malformed."
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
  "https://projectleafy.app/privacy/" \
  "https://projectleafy.app/terms/" \
  "https://projectleafy.app/support/"; do
  if ! curl --fail --silent --show-error --head "$url" >/dev/null; then
    echo "Release validation failed: $url is unavailable."
    exit 1
  fi
done

production_url="$(awk -F ' = ' '/^SUPABASE_URL =/ { print $2 }' Config/Production.xcconfig | sed 's|/$()|/|g')"
production_key="$(awk -F ' = ' '/^SUPABASE_PUBLISHABLE_KEY =/ { print $2 }' Config/Production.xcconfig)"

required_functions=(
  save-nutrition-plan manage-legal-acceptance daily-nutrition
  weight-fluctuation-context manage-daily-checkin manage-weight-entry
  manage-food-entry discover-food-product manage-catalog-contribution
  estimate-meal nutrition-chat delete-account
)
for function_name in "${required_functions[@]}"; do
  http_status="$(curl --max-time 15 --silent --output /dev/null --write-out '%{http_code}' \
    --request POST "$production_url/functions/v1/$function_name" \
    --header 'Content-Type: application/json' \
    --header "apikey: $production_key" \
    --data '{}')"
  if [[ "$http_status" == "000" || "$http_status" == "404" ]]; then
    echo "Release validation failed: production function $function_name is unavailable (HTTP $http_status)."
    exit 1
  fi
done

legal_table_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$production_url/rest/v1/account_legal_acceptances?select=id&limit=0" \
  --header "apikey: $production_key")"
if [[ "$legal_table_status" != "200" ]]; then
  echo "Release validation failed: production legal-acceptance storage is unavailable (HTTP $legal_table_status)."
  exit 1
fi

plutil -lint Leafy/Resources/Info.plist Leafy/Resources/PrivacyInfo.xcprivacy Config/ExportOptions.plist >/dev/null

if rg -n "Nutrition data program|commercial analysis|early beta" Leafy auth-site; then
  echo "Release validation failed: retired commercial-program or beta copy remains."
  exit 1
fi

if ! rg -q "'PFQS-1.1'.*'active'" supabase/migrations/202608250002_pfqs_1_1_provisional_scores.sql; then
  echo "Release validation failed: PFQS 1.1 provisional-score activation migration is missing."
  exit 1
fi
echo "Leafy release configuration is ready."
