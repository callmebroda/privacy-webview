# Vanadium privacy patches, Chromium 158 (GrapheneOS, tag 158.0.8127.92.0)

11 patches, each verified to apply cleanly against Chromium 158.0.8127.88 sources
(`git apply -C1`). They cover tracking surfaces that are new or changed in 157/158:

* 0076 disable-contextual-search-by-default
* 0090 disable-offering-translations-by-default
* 0096 disable-component-updater-pings-by-default
* 0103 Disable-newer-privacy-sandbox-features-by-default
* 0108 most-private-WebRTC-IP-handling-policy-by-default
* 0112 disable-trials-of-privacy-aware-analytics-advertising
* 0114 disable-appending-variations-header
* 0116 disable-fetching-optimization-guides-by-default
* 0118 disable-fetching-optimization-hints-by-default
* 0119 disable-more-optimization-guides-features-by-default
* 0120 disable-network-time-tracker-by-default

Deliberately excluded:

* 0122 (Glic) — obsolete at 158: upstream already dropped `IS_ANDROID` from
  `BASE_FEATURE(kGlic, ...)` in `chrome/common/chrome_features.cc`, so Glic is
  disabled on Android by default.
* 0104 (WebGPU on Android) — obsolete at 158: `WEBGPU_ENABLED` in
  `gpu/config/gpu_finch_features.cc` already excludes Android.
* 0074 (Media Integrity on WebView) — patches GrapheneOS's `vanadium/chromium_src/`
  overlay, which does not exist in a stock Chromium checkout.

Not wired into `patches/series` yet.
