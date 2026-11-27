#!/usr/bin/env bash
# Build Vanadium's WebView at minSdk 29 (Android 10+) from Vanadium's own patch set.
#
# This is the "backport" recipe: stock Chromium + GrapheneOS's Vanadium patches,
# with the three minSdk-34 lines lowered to 29 and nothing else changed. No
# ungoogled-chromium patches, no hand-maintained fork: when Vanadium ships a new
# tag you bump VANADIUM_VERSION and rebuild.
#
#   ./build-vanadium.sh                 # arm64, tag below
#   CHROMIUM_ROOT=/mnt/ugc ./build-vanadium.sh
#   SKIP_PATCHES="" ./build-vanadium.sh # apply every patch, incl. the config APK
#
# Prerequisites on the machine: depot_tools on PATH, ~100 GB free, 16 GB+ RAM,
# and the Android build deps (build/install-build-deps.sh --android).
set -euo pipefail

VANADIUM_VERSION=${VANADIUM_VERSION:-158.0.8127.92}
CHROMIUM_TAG=${CHROMIUM_TAG:-$VANADIUM_VERSION}
TARGET=${TARGET:-vanadium_webview_apk}
FALLBACK_TARGET=${FALLBACK_TARGET:-system_webview_apk}
# 0022 = "config-like" APK: resources only (android:hasCode="false"), a GrapheneOS
#        convenience for sharing config between its apps. The WebView target has no
#        dependency on it (verified: patch 0025 has no config_apk reference), and the
#        Magisk module ships only VanadiumWebView.apk + an RRO. Not needed here.
# 0024 = dedicated browser target; we only build the WebView.
SKIP_PATCHES=${SKIP_PATCHES:-"0022 0024"}
root=${CHROMIUM_ROOT:-$PWD/chromium}
here=$(cd "$(dirname "$0")" && pwd)

log() { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------- source
if [[ ! -d $root/src/.git ]]; then
    log "fetching Chromium $CHROMIUM_TAG"
    mkdir -p "$root"
    git init -q "$root/src"
    git -C "$root/src" remote add origin https://chromium.googlesource.com/chromium/src.git
    git -C "$root/src" fetch -q --depth 1 origin "refs/tags/$CHROMIUM_TAG:refs/tags/$CHROMIUM_TAG"
fi
git -C "$root/src" -c advice.detachedHead=false checkout -q --force "refs/tags/$CHROMIUM_TAG"

# ---------------------------------------------------------------- patches
log "applying Vanadium $VANADIUM_VERSION patches (minSdk lowered to 29; skipping: ${SKIP_PATCHES:-none})"
cd "$root/src"
git -c user.name=build -c user.email=build@localhost am --abort 2>/dev/null || true
applied=0
for p in "$here"/vanadium/patches/*.patch; do
    base=$(basename "$p")
    skip=no
    for s in $SKIP_PATCHES; do
        case "$base" in "$s"*) skip=yes ;; esac
    done
    [ "$skip" = yes ] && { echo "  skip $base"; continue; }
    if git -c user.name=build -c user.email=build@localhost am -q --whitespace=nowarn --keep-non-patch "$p"; then
        applied=$((applied + 1))
    else
        echo "FATAL: $base did not apply. Resolve it, then re-run." >&2
        git am --abort || true
        exit 42
    fi
done
echo "applied $applied patches"

# ---------------------------------------------------------------- configure
log "gn gen"
out=out/Default
mkdir -p "$out"
cp "$here"/vanadium/args.gn "$out/args.gn"
{
    echo ''
    echo '# --- backport overrides (this repo) ---'
    echo 'target_os = "android"'
    echo 'target_cpu = "arm64"'
    echo 'min_sdk_version = 29'
    echo 'system_webview_package_name = "app.vanadium.webview"'
} >> "$out/args.gn"
gn gen "$out"

# ---------------------------------------------------------------- build
log "building $TARGET"
if ! autoninja -C "$out" "$TARGET"; then
    log "$TARGET failed, trying $FALLBACK_TARGET"
    autoninja -C "$out" "$FALLBACK_TARGET"
fi

log "done"
find "$out/apks" -maxdepth 1 -name '*.apk' -newer "$out/build.ninja" -printf '  %f  %s bytes\n' || true
