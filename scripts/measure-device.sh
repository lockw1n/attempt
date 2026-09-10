#!/usr/bin/env bash
#
# T-1.83 / NFR-1.1, NFR-1.2, NFR-1.5, NFR-1.6, DOD-1.2: take this phase's performance numbers on a
# real phone, repeatably.
# USAGE
#   scripts/measure-device.sh devices                 # what is connected, and what to pass below
#   scripts/measure-device.sh install                 # Release build -> the device
#   scripts/measure-device.sh launch [runs]           # NFR-1.1, cold launch, unattended
#   scripts/measure-device.sh signposts [seconds]     # NFR-1.2, NFR-1.6, NFR-17.4, while you drive it
#   scripts/measure-device.sh hitches [seconds]       # NFR-1.5, while you scroll History
#
#   ATTEMPT_DEVICE=<udid>  picks the device when more than one is connected, and is also how a
#                          booted SIMULATOR is measured: pass its UDID. Every figure in this task's
#                          table that says "simulator" was taken that way, so it is a documented
#                          route rather than a workaround. `hitches` is the exception — a simulator
#                          renders on the Mac's GPU, so NFR-1.5 has no answer there at all.
# END USAGE
#
# WHY A SCRIPT. `T-1.81` asked this task to decide between giving the launch sequence a test target
# and making the by-hand run "a named, repeatable step rather than something each task improvises".
# This is that step. The decision behind it is not a preference: an SPM test bundle CANNOT run on a
# device destination — `xcodebuild` refuses with "Tool-hosted testing is unavailable on device
# destinations. Select a host application" — and the app target has no test target to be that host
# (`T-1.94`). So no test in this repository can produce a device number, and the instrument has to
# be the shipping binary plus Instruments.
#
# RELEASE, NOT DEBUG, AND THAT CHANGES THE NUMBER. Every other measurement in this phase is at
# `-Onone` (`T-1.90` found the first Release-only defect for the same reason). A Debug figure and a
# Release figure are not comparable, so this builds Release and says so in its own output.
#
# WHAT IT CANNOT DO, AND DOES NOT PRETEND TO. Three of the four numbers need a finger on the glass:
# `NFR-1.2` needs a circle tapped, `NFR-1.5` needs History scrolled, `NFR-1.6` needs a set logged.
# Those subcommands record a trace for a fixed window and tell you what to do during it; only
# `launch` is unattended. A script that claimed otherwise would be reporting an idle device.
#
# THE FIXTURE. `NFR-1.5` and `NFR-1.6` are written against ~15,000 sets, which no store on a phone
# has. `scripts/make-scale-backup.py` grows a real full backup to that size; restore the file it
# writes through Settings > Restore before running `hitches` or `signposts`, or the numbers are
# about whatever happened to be on the device.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Attempt"
PROJECT="Attempt.xcodeproj"
BUNDLE_ID="lockw1n.Attempt"
BUILD_DIR="${BUILD_DIR:-build}"
DERIVED="$BUILD_DIR/device-measure"
TRACES="$BUILD_DIR/traces"

# TWO TOOLS, TWO IDENTIFIER SPACES, AND THEY DO NOT INTERCHANGE. `devicectl` names a device by its
# CoreDevice UUID (EE0672E2-...); `xctrace` names the same phone by its hardware UDID
# (00008130-...), and handed the other one it says "No devices found matching" and writes a 0-byte
# trace rather than failing. A recording that produced nothing looks exactly like one that produced
# nothing interesting, so each is resolved by its own tool below.

# The connected device, or an explanation. Never a default that silently picks the wrong phone:
# `DOD-1.2` is a claim about a named model, so every number this script takes has to name it too.
resolve_device() {
    if [[ -n "${ATTEMPT_DEVICE:-}" ]]; then
        printf '%s' "$ATTEMPT_DEVICE"
        return
    fi
    local connected
    connected=$(xcrun devicectl list devices 2>/dev/null \
        | awk '$0 ~ /connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-/) print $i }')
    local count
    count=$(printf '%s\n' "$connected" | grep -c . || true)
    if [[ "$count" -eq 0 ]]; then
        echo "measure-device.sh: no device is connected. Plug one in and unlock it." >&2
        exit 1
    fi
    if [[ "$count" -gt 1 ]]; then
        echo "measure-device.sh: more than one device is connected; set ATTEMPT_DEVICE." >&2
        xcrun devicectl list devices >&2
        exit 1
    fi
    printf '%s' "$connected"
}

