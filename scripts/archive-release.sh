#!/usr/bin/env bash
#
# T-1.72 / DOD-1.4, DOD-1.6: archive the app for TestFlight, and record what App Store Connect
# needs that no build produces.
#
#   scripts/archive-release.sh [--export] [--allow-provisioning-updates]
#
# WHY A SCRIPT. The archive is the one build in this project nobody can reproduce from the
# verification chain: `build-packages.sh` never touches the app target, and every other app build
# in the repo is a simulator build. Getting it wrong is not visible until an upload is rejected or,
# worse, until two testers' devices fail to see each other's data.
#
# WHAT IT DOES NOT DO. It does not upload, it does not create testers, and it does not touch the
# App Store Connect listing. Those are outward-facing writes against the author's account; this
# prints what they need and stops.
#
# THE CLOUDKIT ENVIRONMENT FOLLOWS THE SIGNING, NOT A BUILD SETTING. The app pins no
# `com.apple.developer.icloud-container-environment` key on purpose (T-1.70 measured this against
# the real container): a development-signed build reaches the CloudKit *Sandbox*, a
# distribution-signed one reaches *Production*. So this script's export method is what decides
# which schema the build talks to, and `DOD-1.4`'s "Production, not Development" is satisfied by
# archiving and exporting for the store rather than by setting anything. Do not add that key to
# make it explicit — a wrong value there is invisible until two devices fail to sync.
#
# SIGNING. As of T-1.72 the only identity on the author's machine is
# `Apple Development: aleksey.kotsuba@gmail.com (ZPZ5J3H9WT)`. An App Store export needs an
# `Apple Distribution` certificate, which does not exist yet; `--allow-provisioning-updates` lets
# xcodebuild create it in the portal, against the account's certificate quota. That is a portal
# write, which is why it is a flag rather than the default.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Attempt"
PROJECT="Attempt.xcodeproj"
BUILD_DIR="${BUILD_DIR:-build}"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

do_export=0
# Left unset rather than empty: see the expansion at the xcodebuild calls below.
provisioning_args=()

for arg in "$@"; do
    case "$arg" in
        --export) do_export=1 ;;
        --allow-provisioning-updates) provisioning_args+=(-allowProvisioningUpdates) ;;
        *) echo "error: unknown argument $arg" >&2; exit 1 ;;
    esac
done

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE"

echo "archiving $SCHEME (Release, generic iOS device) ..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    ${provisioning_args[@]+"${provisioning_args[@]}"}

echo
echo "archive: $ARCHIVE"

# What actually shipped, read off the archived bundle rather than off the project file — the same
# argument audit-app-build-settings.sh makes for -showBuildSettings over reading .pbxproj.
PLIST="$ARCHIVE/Products/Applications/$SCHEME.app/Info.plist"
if [[ -f "$PLIST" ]]; then
    echo
    echo "what the archive declares:"
    for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion MinimumOSVersion; do
        printf '  %-28s %s\n' "$key" "$(plutil -extract "$key" raw -o - "$PLIST" 2>/dev/null || echo '(absent)')"
    done
fi

if (( do_export )); then
    OPTIONS="$BUILD_DIR/ExportOptions.plist"
    cat > "$OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>54A7S98K2Q</string>
	<key>uploadSymbols</key>
	<true/>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST
    rm -rf "$EXPORT_DIR"
    echo
    echo "exporting for App Store Connect ..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$OPTIONS" \
        -exportPath "$EXPORT_DIR" \
        ${provisioning_args[@]+"${provisioning_args[@]}"}
    echo "export: $EXPORT_DIR"
fi

cat <<'NEXT'

------------------------------------------------------------------------------
STILL TO DO BY HAND — none of it is a build step, and this script does none of it.

1. UPLOAD. Xcode → Window → Organizer → the archive above → Distribute App →
   TestFlight & App Store. Or `xcrun altool`/`notarytool` with an app-specific
   password. Uploading is an outward-facing write; it is deliberately not here.

2. APP PRIVACY LABEL (G-5.3). The answers, from what the shipped build actually
   does rather than from intent:

     Does this app collect data?            NO.

   That single answer is the whole label, and each input that could have changed
   it has been checked:
     - Analytics: none. TR-1.11 (TelemetryDeck) is DEFERRED → Phase 5, so no
       SDK ships. scripts/check-no-third-party.sh proves it mechanically on
       every run of the verification chain.
     - HealthKit (G-5.4, T-1.51): body mass is READ, on device, only on an
       explicit import. An imported reading becomes a weigh-in row in the
       lifter's own log, so with sync on (the default) it mirrors into the
       lifter's OWN private CloudKit database — the same place, and the same
       argument, as the anonymous ID below. It goes nowhere else. Apple's
       "collect" is data transmitted to the developer or a third party; the
       user's own iCloud is neither, so it is not declared. The in-app policy
       and the Health usage description say the same thing — keep all three
       in step, since a claim that Health data "stays on this device" was
       false from the day sync went on by default.
     - The anonymous user ID (TR-1.10): a column on the user's settings row.
       With sync on it is written into the user's OWN private CloudKit
       database, which Apple treats as the user's storage rather than the
       developer's collection.
     - iCloud sync (FR-1.12.1): the private database is the user's. Attempt has
       no server, no account, and no way to read it.

   If any of those four changes, this answer changes with it.

3. PRIVACY POLICY URL. https://lockw1n.github.io/attempt/privacy.html
   Published by .github/workflows/deploy-content.yml, rendered from the About
   screen's own strings by scripts/make-privacy-policy.py. It exists only after
   that workflow has run on main — check the URL resolves before submitting.

4. TESTERS. Three external testers, per DOD-1.6, and the date they receive the
   build is that criterion's clock start. Record both in
   docs/phase-1/tasks/T-1.72-release-and-testflight.md, which is where T-1.87
   reads them from. Recruit one on an iPhone 11 or 12 if you can: it is free
   here and it is the only slow-end hardware this project will see, though it
   does NOT discharge DOD-1.2 — that is still T-1.83's to answer.
------------------------------------------------------------------------------
NEXT
