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
PREPARE_ONLY=n
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --resume) RESUME=y; shift ;;
        --install-deps) INSTALL_DEPS=y; shift ;;
        --prepare-only) PREPARE_ONLY=y; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

VANADIUM_VERSION=${VANADIUM_VERSION:-158.0.8127.92}
CHROMIUM_TAG=${CHROMIUM_TAG:-$VANADIUM_VERSION}
# All patches are applied. 0025 (the webview target) needs context lines that 0024
# adds to vanadium/BUILD.gn, so nothing can be skipped without breaking the series.
# The browser target and config APK exist as GN targets but are never built.
SKIP_PATCHES=${SKIP_PATCHES:-""}
here=$(pwd)
out=src/out/Default

case "$ARCH" in
    arm64) cpu=arm64 ;;
    arm)   cpu=arm ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 2 ;;
esac
log() { printf '\n== %s\n' "$*"; }
disk() { df -h / /mnt 2>/dev/null | sed 's/^/  /' || true; }

log "start: $ARCH, Vanadium $VANADIUM_VERSION, target $TARGET"
disk
free_gb=$(df -Pk /mnt 2>/dev/null | awk 'NR==2 {print int($4/1048576)}' || echo 0)
[ "${free_gb:-0}" -ge 30 ] || echo "::warning::only ${free_gb} GB free on /mnt; a Chromium build needs ~60-80 GB" >&2

# ------------------------------------------------------------------ depot_tools
if [ ! -d depot_tools ]; then
    log "cloning depot_tools"
    git clone -q --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
# Vanadium's gclient hook runs `git -C src/v8 am` itself, without -c identity flags.
# On a bare runner that dies with "Committer identity unknown", so set it globally.
git config --global user.name  "vanadium-backport build"
git config --global user.email "build@localhost"

export PATH="$here/depot_tools:$PATH"
# depot_tools ships without its bundled python until it is bootstrapped, and
# DEPOT_TOOLS_UPDATE=0 suppresses that bootstrap - which is why "gn gen" died with
# "python3_bin_reldir.txt not found". Bootstrap explicitly and verify before going on.
unset DEPOT_TOOLS_UPDATE || true
if [ ! -f depot_tools/python3_bin_reldir.txt ]; then
    log "bootstrapping depot_tools (ensure_bootstrap)"
    ( cd depot_tools && ./ensure_bootstrap ) || true
fi
if [ ! -f depot_tools/python3_bin_reldir.txt ]; then
    log "ensure_bootstrap did not take; trying update_depot_tools"
    ( cd depot_tools && ./update_depot_tools ) || true
fi
if [ ! -f depot_tools/python3_bin_reldir.txt ]; then
    echo "FATAL: depot_tools bootstrap did not produce python3_bin_reldir.txt" >&2
    echo "       (tried ensure_bootstrap and update_depot_tools)" >&2
    exit 1
fi
for tool in gclient gn autoninja; do
    command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: $tool not on PATH after bootstrap" >&2; exit 1; }
done
export DEPOT_TOOLS_UPDATE=0

# ------------------------------------------------------------------ source
# The harness packs src/ WITHOUT src/.git between jobs, so a resumed job has a
# patched tree but no git metadata. Use the markers to tell the two cases apart.
ALREADY_PREPARED=n
if [ -f src/.vanadium-patched ]; then ALREADY_PREPARED=y; fi

if [ "$ALREADY_PREPARED" = y ]; then
    log "resuming with an already fetched/patched tree (RESUME=${RESUME}, no .git expected)"
else
    if [ ! -d src/.git ]; then
        log "fetching Chromium $CHROMIUM_TAG"
        mkdir -p src
        git init -q src
        git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
        git -C src fetch -q --depth 1 origin "refs/tags/$CHROMIUM_TAG:refs/tags/$CHROMIUM_TAG"
    fi
    git -C src -c advice.detachedHead=false checkout -q --force "refs/tags/$CHROMIUM_TAG"
    git -C src config user.name "vanadium-backport build"
    git -C src config user.email "build@localhost"
fi

# ------------------------------------------------------------------ deps
if [ "$ALREADY_PREPARED" != y ] && [ ! -f src/.gclient-synced ]; then
    log "gclient sync + runhooks (this is the long part)"
    cp "$here/.gclient" .gclient
    # No --revision / -D / --force: Vanadium's .gclient marks the src solution
    # "managed: False", so gclient leaves our checked-out tag alone and only syncs the
    # DEPS children. -D would delete unversioned trees such as src/vanadium/.
    gclient sync --nohooks --no-history --shallow --jobs 16
    : > src/.gclient-synced
fi

if [ "$INSTALL_DEPS" = y ]; then
    log "installing Chromium build deps"
    ( cd src && ./build/install-build-deps.sh --no-prompt --android --unsupported ) || true
fi

# ------------------------------------------------------------------ patches
if [ "$ALREADY_PREPARED" != y ]; then
    log "applying Vanadium $VANADIUM_VERSION patches (minSdk 29; skipping: ${SKIP_PATCHES:-none})"
    git -C src am --abort 2>/dev/null || true
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

    # Now that the tree carries Vanadium's patches (which create src/vanadium/...),
    # run the hooks from Vanadium's .gclient: subproject patches for v8 and
    # third_party/search_engines_data/resources, plus the adblock filter lists that the
    # config APK embeds.
    log "gclient runhooks (subproject patches + filter lists)"
    if ! gclient runhooks; then
        # 21 filter lists are downloaded from third-party mirrors; one flake should not
        # throw away the fetch + sync + 304 patches. The hook is idempotent (it checks
        # `git diff` before patching and overwrites the lists), so retry once.
        log "runhooks failed, retrying once"
        gclient runhooks
    fi
    : > src/.vanadium-patched
fi

# ------------------------------------------------------------------ subprojects
# Handled by Vanadium's own gclient hook (tools/common/apply_subprojects_patches.py,
# wired in .gclient), which patches src/v8 and
# src/third_party/search_engines_data/resources with git am and skips [tmp]/[upstream]
# patches that no longer apply. It also fetches the adblock filter lists the config APK
# embeds. Running it ourselves would double-apply and use the wrong target directories.

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
        echo 'default_min_sdk_version = 29'   # global arg; the per-target value is set in patches 0022/0024/0025
        echo 'system_webview_package_name = "app.vanadium.webview"'
        echo 'is_official_build = false'
        echo 'symbol_level = 0'
        echo 'blink_symbol_level = 0'
        echo 'v8_symbol_level = 0'
        echo 'use_thin_lto = false'
        # Vanadium's args.gn sets is_cfi = true, and //build/config/compiler/compiler.gni
        # asserts "CFI requires ThinLTO". We build without ThinLTO to fit a 4-core/16 GB
        # runner, so CFI has to go too. This costs a security hardening (not privacy) -
        # to get it back, drop both use_thin_lto and is_cfi overrides and build on a
        # machine with 32 GB+ RAM.
        echo 'is_cfi = false'
        echo 'use_cfi_cast = false'   # only meaningful with is_cfi; keep the pair consistent
        echo 'use_siso = false'       # siso needs its CIPD binary; plain ninja for the chained parts
        echo 'dcheck_always_on = false'
        echo 'treat_warnings_as_errors = false'
        echo 'android_static_analysis = "off"'
    } >> "$out/args.gn"
    log "args.gn"
    sed 's/^/  /' "$out/args.gn"
    ( cd src && gn gen out/Default )
fi

# ------------------------------------------------------------------ build
disk
if [ "$PREPARE_ONLY" = y ]; then
    log "prepare-only: fetched, patched and configured; not building"
    exit 0
fi
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