# What the table in the task file has to say in every row, read from the phone rather than typed.
describe_device() {
    local udid="$1"
    xcrun devicectl device info details --device "$udid" 2>/dev/null \
        | awk -F': ' '
            /marketingName/ { model = $2 }
            /productType/ { type = $2 }
            /osVersionNumber/ { os = $2 }
            END { printf "%s (%s), iOS %s", model, type, os }'
}

# The same phone as `resolve_device`, spelled the way `xctrace` spells it.
xctrace_udid() {
    xcrun xctrace list devices 2>/dev/null \
        | awk '/^== Devices Offline ==/ { exit } /\(([0-9A-F]{8}-[0-9A-F]{16})\)/ {
                 match($0, /\(([0-9A-F]{8}-[0-9A-F]{16})\)/); print substr($0, RSTART + 1, RLENGTH - 2) }' \
        | head -1
}

# A recording that produced nothing, refused before anything reads it as an empty measurement.
#
# BY SIZE, BECAUSE NEITHER FILE TEST ANSWERS THE QUESTION. A `.trace` is a bundle, so `-d` is true
# the moment `xctrace` creates the directory — which it does before it discovers it has no device to
# record — and `-s` on a directory is true for the directory entry itself whatever is inside. The
# first version of this guard was `[[ -s "$out"/* ]] || [[ -d "$out" ]]`, which passes on an empty
# directory and therefore could not fail at all. A real recording is megabytes; the floor is set
# where nothing that recorded anything can fall below it.
require_trace() {
    local out="$1" kilobytes
    kilobytes=$(du -sk "$out" 2>/dev/null | awk '{ print $1 }')
    if [[ -z "$kilobytes" || "$kilobytes" -lt 8 ]]; then
        echo "measure-device.sh: $out recorded nothing (${kilobytes:-0} KB)." >&2
        echo "measure-device.sh: the commonest cause is the wrong UDID — xctrace wants the" >&2
        echo "  hardware one (00008130-...), not devicectl's CoreDevice UUID (EE0672E2-...)." >&2
        exit 1
    fi
}

# Everything an App Launch trace calls launching, summed — every lifecycle period before the app
# reaches `Foreground - Active`, which is the first frame being on screen.
#
# READ OFF THE TRACE RATHER THAN OFF A SUMMARY, because Instruments' own headline number is not
# exported. `life-cycle-period` is the table the App Launch template fills; its rows are the phases
# and `Foreground - Active` is the one that is not launching.
launch_milliseconds() {
    local trace="$1"
    xcrun xctrace export --input "$trace" \
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="life-cycle-period"]' 2>/dev/null \
        | python3 -c '
import re, sys
rows = re.findall(r"<row>(.*?)</row>", sys.stdin.read(), re.S)
total = 0
phases = []
for row in rows:
    duration = re.search(r"<duration[^>]*>(\d+)</duration>", row)
    period = re.search(r"<app-period[^>]*>([^<]*)</app-period>", row)
    if not (duration and period) or period.group(1).startswith("Foreground"):
        continue
    total += int(duration.group(1))
    phases.append((period.group(1), int(duration.group(1)) / 1e6))
if not phases:
    print("no launch recorded")
    raise SystemExit(1)
slowest = max(phases, key=lambda phase: phase[1])
print(f"{total / 1e6:8.1f} ms to first frame   (slowest phase: {slowest[0]}, {slowest[1]:.1f} ms)")
'
}

cmd_devices() {
    xcrun devicectl list devices
}

cmd_install() {
    local udid="$1"
    echo "measure-device.sh: building Release for $(describe_device "$udid")"
    xcodebuild build \
        -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -destination "platform=iOS,id=$udid" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates >/dev/null
    local app
    app=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$SCHEME.app" -print -quit)
    [[ -n "$app" ]] || { echo "measure-device.sh: no $SCHEME.app was built" >&2; exit 1; }
    xcrun devicectl device install app --device "$udid" "$app" >/dev/null
    echo "measure-device.sh: installed $app"
}

