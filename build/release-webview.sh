#!/usr/bin/env bash
# EXPERIMENTAL (this fork only): sign and assemble the WebView release asset from a
# finished per-arch build. The upstream script (build/release.sh) assumes the browser
# target was built and aborts when ChromePublic.apk is missing; this fork builds only
# system_webview_apk, so this variant assembles SystemWebView_<arch>.apk alone.
#
#   build/release-webview.sh <arch> [out-dir]     e.g. build/release-webview.sh arm64
#   env: UGC_KEYSTORE, UGC_KEYSTORE_ALIAS (default key0), UGC_KEYSTORE_PASSFILE
set -eu
cd "$(dirname "$0")/.."
ARCH="${1:?usage: build/release-webview.sh <arch> [out-dir]}"
OUT="src/${2:-out/Default}"

. ./.build_config
VERSION=$(grep -o 'android_override_version_name="[^"]*"' "$OUT/args.gn" 2>/dev/null | cut -d'"' -f2 || true)
[ -n "$VERSION" ] || VERSION="$chromium_version"
REL="releases/${VERSION}-${ungoogled_chromium_android_revision}"
mkdir -p "$REL"

WV_IN=$(find "$OUT/apks" -maxdepth 1 -name "SystemWebView64.apk" | head -1)
[ -n "$WV_IN" ] || WV_IN=$(find "$OUT/apks" -maxdepth 1 -name "SystemWebView.apk" | head -1)
[ -n "$WV_IN" ] || { echo "FATAL: no SystemWebView.apk under $OUT/apks (webview target not built?)"; exit 1; }

KS="${UGC_KEYSTORE:-}"
KS_ALIAS="${UGC_KEYSTORE_ALIAS:-key0}"
KS_PASSFILE="${UGC_KEYSTORE_PASSFILE:-}"
APKSIGNER="${APKSIGNER:-$(ls src/third_party/android_sdk/public/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)}"
[ -n "${APKSIGNER:-}" ] && [ -x "$APKSIGNER" ] || APKSIGNER=$(ls "$HOME"/android-sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
_TREE_JDK="src/third_party/jdk/current/bin"
if [ -x "$_TREE_JDK/java" ]; then
    JAVA_HOME="$(cd "$_TREE_JDK/.." && pwd)"
    export JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
fi
KEYTOOL="${KEYTOOL:-$([ -x "$_TREE_JDK/keytool" ] && echo "$_TREE_JDK/keytool" || command -v keytool)}"

if [ -n "$KS" ] && [ -f "$KS" ] && [ -n "$KS_PASSFILE" ] && [ -f "$KS_PASSFILE" ]; then
    [ -n "${APKSIGNER:-}" ] && [ -x "$APKSIGNER" ] || { echo "FATAL: apksigner not found"; exit 1; }
    PW=$(cat "$KS_PASSFILE")
    "$APKSIGNER" sign --ks "$KS" --ks-key-alias "$KS_ALIAS" \
        --ks-pass "pass:$PW" --key-pass "pass:$PW" \
        --in "$WV_IN" --out "$REL/SystemWebView_${ARCH}.apk"
    WFP=$("$APKSIGNER" verify --print-certs "$REL/SystemWebView_${ARCH}.apk" 2>/dev/null \
          | grep -m1 "certificate SHA-256 digest" | awk '{print $NF}' \
          | sed 's/../&:/g; s/:$//' | tr 'a-f' 'A-F' || true)
    KFP=$("$KEYTOOL" -list -keystore "$KS" -alias "$KS_ALIAS" -storepass "$PW" -v 2>/dev/null \
          | grep -m1 "SHA256:" | awk '{print $2}' || true)
    [ "$WFP" = "$KFP" ] || { echo "FATAL: signed WebView cert != keystore (apk=$WFP key=$KFP)"; exit 1; }
    echo "signed SystemWebView as $KS_ALIAS ($KFP)"
else
    echo "WARN: no keystore supplied, copying build output as-is (NOT release-signed)."
    cp "$WV_IN" "$REL/SystemWebView_${ARCH}.apk"
fi

( cd "$REL"
  if [ -f sha256sums.txt ]; then grep -v "  SystemWebView_${ARCH}[._]" sha256sums.txt > sha256sums.new || : ; fi
  sha256sum "SystemWebView_${ARCH}.apk" >> sha256sums.new
  sort -k2 sha256sums.new -o sha256sums.txt
  rm -f sha256sums.new )

echo "=== assembled $REL ($ARCH) ==="
ls -lh "$REL" | sed 's/^/  /'

DN=$("$APKSIGNER" verify --print-certs "$REL/SystemWebView_${ARCH}.apk" 2>/dev/null \
     | grep -m1 "certificate DN" | cut -d: -f2- | sed 's/^ *//' || true)
SHA=$("$APKSIGNER" verify --print-certs "$REL/SystemWebView_${ARCH}.apk" 2>/dev/null \
      | grep -m1 "certificate SHA-256 digest" | awk '{print $NF}' || true)
case "$DN" in
    *"Android Debug"*|"") echo "=== SIGNING: DEBUG-SIGNED — DO NOT PUBLISH ===" ;;
    *)                    echo "=== SIGNING: release key ===" ;;
esac
echo "  signer DN:  ${DN:-<none — apk is unsigned>}"
echo "  cert SHA256: ${SHA:-n/a}"
