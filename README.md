# Vanadium WebView — Android 10+ backport (personal, unsupported)

> [!CAUTION]
> **Personal experiment. Not an official build. No support.**
>
> - This is **not** an official GrapheneOS or Vanadium build, and it is not affiliated
>   with, endorsed by, or supported by the GrapheneOS project.
> - It rebuilds GrapheneOS's **Vanadium 158.0.8127.92** patch set on stock Chromium with
>   `min_sdk_version` lowered from 34 to **29**, so it installs on Android 10+. GrapheneOS
>   does not support that configuration — expect rough edges, and do not report them
>   upstream.
> - **ThinLTO, CFI and siso are disabled** so the build fits a 4-core / 16 GB CI runner.
>   That is a deliberate loss of security hardening versus real Vanadium.
> - **No support, no warranty, no issue triage.** Issues are disabled on purpose. If you
>   want a maintained, supported build, use GrapheneOS or upstream Vanadium.
> - The build scripts here were written with AI assistance and validated only by CI runs.
>   They have not been audited by a human. Treat the output accordingly.

## What this is

A personal, reproducible way to stay current with Vanadium's WebView hardening on a device
that is **not** running GrapheneOS. Instead of maintaining a hand-ported patch set, it takes
Vanadium's own sources and rebuilds them at a lower minimum SDK:

| Piece | Source |
|---|---|
| Chromium | `chromium.googlesource.com/chromium/src.git` @ `158.0.8127.92` |
| Main patches | GrapheneOS/Vanadium `patches/` (304) |
| Subproject patches | `subprojects_patches/` — v8 (4) + search engines (3), applied by Vanadium's own gclient hook |
| Build args | Vanadium's `args.gn` + minSdk 29 + ThinLTO/CFI/siso off |
| Target | `vanadium_webview_apk` → `VanadiumWebView64.apk` |

Bumping to a new Vanadium release is: copy `patches/`, re-apply one `sed`, rebuild. No
patch porting.

## Build

```
./build-vanadium.sh            # or ./build.sh --arch arm64 --target webview_target
```

See [VANADIUM-BACKPORT.md](VANADIUM-BACKPORT.md) for the full recipe, the expected
breakages, the bump procedure, and what is deliberately not built (the config APK / RRO).

## Installing

The APK is **unsigned for release** — sign it with your own key before installing. It is a
standalone WebView (`app.vanadium.webview`, no Trichrome). You need root plus a WebView
provider overlay to select it, and you must uninstall any previous install signed with a
different key first.

## If this does not work

The other branch of this repo, `master` / `experimental-webview-158`, holds a different
recipe: official Chromium + ungoogled-chromium's patch set + Vanadium hardening + Bromite/
Cromite patches, hand-ported. It is more aggressive about removing Google integrations and
it already produced a working `minSdk 29` WebView — at the cost of manual maintenance.
