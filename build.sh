#!/usr/bin/env bash
# Vanadium backport build driver — drop-in replacement for the ungoogled-chromium
# build.sh so the existing GitHub Actions harness (build-steps.yml +
# .github/actions/build-stage) can drive it unchanged.
#
#   ./build.sh --arch arm64 --target webview_target [--resume] [--install-deps]
#
# Recipe: Chromium at Vanadium's tag -> gclient sync -> gclient runhooks
# (prebuilt node_modules, no npm) -> Vanadium's patches via git am -> minSdk 29
# -> vanadium_webview_apk (fallback system_webview_apk).
set -eu -o pipefail

ARCH=arm64
TARGET=webview_target
RESUME=n
INSTALL_DEPS=n
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --resume) RESUME=y; shift ;;
        --install-deps) INSTALL_DEPS=y; shift ;;
        --prepare-only) shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

VANADIUM_VERSION=${VANADIUM_VERSION:-158.0.8127.92}
CHROMIUM_TAG=${CHROMIUM_TAG:-$VANADIUM_VERSION}
SKIP_PATCHES=${SKIP_PATCHES:-"0022 0024"}
here=$(pwd)
out=src/out/Default

case "$ARCH" in
    arm64) cpu=arm64 ;;
    arm)   cpu=arm ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac
log() { printf '\n== %s\n' "$*"; }

# ------------------------------------------------------------------ depot_tools
if [ ! -d depot_tools ]; then
    log "cloning depot_tools"
    git clone -q --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$here/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0

# ------------------------------------------------------------------ source
if [ ! -d src/.git ]; then
    log "fetching Chromium $CHROMIUM_TAG"
    mkdir -p src
    git init -q src
    git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
    git -C src fetch -q --depth 1 origin "refs/tags/$CHROMIUM_TAG:refs/tags/$CHROMIUM_TAG"
fi
git -C src -c advice.detachedHead=false checkout -q --force "refs/tags/$CHROMIUM_TAG"

# ------------------------------------------------------------------ deps
if [ ! -f src/.gclient-synced ] || [ "$RESUME" != y ]; then
    log "gclient sync + runhooks (this is the long part)"
    cat > .gclient <<EOF
solutions = [{
  "name": "src",
  "url": "https://chromium.googlesource.com/chromium/src.git",
  "managed": False,
  "custom_vars": {"checkout_pgo_profiles": False, "checkout_traffic_annotation_tools": False},
}]
target_os = ["android"]
EOF
    gclient sync --nohooks --no-history --shallow -D --force --jobs 16 \
        --revision "src@$(git -C src rev-parse HEAD)"
    gclient runhooks
    : > src/.gclient-synced
fi

if [ "$INSTALL_DEPS" = y ]; then
    log "installing Chromium build deps"
    ( cd src && ./build/install-build-deps.sh --no-prompt --android --unsupported ) || true
fi

# ------------------------------------------------------------------ patches
if [ ! -f src/.vanadium-patched ] || [ "$RESUME" != y ]; then
    log "applying Vanadium $VANADIUM_VERSION patches (minSdk 29; skipping: ${SKIP_PATCHES:-none})"
    applied=0
    for p in "$here"/vanadium/patches/*.patch; do
        base=$(basename "$p")
        skip=no
        for s in $SKIP_PATCHES; do case "$base" in "$s"*) skip=yes ;; esac; done
        [ "$skip" = yes ] && continue
        if git -C src -c user.name=build -c user.email=build@localhost am -q --whitespace=nowarn --keep-non-patch "$p"; then
            applied=$((applied + 1))
        else
            echo "FATAL: $base did not apply" >&2
            git -C src am --abort || true
            exit 42
        fi
    done
    echo "applied $applied patches"
    : > src/.vanadium-patched
fi

# ------------------------------------------------------------------ configure
if [ ! -f "$out/build.ninja" ]; then
    log "gn gen ($ARCH, minSdk 29)"
    mkdir -p "$out"
    cp "$here"/vanadium/args.gn "$out/args.gn"
    {
        echo ''
        echo '# --- backport overrides ---'
        echo 'target_os = "android"'
        echo "target_cpu = \"$cpu\""
        echo 'min_sdk_version = 29'
        echo 'system_webview_package_name = "app.vanadium.webview"'
        echo 'is_official_build = false'
        echo 'symbol_level = 0'
        echo 'blink_symbol_level = 0'
        echo 'v8_symbol_level = 0'
        echo 'use_thin_lto = false'
        echo 'dcheck_always_on = false'
        echo 'treat_warnings_as_errors = false'
        echo 'android_static_analysis = "off"'
    } >> "$out/args.gn"
    ( cd src && gn gen out/Default )
fi

# ------------------------------------------------------------------ build
ninja_target=system_webview_apk
if [ "$TARGET" = webview_target ] || [ "$TARGET" = vanadium_webview_apk ]; then
    ninja_target=vanadium_webview_apk
fi
log "building $ninja_target"
rc=0
timeout -k 5m -s INT "${NINJA_TIMEOUT:-16200s}" \
    autoninja -C "$out" "$ninja_target" || rc=$?
if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
    echo "ninja reached the ${NINJA_TIMEOUT:-16200s} budget with work remaining"
    echo "status=running" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
fi
if [ "$rc" -ne 0 ]; then
    log "$ninja_target failed, trying system_webview_apk"
    autoninja -C "$out" system_webview_apk
fi

echo "status=completed" >> "${GITHUB_OUTPUT:-/dev/null}"
ls -l "$out/apks" 2>/dev/null | sed 's/^/  /' || true
