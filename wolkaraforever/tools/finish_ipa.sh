#!/bin/bash
# Finish the sideload .ipa after a build, by hand, when package_ipa.sh stops at signing
# (in an iCloud-synced checkout the build's files carry extended attributes that codesign
# refuses, and the packaging script exits without a word).
#
# Clears the attributes, signs every library and the app ad hoc, declares the two memory
# capabilities explicitly (a sideloader only asks for what the app declares, and without
# them the game gets the default memory budget and is killed loading into the world), checks
# that they are really there, and writes the .ipa into the repository folder with the date.
#
# usage: wolkaraforever/tools/finish_ipa.sh [output.ipa]
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
OUT=${1:-$ROOT/WolkaraForever-$(date +%m%d-%H%M).ipa}
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT";; esac

APP=build/platform/build/ipa-derived/Build/Products/Release-iphoneos/TolkaraDiagnostics.app
[ -d "$APP" ] || { echo "No built app at $APP - run wolkaraforever/tools/package_ipa.sh first."; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/App.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.developer.kernel.increased-memory-limit</key><true/>
<key>com.apple.developer.kernel.extended-virtual-addressing</key><true/>
</dict></plist>
EOF

mkdir "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
COPY="$WORK/Payload/TolkaraDiagnostics.app"
xattr -cr "$COPY"
for library in "$COPY"/Frameworks/*.dylib; do
    [ -f "$library" ] || continue
    codesign -f -s - "$library" 2>/dev/null || { echo "Could not sign $(basename "$library")"; exit 1; }
done
codesign -f -s - --entitlements "$WORK/App.entitlements" "$COPY" 2>/dev/null || { echo "Could not sign the app"; exit 1; }

DECLARED=$(codesign -d --entitlements - --xml "$COPY" 2>/dev/null || true)
for capability in increased-memory-limit extended-virtual-addressing; do
    printf '%s' "$DECLARED" | grep -q "com.apple.developer.kernel.$capability" ||
        { echo "Refusing: the signed app does not declare $capability."; exit 1; }
done

rm -f "$OUT"
(cd "$WORK" && zip -qryX "$OUT" Payload)
echo "Ready: $OUT ($(du -h "$OUT" | cut -f1)), memory capabilities declared."
echo "Install it over the existing app in SideStore (My Apps -> +)."