# NFR-1.1. The only unattended measurement here, because a cold launch needs no gesture.
#
# THE TEMPLATE MEASURES PROCESS START TO FIRST FRAME, which is not word-for-word "interactive
# dashboard" — the launch tab finishes its own read a little after the first frame is drawn. It is
# reported as what it is; the gap is named in the task file rather than folded into the figure.
cmd_launch() {
    local udid="$1" runs="${2:-5}"
    mkdir -p "$TRACES"
    echo "measure-device.sh: NFR-1.1, $runs cold launches on $(describe_device "$udid"), Release"
    local trace_udid
    trace_udid=$(xctrace_udid)
    for ((run = 1; run <= runs; run++)); do
        local out="$TRACES/launch-$run.trace"
        rm -rf "$out"
        # A trace whose recording failed is 0 bytes, and every later step would read it as an empty
        # launch. Fail on the record rather than on the parse, where the cause is still visible.
        xcrun xctrace record --device "$trace_udid" --template "App Launch" \
            --launch "$BUNDLE_ID" --output "$out" --time-limit 15s >/dev/null
        require_trace "$out"
        printf '  run %d: ' "$run"
        launch_milliseconds "$out"
        rm -rf "$out"
    done
    echo "measure-device.sh: process creation to first frame, under Instruments. NFR-1.1 budget 1.5 s."
}

# NFR-1.2, NFR-1.6 and NFR-17.4, from the signposts `PerformanceSignpost` emits.
#
# THE UNIFIED LOG RATHER THAN A TRACE, AND THAT IS A CORRECTION RATHER THAN A PREFERENCE.
# `xctrace record --attach` was the obvious instrument and it does not work here: attached to a
# simulator process it ignores its own `--time-limit` and has to be killed, and by bundle id it
# refuses outright ("Cannot find process matching name"). Signposts are unified-log entries, so
# `log stream --signpost` reads the same events, streams them as text, needs no attach, and costs
# kilobytes where a trace costs a fifth of a gigabyte. Measured 2026-09-10, both ways.
cmd_signposts() {
    local udid="$1" seconds="${2:-60}"
    mkdir -p "$TRACES"
    local out="$TRACES/signposts.log"
    cat <<'DRIVE'
measure-device.sh: recording. While it runs, on the phone:
  NFR-1.2   tap a planned exercise's circle, and log a set in a free workout.
  NFR-1.6   both of the above trigger a recompute; a long-history lift is the interesting one.
  NFR-17.4  leave the Train tab and come back, which re-reads the week.
DRIVE
    stream_signposts "$udid" "$seconds" >"$out" 2>&1 || true
    summarise_signposts "$out"
}

# The stream itself, which is spelled differently for the two kinds of device.
#
# **Backgrounded and killed rather than run under `timeout`**, which macOS does not ship — the
# GNU coreutils spelling is `gtimeout` and is not there either on a stock machine, so a script that
# reached for it would fail on the only kind of host that can talk to an iPhone.
stream_signposts() {
    local udid="$1" seconds="$2"
    local predicate="subsystem == \"$BUNDLE_ID\""
    if xcrun simctl list devices 2>/dev/null | grep -q "$udid"; then
        xcrun simctl spawn "$udid" \
            log stream --style compact --signpost --predicate "$predicate" &
    else
        xcrun log stream --device "$(xctrace_udid)" \
            --style compact --signpost --predicate "$predicate" &
    fi
    local streamer=$!
    sleep "$seconds"
    # SIGINT, NOT SIGTERM. `log stream` writes to a pipe here, so its output is block-buffered;
    # terminated it dies with the buffer unflushed and a short window reports no signposts at all,
    # which is indistinguishable from the app not having been driven. Interrupted, it flushes.
    kill -INT "$streamer" 2>/dev/null || true
    wait "$streamer" 2>/dev/null || true
}

