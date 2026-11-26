#!/usr/bin/env bash
set -euo pipefail

echo "::group::disk before"
df -h / /mnt
echo "::endgroup::"

sudo rm -rf /usr/local/lib/android \
            /usr/local/.ghcup \
            /usr/lib/jvm \
            /usr/lib/google-cloud-sdk \
            /usr/lib/dotnet \
            /usr/share/swift \
            /opt/hostedtoolcache 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
sudo apt-get -qq update
sudo apt-get -qq install -y ccache zstd

sudo fallocate -l 8G /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap -f /mnt/swapfile >/dev/null
sudo swapon /mnt/swapfile

sudo mkdir -p "${UGC_WORK}" /mnt/ccache
sudo chown -R "$(id -u):$(id -g)" /mnt

# --- npm: neutralise the proxy/registry config inherited from the runner image ------
# The image ships npm pointed at an internal proxy
# (airlock-proxy.uplink.goog:999) which resolves to 127.0.0.1, where nothing listens, so
# every npm fetch in Chromium's hook phase dies with:
#   npm error FetchError: request to http://airlock-proxy.uplink.goog:999/... ECONNREFUSED
# Fix: pin the public registry, strip the poisoned keys from the image's global npmrc,
# and clear the npm-specific proxy env vars. Generic HTTP(S)_PROXY is left alone (git and
# apt work through it) so only npm's own settings change.
NPMRC="${HOME}/.npmrc"
cat > "${NPMRC}" <<'NPMRC_EOF'
registry=https://registry.npmjs.org/
fetch-retries=5
fetch-retry-mintimeout=20000
fetch-retry-maxtimeout=120000
fetch-timeout=300000
audit=false
fund=false
NPMRC_EOF
chmod 600 "${NPMRC}"

if command -v npm >/dev/null 2>&1; then
  GLOBAL_NPMRC="$(npm config get globalconfig 2>/dev/null || true)"
  if [ -n "${GLOBAL_NPMRC}" ] && [ -f "${GLOBAL_NPMRC}" ]; then
    echo "global npmrc: ${GLOBAL_NPMRC}"
    grep -E '^(registry|proxy|https-proxy)=' "${GLOBAL_NPMRC}" | sed 's/^/  before: /' || true
    sudo sed -i -E '/^(registry|proxy|https-proxy)=/d' "${GLOBAL_NPMRC}" 2>/dev/null \
      || sed -i -E '/^(registry|proxy|https-proxy)=/d' "${GLOBAL_NPMRC}" 2>/dev/null || true
  fi
fi

unset npm_config_proxy npm_config_https_proxy NPM_CONFIG_PROXY NPM_CONFIG_HTTPS_PROXY 2>/dev/null || true
export NPM_CONFIG_REGISTRY=https://registry.npmjs.org/
export npm_config_registry=https://registry.npmjs.org/

# persist for the build step (hosted-build.sh clears the proxy vars again there)
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "NPM_CONFIG_USERCONFIG=${NPMRC}"
    echo "NPM_CONFIG_REGISTRY=https://registry.npmjs.org/"
    echo "npm_config_registry=https://registry.npmjs.org/"
  } >> "${GITHUB_ENV}"
fi

echo "::group::npm check"
if command -v npm >/dev/null 2>&1; then
  echo "effective registry: $(npm config get registry 2>/dev/null || echo unknown)"
  echo "effective proxy:    $(npm config get proxy 2>/dev/null || echo none)"
fi
# fetch the exact artifact npm choked on, so a broken registry path fails here in
# seconds instead of ~40 minutes into the source fetch
npm_ok=no
for attempt in 1 2 3; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 --retry 2 \
         https://registry.npmjs.org/write-file-atomic/-/write-file-atomic-7.0.1.tgz || true)
  echo "registry probe ${attempt}: HTTP ${code}"
  [ "${code}" = "200" ] && { npm_ok=yes; break; }
  sleep 5
done
[ "${npm_ok}" = "yes" ] || {
  echo "FATAL: registry.npmjs.org does not serve the tarball npm needs (HTTP ${code})."
  echo "       Chromium's hook phase cannot succeed without it."
  exit 1
}
echo "::endgroup::"

echo "::group::disk after"
df -h / /mnt
echo "::endgroup::"
