# Vanadium WebView backport to Android 10+ (API 29)

Branch: `vanadium-backport`. `master` and `experimental-webview-158` are untouched — if
this fails, the ungoogled-chromium work is still there.

## What this is

Instead of maintaining ~90 hand-ported patches against ungoogled-chromium, this branch
builds **GrapheneOS's Vanadium patch set directly** on stock Chromium, with the minimum
SDK lowered from 34 to 29.

Vanadium is not GrapheneOS-exclusive: its WebView is a standalone package
(`app.vanadium.webview`, no Trichrome library — confirmed in their `args.gn`, which has no
Trichrome targets at all). The only thing locking it to Android 14+ is three lines in their
own build targets:

```
patches/0022-Add-a-new-config-like-apk-target-for-building.patch:  +    min_sdk_version = 34
patches/0024-Add-dedicated-browser-target-for-Vanadium.patch:      +    min_sdk_version = 34
patches/0025-Add-dedicated-webview-target-for-Vanadium.patch:      +      min_sdk_version = 34
```

All three are already changed to `29` in `vanadium/patches/` on this branch. Nothing else
in their 304-patch series hardcodes an SDK level.

## The config APK (patches 0022 / 0024) is not needed

`0022` adds `vanadium/android_config/` — a **resources-only** APK
(`android:hasCode="false"`, no code, no shared library) that GrapheneOS uses to share
config between Vanadium apps. The WebView target does not reference it: patch `0025`
contains no `config_apk` / `vanadium_config` dependency.

The Magisk module proves the same thing from the other end — it ships only
`VanadiumWebView.apk` plus `Overlay/WebViewOverlay29.apk`, an RRO that whitelists
`app.vanadium.webview` in `config_webview_packages.xml`. No config APK.

So the script skips `0022` (config APK) and `0024` (browser target) by default and builds
only the WebView. It cannot be "folded into" the WebView APK because it is a separate
package by design — it is simply unnecessary here.

## Vanadium's own build plumbing (all of it, audited)

Their repo carries more than `patches/`. Everything is now wired:

| Piece | Handling |
|---|---|
| `patches/` (304) | `git am` in numeric order, nothing skipped |
| `subprojects_patches/v8` (4) | applied by **their** hook to `src/v8` — mandatory, without 0001 the build asserts on DrumBrake |
| `subprojects_patches/third_party/search_engines_data/resources` (3) | same hook, target is `src/third_party/search_engines_data/**resources**` (a separate repo) |
| `.gclient` hooks (23) | vendored verbatim with paths rebased under `vanadium/`; includes the ~20 adblock filter-list downloads that the config APK embeds |
| `tools/common/apply_subprojects_patches.py`, `tools/filter_lists/filter_list_download.py` | vendored; skips `[tmp]`/`[upstream]` patches that no longer apply, exactly as upstream does |
| `args.gn` | vendored, with minSdk 29 + ThinLTO/CFI/siso overrides |
| `generate-release` | signing only; confirms the artifact is `VanadiumWebView.apk` |
| `checkout_pgo_profiles` | `True` upstream, `False` here — PGO is unused with `is_official_build = false` and saves ~1.5 GB |

Order matters and now matches upstream: `gclient sync --nohooks` → `git am` the main
series → `gclient runhooks` (subproject patches + filter lists, which need
`src/vanadium/android_config/` to exist first) → `gn gen` → ninja.

## Why this can work

* Chromium 158 itself supports API 29 — the other branch proves it: 32 Vanadium patches
  compiled and produced a working `minSdk 29` WebView.
* Vanadium's patches are mostly feature-flag defaults and feature removals, not API-30+
  platform code. Chromium guards platform APIs with `SDK_INT` checks.
* 138 of the patches create their own `vanadium/chromium_src/` overlay files, so no
  separate GrapheneOS checkout is needed — the patch series is self-contained.

## What to expect to break

1. **GrapheneOS-only features** — e.g. their coarse-location API added around 157. Those
   patches compile but the feature is inert on stock Android. If one fails to compile,
   skip it with `SKIP_PATCHES="0016 0022 0024 ..."`; nothing of value is lost on a
   non-GrapheneOS device.
2. **Runtime on API 29/30** — features that call newer platform APIs may misbehave even
   though the app installs. Test on the device before trusting it.
3. **`vanadium_webview_apk` target** — if their dedicated target needs the config APK
   plumbing, the script falls back to Chromium's stock `system_webview_apk`, which carries
   the same patches.

## Build

```
export PATH=$PWD/depot_tools:$PATH
./build-vanadium.sh                                  # arm64, Vanadium 158.0.8127.92
SKIP_PATCHES="" ./build-vanadium.sh                  # apply everything, incl. config APK
TARGET=system_webview_apk ./build-vanadium.sh        # stock WebView target
```

The script clones Chromium at the tag Vanadium targets, applies `vanadium/patches/*.patch`
in numeric order with `git am`, writes `vanadium/args.gn` plus the minSdk-29 overrides into
`out/Default/args.gn`, then builds.

## Bumping to a newer Vanadium

```
git -C vanadium-src fetch --depth 1 origin <new-tag>
rm -rf vanadium/patches && cp -a vanadium-src/patches vanadium/
sed -i 's/min_sdk_version = 34/min_sdk_version = 29/' vanadium/patches/002[245]-*.patch
VANADIUM_VERSION=<new-tag> ./build-vanadium.sh
```

That is the entire maintenance burden — no hand-porting.

## Fallback

`master` / `experimental-webview-158` still hold the ungoogled-chromium recipe that produced
a working `SystemWebView_arm64.apk` (package `org.ungoogled.chromium.webview`, minSdk 29).
If this branch cannot be made to build, nothing is lost.
