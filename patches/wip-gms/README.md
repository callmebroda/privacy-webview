# Work in progress: Play-Services removal for Chromium 158 (NOT in patches/series)

These are the 12 `Remove-dependency-on-*` / `gms-dangling` patches from
`patches/series.browser`, ported toward 158, plus 14 Vanadium privacy patches
(GrapheneOS, tag 158.0.8127.92.0) that cover tracking surfaces new in 157/158.

Status at this commit:

* Ported and verified against real 158 sources: `androidx/BUILD.gn` (-571),
  `android_deps/BUILD.gn` (-1436, retargeted from the deleted
  `autorolled/BUILD.gn`), `chrome/android/java/AndroidManifest.xml` (-66),
  `components/fcm/android/BUILD.gn`, 6 media_router Java files.
* Stubs rewritten for 158 (from the 156 reference, adapted): `TextDetectionImpl`
  (44 lines, adds 158's `ensureReady`), `LocationProviderGmsCore` (47 lines).
* Still hand work: `SmsVerificationReceiver`, `CafMessageHandler`,
  `GeolocationHeader`, `OmniboxFeatures`; a few BUILD.gn dep lines Google
  renamed; and Vanadium `0122` (Glic) which drifts on
  `chrome/common/chrome_features.cc`.
* `0074` (Media Integrity on WebView) depends on GrapheneOS's
  `vanadium/chromium_src/` overlay and cannot be applied to a stock tree.

They are deliberately NOT in `patches/series`: a half-ported removal patch
breaks the build. Move them in only once the set applies end to end.
