# Experimental WebView-only build — read this first

This repository is a **personal, unsupported experiment**. It is a fork of
[ungoogled-software/ungoogled-chromium-android](https://github.com/ungoogled-software/ungoogled-chromium-android)
and is **not** an official ungoogled-chromium release, is not endorsed by that project,
and should not be reported to it as a bug.

It exists for one purpose: producing a **de-Googled, Vanadium-patched Android System
WebView** at a Chromium version newer than the one upstream currently ships, for private
use on an Android 11 (API 30) device.

## What is different from upstream

| Area | Upstream | This fork |
| --- | --- | --- |
| Chromium | 156.0.8078.79 | **158.0.8127.88** |
| Build target | `chrome_modern_target` (browser + WebView) | **`webview_target`** (`system_webview_apk`) only |
| Release assets | `ChromePublic_*.apk/.aab`, `SystemWebView_*.apk` | **`SystemWebView_*.apk` only** |
| Signing | `build/release.sh` | **`build/release-webview.sh`** (WebView-only) |
| Patch series | validated at 156 | **NOT validated at 158 — expect conflicts** |

The privacy patch set itself is unchanged and is why this fork is interesting: the
`patches/series` file applies the ungoogled-chromium core patches, **32 Vanadium patches**
(seed-based field trials off, variations fetching off, WebView variations support off,
metrics off by default, strict site isolation, Play-services fonts off, autofill server
communication off, background sync off, sensors access off, `fstack-protector-strong`,
stack-clash protection on arm64) plus Bromite/Cromite hardening patches (DoH secure mode
by default, DRM origin-ID preprovisioning off, updater pings off, account permissions
removed) and the Unobtainium patches (Location fallback, Vision, Translate killed).

## What you must expect to go wrong

1. **Patch conflicts.** The series was last rebased at 156. Two milestones of Chromium
   drift usually means hunks fail in the Safe Browsing, de-Google and `src-fix` areas.
   The build stops in the `prep` job at the patch-apply step. Fix the hunk, add it to
   `patches/series` (or amend the existing patch), push, re-run.
2. **`src-fix` files are milestone-numbered.** Several are named `*-150`, `*-152`; add
   `-158` variants for the hunks that no longer apply, following the same pattern.
3. **Build time.** A WebView-only build is much shorter than browser + WebView, but still
   runs across several 350-minute chained jobs. One bad stage wastes the whole chain.
4. **No keystore.** Unless you add `KEYSTORE_B64` and `KEYSTORE_PASS` repository secrets,
   the output APK is debug-signed. Debug-signed APKs must not be distributed.
5. **The release job will refuse unsigned output.** `build-hosted.yml` requires a
   `.idsig` sidecar before publishing. Leave `release_name` blank to skip publishing and
   just download the `release-<arch>` artifact.

## How to run it

Actions → **release build** → *Run workflow*:

* `architecture`: `arm64` (or `arm` for 32-bit devices)
* `chromium_source`: `github`
* `release_name`: **leave blank** (skips the publish job)
* `source_run_id`: leave blank on the first run; if a run dies mid-chain, pass the run id
  to resume from the saved build tree
* `threads`: `0`

The finished APK appears as the `release-<arch>` artifact of the final part job.

## How to actually use the APK

The package name is `org.ungoogled.chromium.webview`, which Android does not accept as a
WebView provider by default. You need root plus an overlay that adds the package and its
certificate digest to `config_webview_packages.xml` (the AnyWebView / open_webview
approach), then select it under *Developer options → WebView implementation*.

Keep a recovery path: if the provider crashes, WebView-backed apps crash with it.
`adb shell pm uninstall-system-updates com.android.webview` or disabling the overlay
module restores the previous provider.

## Support

None. No issue triage, no warranty, no guarantees that the APK installs, renders, or is
secure. If you did not create this fork, you almost certainly want upstream's official
156 build instead.

## License

Inherited from upstream — see [LICENSE.md](LICENSE.md). Upstream credits and patch
authorship (ungoogled-chromium, Vanadium/GrapheneOS, Bromite, Cromite, Unobtainium,
DivestOS) are unchanged.

## Why the patch series is curated (and what was dropped)

`patches/series` holds the patches this build actually applies. `patches/series.browser`
holds 19 browser-only patches that are **not** applied: Play Services / Firebase dependency
removals, `chrome://flags` additions and the extensions UI. They patch `chrome/android`,
`components/media_router`, `components/module_installer`, `chrome/browser/ui/android/...`
and the extensions stack — none of which is linked into `system_webview_apk`.

Two reasons they are out:

1. At Chromium 158 Google merged `third_party/android_deps/autorolled/BUILD.gn` into
   `third_party/android_deps/BUILD.gn`, so every hunk that referenced the old path fails.
   Rebasing them is real work for code this build never compiles.
2. Skipping a *removal* patch cannot break a build — the code it would delete simply stays
   as upstream ships it. The privacy patches that matter for the WebView (ungoogled core,
   Vanadium, Bromite/Cromite, Unobtainium) are all still applied.

The trade-off is honest: with those patches dropped, Play Services references that live in
shared code (`content/`, `services/`) are left in place. WebView does not link Play Services,
so this does not change what the APK can do, but it is less de-Googled than upstream's full
browser build. Restore them (and rebase to the current tag) if you ever build the browser.

## Reference: how holtdroid builds the same Chromium version

Worth knowing, because it explains two choices here:

* holtdroid runs `gclient sync --nohooks` and then **`gclient runhooks`**, which downloads
  Chromium's prebuilt `node_modules` from Google Storage. This fork instead runs
  `third_party/node/update_npm_deps` (an npm install) because ungoogled's flow needs the
  npm tree before it applies its patches — which is why the poisoned `package-lock.json`
  URLs had to be rewritten in `build.sh`.
* holtdroid builds with `is_official_build = false`, `symbol_level = 0`, no LTO. This fork
  keeps ungoogled's `android_flags.release.gn` (`is_official_build = true`), which enables
  ThinLTO and is the main risk for the 16 GB GitHub runners during the link stage.
