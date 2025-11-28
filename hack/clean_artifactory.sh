#!/bin/sh
# This script is expected to be executed with minimal POSIX shell e.g ash
set -eu

RT_TOKEN_FILE="${RT_TOKEN_FILE:-/etc/artifactory/token}"
CACHE_URL="${CACHE_URL:-https://artifactory.nordix.org/artifactory/openstack-remote-cache/ironic-python-agent/dib/ipa-centos9-master.tar.gz}"

if [ ! -r "${RT_TOKEN_FILE}" ]; then
  echo "ERROR: Token file '${RT_TOKEN_FILE}' does not exist or is not readable" >&2
  exit 1
fi

IFS= read -r RT_TOKEN <"${RT_TOKEN_FILE}"
if [ -z "${RT_TOKEN}" ]; then
  echo "ERROR: Artifactory token is empty" >&2
  exit 1
fi

HTTP_CODE=$(curl -s -H "Authorization: Bearer ${RT_TOKEN}" -XDELETE "${CACHE_URL}" -o /dev/null -w "%{http_code}")
if [ "${HTTP_CODE}" -ne 204 ] && [ "${HTTP_CODE}" -ne 200 ]; then
  echo "ERROR: DELET failed with status ${HTTP_CODE}, URL:${CACHE_URL}" >&2
  exit 1
fi
