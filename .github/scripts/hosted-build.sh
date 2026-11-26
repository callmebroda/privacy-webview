#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${UGC_WORK}"
cp -a "${GITHUB_WORKSPACE}/." "${UGC_WORK}/"

export CCACHE_DIR=/mnt/ccache
cd "${UGC_WORK}"

# Clear npm's inherited proxy settings so the hook phase uses the registry pinned in
# ~/.npmrc (see hosted-prepare.sh). Generic HTTP(S)_PROXY is intentionally left alone:
# git and apt rely on it, and only npm's own config points at the dead internal host.
unset npm_config_proxy npm_config_https_proxy NPM_CONFIG_PROXY NPM_CONFIG_HTTPS_PROXY 2>/dev/null || true
export NPM_CONFIG_REGISTRY="${NPM_CONFIG_REGISTRY:-https://registry.npmjs.org/}"
export npm_config_registry="${npm_config_registry:-https://registry.npmjs.org/}"

: > build-step.log
setsid ./build.sh "$@" < /dev/null >> build-step.log 2>&1 &
_pid=$!
tail --pid="$_pid" -n +1 -f build-step.log &
_tail=$!
_rc=0
wait "$_pid" || _rc=$?
sudo pkill -9 -s "$_pid" 2>/dev/null || true
wait "$_tail" 2>/dev/null || true
exit "$_rc"
