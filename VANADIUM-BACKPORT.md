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

## Why this can work

* Chromium 158 itself supports API 29 — the other branch proves it: 32 Vanadium patches
  compiled and produced a working `minSdk 29` WebView.
* Vanadium's patches are mostly feature-flag defaults and feature removals, not
  API-30+ platform code. Chromium guards platform APIs with `SDK_INT` checks.
* 138 of the patches create their own `vanadium/chromium_src/` overlay files, so no
  separate GrapheneOS checkout is needed — the patch series is self-contained.

## What to expect to break

1. **Patches 0022 / 0024 / 0025** add the GrapheneOS-specific targets (`vanadium_config_apk`,
   `vanadium_browser_apk`, `vanadium_webview_apk`). If those targets reference GrapheneOS
   OS-side bits, skip them with `SKIP_PATCHES="0022 0024"` and build Chromium's standard
   `system_webview_apk` instead — the script falls back to it automatically.
2. **GrapheneOS-only features** — e.g. their coarse-location API added around 157. Those
   patches compile but the feature is inert on stock Android. If one fails to compile,
   skip it; nothing of value is lost on a non-GrapheneOS device.
3. **Runtime on API 29/30** — features that call newer platform APIs may misbehave even
   though the app installs. Test on the device before trusting it.

## Build

```
export PATH=$PWD/depot_tools:$PATH
./build-vanadium.sh                       # arm64, Vanadium 158.0.8127.92
SKIP_PATCHES="0022 0024" ./build-vanadium.sh
VANADIUM_VERSION=158.0.8127.92 TARGET=system_webview_apk ./build-vanadium.sh
```

The script clones Chromium at the tag Vanadium targets, applies `vanadium/patches/*.patch`
in numeric order with `git am`, writes `vanadium/args.gn` plus the minSdk-29 overrides into
`out/Default/args.gn`, then builds.

## Bumping to a newer Vanadium

```
git -C vanadium-src fetch --depth 1 origin <new-tag>   # or re-clone
rm -rf vanadium/patches && cp -a vanadium-src/patches vanadium/
# re-apply the minSdk change to 0022/0024/0025 if the files still exist
sed -i 's/min_sdk_version = 34/min_sdk_version = 29/' vanadium/patches/002[245]-*.patch
VANADIUM_VERSION=<new-tag> ./build-vanadium.sh
```

That is the entire maintenance burden — no hand-porting.

## Fallback

`master` / `experimental-webview-158` still hold the ungoogled-chromium recipe that produced
a working `SystemWebView_arm64.apk` (package `org.ungoogled.chromium.webview`, minSdk 29).
If this branch cannot be made to build, nothing is lost.
