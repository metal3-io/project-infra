#!/usr/bin/env bash
# shellcheck disable=SC2317

set -eux

CI_DIR="$(dirname "$(readlink -f "${0}")")"

export IMAGE_OS="${IMAGE_OS:-ubuntu}"
export REPO_ORG="${REPO_ORG:-metal3-io}"
export REPO_NAME="${REPO_NAME:-ironic-image}"
export REPO_BRANCH="${REPO_BRANCH:-main}"
export UPDATED_REPO="${UPDATED_REPO:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
export UPDATED_BRANCH="${UPDATED_BRANCH:-main}"
export PR_ID="${PR_ID:-}"
export METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
export METAL3BRANCH="${METAL3BRANCH:-main}"
export CAPM3RELEASEBRANCH="${CAPM3RELEASEBRANCH:-main}"
export BMORELEASEBRANCH="${BMORELEASEBRANCH:-main}"
export NUM_NODES="${NUM_NODES:-1}"

# iPXE TLS switches
export BUILD_IPXE="true"
export IPXE_ENABLE_TLS="true"
export IRONIC_TLS_SETUP="${IRONIC_TLS_SETUP:-true}"
export IPXE_TLS_PORT="${IPXE_TLS_PORT:-8084}"
# OpenSSL protocol flag to enforce (e.g. tls1_3 -> -tls1_3).
export TLS_VERSION="${TLS_VERSION:-tls1_3}"
# Build iPXE from the Nordix fork carrying the TLS 1.3 work instead of upstream.
export IPXE_REPO="${IPXE_REPO:-https://github.com/Nordix/ipxe.git}"
export IPXE_RELEASE_BRANCH="${IPXE_RELEASE_BRANCH:-tuomo/tls-1.3}"

# shellcheck disable=SC1091
source "${CI_DIR}/test_env.sh"

export FORCE_REPO_UPDATE=false

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    export CONTAINER_RUNTIME="docker"
    export BOOTSTRAP_CLUSTER="kind"
else
    export BOOTSTRAP_CLUSTER="minikube"
fi

# TODO:dev_env_integration_tests and e2e_tests have similar blocks.
# This should be extracted into a shared function
REPO_LOCATION="${REPO_LOCATION:-${HOME}/tested_repo}"
rm -rf "${REPO_LOCATION}"
git clone "https://github.com/${REPO_ORG}/${REPO_NAME}.git" "${REPO_LOCATION}"
cd "${REPO_LOCATION}"
git checkout "${REPO_BRANCH}"
if [[ "${UPDATED_REPO}" != *"${REPO_ORG}/${REPO_NAME}"* ]] ||
    [[ "${UPDATED_BRANCH}" != "${REPO_BRANCH}" ]]; then
    git config user.email "test@test.test"
    git config user.name "Test"
    git remote add test "${UPDATED_REPO}"
    git fetch test
    if [[ -n "${PR_ID:-}" ]]; then
        git fetch origin "pull/${PR_ID}/head:${UPDATED_BRANCH}-branch" || true
    fi
    git merge "${UPDATED_BRANCH}" || exit
fi
cd "${HOME}"

git clone "${METAL3REPO}" "${HOME}/metal3"
pushd "${HOME}/metal3"
git checkout "${METAL3BRANCH}"

echo "Deploying metal3-dev-env with iPXE TLS enabled"
make

# --- Resolve the CA and the Ironic host IP the tests need -------------------
# Prefer values exported by the dev-env; fall back to sensible defaults.
WORKING_DIR="${WORKING_DIR:-/opt/metal3-dev-env}"
IPXE_CACERT_FILE="${IPXE_CACERT_FILE:-${WORKING_DIR}/certs/ipxe-ca.pem}"

if [[ -z "${IRONIC_HOST_IP:-}" ]]; then
    # Fall back to the dev-env default provisioning host IP.
    IRONIC_HOST_IP="${CLUSTER_URL_HOST:-172.22.0.2}"
fi

