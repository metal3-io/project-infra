#!/bin/sh
# This script is expected to be executed with minimal POSIX shell e.g ash
set -eu

RT_TOKEN_FILE="${RT_TOKEN_FILE:-/etc/artifactory/token}"
# Used to clean a cached artifact
CACHE_URL="${CACHE_URL:-https://artifactory.nordix.org/artifactory/openstack-remote-cache/ironic-python-agent/dib/ipa-centos9-master.tar.gz}"
# User facing proxy endpoint that is backed by the content of the cache, users should pull from here
PROXY_URL="${PROXY_URL:-https://artifactory.nordix.org/artifactory/openstack-remote/ironic-python-agent/dib/ipa-centos9-master.tar.gz}"

if [ ! -r "${RT_TOKEN_FILE}" ]; then
  echo "ERROR: Token file '${RT_TOKEN_FILE}' does not exist or is not readable" >&2
  exit 1
fi

IFS= read -r RT_TOKEN <"${RT_TOKEN_FILE}"
if [ -z "${RT_TOKEN}" ]; then
  echo "ERROR: Artifactory token is empty" >&2
  exit 1
fi

# Hardening to avoid leaking token (as much as possible)
HEADER_FILE=$(mktemp)
trap 'rm -f "${HEADER_FILE}"' EXIT
printf 'Authorization: Bearer %s\n' "${RT_TOKEN}" > "${HEADER_FILE}"
chmod 600 "${HEADER_FILE}"

# Clean the cached artifact
DELETE_CALL=$(curl -s -H @"${HEADER_FILE}" -XDELETE "${CACHE_URL}" -o /dev/null -w "%{http_code}")
if [ "${DELETE_CALL}" -ne 204 ] && [ "${DELETE_CALL}" -ne 200 ]; then
  echo "ERROR: Artifact delete failed with status ${DELETE_CALL}, URL:${CACHE_URL}" >&2
  exit 1
fi

# Preloading cache, so that jobs can access the new artifact faster
PRELOAD_CALL=$(curl -sS --retry 10 --retry-delay 5 "${PROXY_URL}" -o /dev/null -w "%{http_code}")
if [ "${PRELOAD_CALL}" -ne 200 ]; then
  echo "ERROR: Preload failed with status ${PRELOAD_CALL}, URL:${PROXY_URL}" >&2
  exit 1
fi
