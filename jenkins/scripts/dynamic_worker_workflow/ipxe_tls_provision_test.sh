#!/usr/bin/env bash
# ignore shellcheck v0.9.0 introduced SC2317 about unreachable code
# that doesn't understand traps, variables, functions etc causing all
# code called via iterate() to false trigger SC2317
# shellcheck disable=SC2317

set -eux

CI_DIR="$(dirname "$(readlink -f "${0}")")"

# --- CI inputs (repo under test) --------------------------------------------
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
# At least 2 nodes are required (NUMBER_OF_BMH = CP + workers).
export NUM_NODES="${NUM_NODES:-2}"

# --- iPXE TLS switches (see IPXE_TLS_TESTS.md section 7) ---------------------
export BUILD_IPXE="true"
export IPXE_ENABLE_TLS="true"
export IRONIC_TLS_SETUP="${IRONIC_TLS_SETUP:-true}"
export IPXE_TLS_PORT="${IPXE_TLS_PORT:-8084}"
# OpenSSL protocol flag to enforce (e.g. tls1_3 -> -tls1_3).
export TLS_VERSION="${TLS_VERSION:-tls1_3}"
# Build iPXE from the Nordix fork carrying the TLS 1.3 work instead of upstream.
# This is the firmware actually under test; metal3-dev-env's build_ipxe_firmware()
# clones ${IPXE_REPO} at ${IPXE_RELEASE_BRANCH}.
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

# --- Resolve the paths / values the checks need -----------------------------
# Prefer values exported by the dev-env; fall back to verified defaults.
WORKING_DIR="${WORKING_DIR:-/opt/metal3-dev-env}"
IPXE_CACERT_FILE="${IPXE_CACERT_FILE:-${WORKING_DIR}/certs/ipxe-ca.pem}"
# The ipxe-builder writes the custom TLS firmware here (IRONIC_DATA_DIR=/shared).
IRONIC_DATA_DIR="${IRONIC_DATA_DIR:-${WORKING_DIR}/ironic}"
IPXE_CUSTOM_FIRMWARE_DIR="${IPXE_CUSTOM_FIRMWARE_DIR:-${IRONIC_DATA_DIR}/custom_ipxe_firmware}"

if [[ -z "${IRONIC_HOST_IP:-}" ]]; then
    IRONIC_HOST_IP="${CLUSTER_URL_HOST:-172.22.0.2}"
fi

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

echo "Using IRONIC_HOST_IP=${IRONIC_HOST_IP}"
echo "Using IPXE_CACERT_FILE=${IPXE_CACERT_FILE}"
echo "Using IPXE_CUSTOM_FIRMWARE_DIR=${IPXE_CUSTOM_FIRMWARE_DIR}"
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

iterate() {
    local RUNS=0
    local COMMAND="$*"
    local TMP_RET TMP_RET_CODE
    TMP_RET="$(${COMMAND})"
    TMP_RET_CODE="$?"

    until [[ "${TMP_RET_CODE}" = 0 ]]; do
        if [[ "${RUNS}" = "0" ]]; then
            echo "   - Waiting for task completion (up to 1200 seconds)" \
                " - Command: '${COMMAND}'"
        fi
        RUNS="$((RUNS+1))"
        if [[ "${RUNS}" = 40 ]]; then
            break
        fi
        sleep 30
        # shellcheck disable=SC2068
        TMP_RET="$(${COMMAND})"
        TMP_RET_CODE="$?"
    done
    echo "${TMP_RET}"
    return "${TMP_RET_CODE}"
}

# ----------------------------------------------------------------------------
# Pre-flight checks
# ----------------------------------------------------------------------------
echo ""
echo "=== iPXE TLS: end-to-end provisioning verification ==="
echo ""

# Pre-flight A: the builder actually produced custom TLS firmware.
RESULT_STR="Pre-flight A: custom TLS iPXE firmware exists in ${IPXE_CUSTOM_FIRMWARE_DIR}"
if compgen -G "${IPXE_CUSTOM_FIRMWARE_DIR}/*.efi" >/dev/null &&
    [[ -r "${IPXE_CUSTOM_FIRMWARE_DIR}/undionly.kpxe" ]]; then
    process_status 0
else
    process_status 1
fi

# Pre-flight B: the HTTPS endpoint is valid (fast fail before the long wait).
RESULT_STR="Pre-flight B: HTTPS endpoint validates against the iPXE CA"
TLS_OUT="$(echo "Q" | openssl s_client \
    -connect "${IRONIC_HOST_IP}:${IPXE_TLS_PORT}" \
    "-${TLS_VERSION}" -CAfile "${IPXE_CACERT_FILE}" \
    -verify_ip "${IRONIC_HOST_IP}" 2>&1 || true)"
if grep -q "Verify return code: 0 (ok)" <<<"${TLS_OUT}"; then
    process_status 0
else
    process_status 1
fi

if [[ "${FAILS}" -ne 0 ]]; then
    echo ""
    echo -e "Pre-flight checks failed; skipping provisioning. Failures : ${FAILS}"
    exit "${FAILS}"
fi

pushd "${HOME}/metal3"
echo "Provisioning target cluster using the custom TLS iPXE firmware"
RESULT_STR="Provisioning completes with custom TLS iPXE (make provision)"
if make provision; then
    process_status 0
else
    process_status 1
fi
popd

# ----------------------------------------------------------------------------
# Confirmation re-check: assert every BMH is 'provisioned' and 'OK'. Redundant
# with make provision's internal wait, but gives an explicit CI pass/fail line.
# ----------------------------------------------------------------------------
check_bmh_provisioned() {
    kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json |
        jq -e '[.items[] | select(.status.provisioning.state != "provisioned")] | length == 0' \
            >/dev/null
}

check_bmh_operational_ok() {
    kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json |
        jq -e '[.items[] | select(.status.operationalStatus != "OK")] | length == 0' \
            >/dev/null
}

RESULT_STR="All BareMetalHosts reached provisioning.state == provisioned"
if iterate check_bmh_provisioned >/dev/null; then
    process_status 0
else
    process_status 1
fi

RESULT_STR="All BareMetalHosts have operationalStatus == OK"
if iterate check_bmh_operational_ok >/dev/null; then
    process_status 0
else
    process_status 1
fi

echo ""
echo -e "Number of failures : ${FAILS}"
exit "${FAILS}"