echo "Using IRONIC_HOST_IP=${IRONIC_HOST_IP}"
echo "Using IPXE_CACERT_FILE=${IPXE_CACERT_FILE}"
echo "Using IPXE_TLS_PORT=${IPXE_TLS_PORT}"

popd

FAILS=0
RESULT_STR=""

process_status() {
    if [[ "${1}" = 0 ]]; then
        echo "OK - ${RESULT_STR}"
        return 0
    else
        echo "FAIL - ${RESULT_STR}"
        FAILS="$((FAILS+1))"
        return 1
    fi
}

# Open a TLS connection with the given openssl flags and capture the output.
tls_connect() {
    echo "Q" | openssl s_client -connect "${IRONIC_HOST_IP}:${IPXE_TLS_PORT}" \
        "$@" 2>&1 || true
}

TLS_FLAG="-${TLS_VERSION}"
ENDPOINT="https://${IRONIC_HOST_IP}:${IPXE_TLS_PORT}"

echo ""
echo "=== iPXE TLS suite A: server-side endpoint verification ==="
echo ""

RESULT_STR="Test 1: ${TLS_VERSION} handshake trusts iPXE CA and validates IP SAN"
TLS1_OUT="$(tls_connect "${TLS_FLAG}" -CAfile "${IPXE_CACERT_FILE}" \
    -verify_ip "${IRONIC_HOST_IP}")"
if grep -q "Protocol *: *TLSv1.3" <<<"${TLS1_OUT}" &&
    grep -q "Verify return code: 0 (ok)" <<<"${TLS1_OUT}"; then
    process_status 0
else
    process_status 1
fi

RESULT_STR="Test 2: negotiated cipher is a TLS 1.3 AEAD suite"
if grep -E "Cipher *: *(TLS_AES_|TLS_CHACHA20_)" <<<"${TLS1_OUT}" >/dev/null; then
    process_status 0
else
    process_status 1
fi

RESULT_STR="Test 3: verification fails without the iPXE CA (negative)"
TLS_NOCA_OUT="$(tls_connect "${TLS_FLAG}" -CAfile /dev/null)"
if grep -q "Verify return code: 0 (ok)" <<<"${TLS_NOCA_OUT}"; then
    # Trusted without our CA -> the trust check is not enforced -> fail.
    process_status 1
else
    process_status 0
fi

RESULT_STR="Test 4: served certificate SAN contains IP:${IRONIC_HOST_IP}"
SAN_OUT="$(tls_connect "${TLS_FLAG}" -CAfile "${IPXE_CACERT_FILE}" -showcerts \
    | openssl x509 -noout -text 2>/dev/null || true)"
if grep -q "IP Address:${IRONIC_HOST_IP}" <<<"${SAN_OUT}"; then
    process_status 0
else
    process_status 1
fi

RESULT_STR="Test 5: boot.ipxe served over TLS starts with #!ipxe"
# curl's flag is --tlsv1.3 (tls1_3 -> tlsv1.3).
CURL_TLS_FLAG="--tlsv${TLS_VERSION#tls}"
CURL_TLS_FLAG="${CURL_TLS_FLAG//_/.}"
BOOT_IPXE="$(curl -sf "${CURL_TLS_FLAG}" --cacert "${IPXE_CACERT_FILE}" \
    "${ENDPOINT}/boot.ipxe" 2>/dev/null || true)"
if [[ "$(head -n1 <<<"${BOOT_IPXE}")" == "#!ipxe" ]]; then
    process_status 0
else
    process_status 1
fi

RESULT_STR="Test 6: legacy TLS 1.1 is refused (negative)"
TLS11_OUT="$(tls_connect -tls1_1 -CAfile "${IPXE_CACERT_FILE}")"
if grep -q "Protocol *: *TLSv1.1" <<<"${TLS11_OUT}"; then
    # It negotiated TLS 1.1 -> legacy protocols are not disabled -> fail.
    process_status 1
else
    process_status 0
fi

echo ""
echo -e "Number of failures : ${FAILS}"
exit "${FAILS}"
