#!/usr/bin/env bash
#
# G-5.3 / T-1.72: keep `ITSAppUsesNonExemptEncryption` honest.
#
#   scripts/check-exempt-encryption.sh [--self-test]
#
# WHY THIS EXISTS. `Config/Info.plist` declares that Attempt uses no encryption beyond Category 5
# Part 2's exemption — HTTPS through system APIs and nothing else. That is a legal declaration
# about the shipping binary, and it is the decaying kind: it was true when written, and the commit
# that makes it false is a commit about something else entirely. Nothing else in the chain can see
# it. SwiftLint reads style, the tests read behaviour, and `check-no-third-party.sh` proves only
# that no *dependency* brought crypto in — it says nothing about crypto written here.
#
# WHAT IT CHECKS. If the declaration is `false`, no shipping source may reach for an implementation
# of cryptography. If it is `true`, the app is claiming an export-compliance filing instead and
# this script has nothing to say.
#
# WHAT IT DOES NOT CATCH. Cryptography reached through a symbol not on the list below, and any
# reached by interpolation or `dlsym`. It reads the source, not the binary — the same limit
# `check-app-strings.sh` documents about itself. It also deliberately ignores tests: this is a
# claim about what ships.

set -euo pipefail

cd "$(dirname "$0")/.."

PLIST="Config/Info.plist"
KEY="ITSAppUsesNonExemptEncryption"

# Implementations of cryptography. Deliberately NOT here: `import Security` on its own, which is
# how the keychain is reached — storing a secret the system already protects is exempt, and
# banning it would make the script fire on code the declaration permits.
PATTERNS='import CryptoKit|import CommonCrypto|CCCrypt|CCCryptor|SecKeyEncrypt|SecKeyDecrypt|SecKeyCreateEncryptedData|SecKeyCreateDecryptedData|SymmetricKey|ChaChaPoly|AES\.GCM|SealedBox'

scan() {
    grep -rnE "$PATTERNS" --include="*.swift" "$@" 2>/dev/null || true
}

# THE POPULATION IS THE SHIPPING TREE: the app target and every package's `Sources`, the Feature
# packages included. `Packages/*/Sources` on its own reads as "every package" and silently misses
# `Packages/Features/*/Sources`, which is where most of the app's code lives — the first version
# of this script shipped with exactly that hole, and its self-test could not see it because the
# fixture is a directory of its own. Tests are deliberately out.
shipping_roots() {
    local root
    for root in Attempt Packages/*/Sources Packages/Features/*/Sources; do
        [[ -d "$root" ]] && printf '%s\n' "$root"
    done
}

if [[ "${1:-}" == "--self-test" ]]; then
    # The gate is only worth having if it fires. Same argument as check-translations.sh's.
    fixture="$(mktemp -d)"
    trap 'rm -rf "$fixture"' EXIT
    printf 'import CryptoKit\n' > "$fixture/Rogue.swift"
    if [[ -z "$(scan "$fixture")" ]]; then
        echo "FAIL: the encryption gate did not fire on a file that imports CryptoKit." >&2
        exit 1
    fi
    # Firing on a fixture proves the pattern, not the population. The population has to reach a
    # Feature package, and every root has to hold at least one Swift file — an empty root is a
    # glob that matched nothing.
    if ! shipping_roots | grep -q '^Packages/Features/[^/]*/Sources$'; then
        echo "FAIL: the shipping population does not reach Packages/Features/*/Sources." >&2
        exit 1
    fi
    while IFS= read -r root; do
        if [[ -z "$(find "$root" -name '*.swift' -print -quit)" ]]; then
            echo "FAIL: $root is in the shipping population but holds no Swift source." >&2
            exit 1
        fi
    done < <(shipping_roots)
    echo "ok — the encryption gate fires on non-exempt cryptography, over $(shipping_roots | wc -l | tr -d ' ') shipping roots."
    exit 0
fi

if [[ ! -f "$PLIST" ]]; then
    echo "error: $PLIST is missing — the declaration this script checks lives there." >&2
    exit 1
fi

declared="$(plutil -extract "$KEY" raw -o - "$PLIST" 2>/dev/null || echo "absent")"

if [[ "$declared" == "absent" ]]; then
    cat >&2 <<MSG
error: $KEY is not declared in $PLIST.

Without it every upload is held in TestFlight as "Missing Compliance" until the question is
answered by hand, which is what T-1.72 added the key to avoid.
MSG
    exit 1
fi

if [[ "$declared" != "false" ]]; then
    echo "  ok    declaration               $KEY is $declared — export compliance is filed, not claimed"
    exit 0
fi

roots=()
while IFS= read -r root; do roots+=("$root"); done < <(shipping_roots)
hits="$(scan "${roots[@]}")"

if [[ -n "$hits" ]]; then
    cat >&2 <<MSG
$PLIST declares $KEY = false, but the shipping sources implement cryptography:

$hits

One of the two is wrong. Either the code does not belong in a build making this declaration, or
the declaration is stale and the app now needs an export-compliance filing — which is an App Store
Connect answer and a legal question, not a build setting. Do not flip the key to silence this.
MSG
    exit 1
fi

echo "  ok    declaration               $KEY = false"
echo "  ok    shipping sources           no non-exempt cryptography"