# Begin/end pairs turned into durations, per requirement.
#
# PAIRED BY SIGNPOST ID, BECAUSE THESE INTERVALS OVERLAP. The first version paired per
# (category, name) in arrival order, on the argument that each interval is serialised by the actor
# or the main actor it runs on. That is false in both directions an interval can overlap itself:
# every write command spans an `await` on the write queued ahead of it — the reason a chain of
# pending writes exists at all — and the recomputer is a reentrant `actor`. FIFO pairing over a
# nested pair reports two durations that belong to neither interval: a 1000 ms answer with a 10 ms
# one inside it comes back as 990 and 20. `PerformanceSignpost` now stamps each interval with
# `makeSignpostID()`, and this pairs on that.
#
# AN UNPAIRED END OR BEGIN IS COUNTED AND SAID, NOT DROPPED. A window that opens or closes across
# an interval produces one of each, which is ordinary; a large count means the pairing is wrong
# rather than the window short, and it takes a printed number to tell those apart.
summarise_signposts() {
    tr -d '\0' <"$1" | python3 -c '
import re, sys, datetime
LINE = re.compile(
    r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) Sp .*"
    r"\[[^:]+:(\S+)\] \[spid ([^,]+), [^]]*?(begin|end)\] (\w+)")
LOOSE = re.compile(r" Sp .*\[[^]]*?(begin|end)\] \w+")
pending, done, orphans, loose = {}, [], 0, 0
for line in sys.stdin:
    found = LINE.search(line)
    if not found:
        loose += 1 if LOOSE.search(line) else 0
        continue
    stamp, category, spid, kind, name = found.groups()
    when = datetime.datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S.%f")
    key = (category, name, spid)
    if kind == "begin":
        pending[key] = when
    elif key in pending:
        done.append((category, (when - pending.pop(key)).total_seconds() * 1000))
    else:
        orphans += 1
if not done:
    if loose:
        print(f"  {loose} signpost line(s) carried no readable spid, so nothing could be paired.")
        print("  The log format changed; fix LINE in summarise_signposts before trusting a number.")
    else:
        print("  no signpost fired. Drive the app while it records.")
    raise SystemExit(1)
for category in sorted({entry[0] for entry in done}):
    values = sorted(entry[1] for entry in done if entry[0] == category)
    print(f"  {category:9s} n={len(values):3d}  min={values[0]:7.1f}  "
          f"median={values[len(values) // 2]:7.1f}  max={values[-1]:7.1f} ms")
if orphans or pending:
    print(f"  ({orphans} end(s) and {len(pending)} begin(s) fell outside the window.)")
'
}

# NFR-1.5. Needs the 15,000-set fixture already restored on the device.
#
# `--launch`, NOT `--attach`, AND `xctrace`'S OWN SPELLING OF THE UDID. Both halves are this task's
# own traps and this subcommand carried both of them until they were fixed: `xctrace record
# --attach` by bundle id refuses outright ("Cannot find process matching name"), and handed
# `devicectl`'s CoreDevice UUID rather than the hardware UDID `xctrace` writes a 0-byte trace and
# carries on. Neither failure says anything, which is why `|| true` is gone from here as well —
# a swallowed error and an empty measurement look identical afterwards.
#
# THE APP IS LAUNCHED, SO THE SCROLLING STARTS AFTER IT IS UP. The window covers the launch too;
# it is a hitch measurement over a scroll, and the first second of it is not that.
cmd_hitches() {
    local udid="$1" seconds="${2:-30}"
    mkdir -p "$TRACES"
    local out="$TRACES/hitches.trace"
    rm -rf "$out"
    echo "measure-device.sh: NFR-1.5 on $(describe_device "$udid"), Release."
    echo "measure-device.sh: recording ${seconds}s. The app launches — go to History and scroll hard."
    xcrun xctrace record --device "$(xctrace_udid)" --template "Animation Hitches" \
        --launch "$BUNDLE_ID" --output "$out" --time-limit "${seconds}s" >/dev/null
    require_trace "$out"
    echo "measure-device.sh: $out"
    echo "measure-device.sh: open it in Instruments; NFR-1.5 is the hitch rate over the scroll."
}

command="${1:-}"
shift || true

case "$command" in
    devices) cmd_devices ;;
    install) cmd_install "$(resolve_device)" ;;
    launch) cmd_launch "$(resolve_device)" "${1:-5}" ;;
    signposts) cmd_signposts "$(resolve_device)" "${1:-60}" ;;
    hitches) cmd_hitches "$(resolve_device)" "${1:-30}" ;;
    *)
        # Delimited rather than counted: a line added to the usage block above used to have to be
        # paid for by hand here, and was not — the block gained NFR-17.4 and this range did not.
        sed -n '/^# USAGE$/,/^# END USAGE$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//'
        exit 64
        ;;
esac
