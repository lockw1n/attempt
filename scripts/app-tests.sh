#!/usr/bin/env bash
#
# T-1.94 / G-6.3: run the app target's own test bundle (TR-1.10, NFR-1.7, FR-1.2.3).
#
# NOT `TR-1.12`. That is the snapshot requirement and it is T-1.08's; this bundle exists for the
# class of defect a snapshot reference cannot see, so keying it there would tick the one claim it
# argues against making.
#
#   scripts/app-tests.sh                       # the booted simulator, or the first available one
#   scripts/app-tests.sh --device 'iPhone lockw1n'
#   scripts/app-tests.sh --simulator 'iPhone 17 Pro'
#   scripts/app-tests.sh --only AttemptTests/ScreenWiringTests
#
# WHY THIS EXISTS, AND WHY IT IS NOT A BARE `xcodebuild test`. Two preconditions belong to the
# destination rather than to the tests, and neither announces itself:
#
#   1. SwiftUI builds accessibility elements lazily and only while an accessibility client is
#      active. Without one, a hosted view lays out at the right size, draws, and answers
#      `accessibilityElements` with an EMPTY ARRAY — so a screen with every control intact reads
#      exactly like one whose controls were deleted. `ApplicationAccessibilityEnabled` is what turns
#      it on for a simulator; a device needs Accessibility turned on in Settings.
#   2. The simulator must be booted before `simctl spawn` can write that default at all. An
#      unbooted device answers "Bad or unknown session", which reads like a permissions problem.
#
# Setting (1) here rather than documenting it is the difference between a named step and something
# every task re-discovers, which is the whole of what this task chose.
#
# A GATE WITH A KNOWN BLIND SPOT IS BETTER THAN ONE THAT REPORTS SOMETHING DIFFERENT EACH RUN, and
# this one has a known blind spot, in check-doc-links.sh's own words: activation reads the
# accessibility tree, so a control that publishes no accessibility element is not in the tree and is
# never checked, whatever the screen draws. Neither is a control that IS in the tree but is covered,
# mis-sized, or behind a gesture that wins. A finger sees those; nothing here does. This proves that
# a screen's parts are still wired to the screen, never that they can be touched.
#
# WHEN IT RUNS, AND WHEN IT DOES NOT. CI's `build` job, which triggers on `main` only — so this
# gate is enforced at the first `dev` -> `main` merge and not before, and T-17.11's defect (the
# class it was built for) landed on `dev`. It is deliberately NOT in CLAUDE.md's verification chain:
# that chain holds every `lint`-job gate cheap enough to run by hand, and this one is a whole app
# build. Run it by hand after a task that changes how a screen attaches its parts — the modifiers
# on a view, not the views under them, which is the only diff this can see and a reference cannot.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Attempt.xcodeproj"
SCHEME="Attempt"
ONLY="AttemptTests"
DEVICE_NAME=""
SIMULATOR_NAME=""

while (( $# )); do
    case "$1" in
        --device) DEVICE_NAME="${2:?--device needs a device name}"; shift 2 ;;
        --simulator) SIMULATOR_NAME="${2:?--simulator needs a simulator name}"; shift 2 ;;
        --only) ONLY="${2:?--only needs a test identifier}"; shift 2 ;;
        *) echo "app-tests.sh: unknown argument: $1" >&2; exit 64 ;;
    esac
done

if [[ -n "$DEVICE_NAME" ]]; then
    # A DEVICE DESTINATION IS THE WHOLE POINT OF THE BUNDLE BEING HOSTED. `xcodebuild` refuses an
    # SPM test bundle here — "Tool-hosted testing is unavailable on device destinations. Select a
    # host application" — and a hosted bundle is the host it is asking for.
    #
    # RESOLVED TO A UDID, NEVER PASSED AS A NAME. Two reasons, and the second is the serious one:
    # `platform=iOS,name=…` was measured on 2026-09-10 to fail with "Unable to find a destination
    # matching the provided destination specifier" against a name `-showdestinations` was listing
    # verbatim at that moment; and every paired phone is a destination, so a name that matches the
    # wrong one builds and installs onto somebody else's device without saying so. This is the
    # third spelling of one phone in this repository — CoreDevice UUID, hardware UDID, and the
    # name — and docs/decisions.md records what the first two cost. `-showdestinations` is the
    # only one of the three that speaks xcodebuild's own.
    DEVICE_UDID="$(xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null \
        | python3 -c "
import re, sys
rows = [dict(re.findall(r'(\w+):([^,}]+)', line)) for line in sys.stdin if 'platform:iOS,' in line]
matches = [r for r in rows if r.get('name', '').strip() == '''$DEVICE_NAME'''
           or r.get('id', '').strip() == '''$DEVICE_NAME''']
if len(matches) != 1:
    names = ', '.join(repr(r.get('name', '?').strip()) for r in rows)
    sys.exit('no single device matches \'$DEVICE_NAME\'; attached: ' + (names or '(none)'))
print(matches[0]['id'].strip())
")"
    echo "destination: device '$DEVICE_NAME' ($DEVICE_UDID)"
    # Two preconditions this script cannot satisfy for a device, unlike the simulator's:
    echo "note: ScreenWiringTests needs Accessibility switched on on that device — see this header."
    echo "note: signing asks for the login keychain once per signed product. Answer the first"
    echo "      prompt with 'Always Allow' rather than 'Allow', or they arrive one per framework."
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS,id=$DEVICE_UDID" \
        -only-testing:"$ONLY"
    exit 0
fi

# A simulator. Resolve one udid and hold it: `platform=iOS Simulator,name=…` may pick a different
# device from the one the default was written to, which would silently reintroduce precondition (1).
if [[ -n "$SIMULATOR_NAME" ]]; then
    UDID="$(xcrun simctl list devices available -j \
        | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(x['udid'] for v in d.values() for x in v if x['name']=='$SIMULATOR_NAME'))")"
else
    UDID="$(xcrun simctl list devices available -j \
        | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; xs=[x for v in d.values() for x in v if x['name'].startswith('iPhone')]; print(next((x['udid'] for x in xs if x['state']=='Booted'), xs[0]['udid']))")"
fi

echo "destination: simulator $UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
# Precondition (1). Written every run rather than checked: it costs nothing, and a check that found
# it already set would be reporting on state some other run happened to leave behind.
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true

xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -only-testing:"$ONLY"
