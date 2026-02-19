#!/usr/bin/env bash
# ignore shellcheck v0.9.0 introduced SC2317 about unreachable code
# that doesn't understand traps, variables, functions etc causing all
# code called via iterate() to false trigger SC2317
# shellcheck disable=SC2317

set -u

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck disable=SC1091
. "${SCRIPTDIR}"/lib/vars.sh

process_status(){
  if [[ "${1}" = 0 ]]; then
    echo "OK - ${RESULT_STR}"
    return 0
  else
    echo "FAIL - ${RESULT_STR}"
    FAILS="$((FAILS+1))"
    return 1
  fi
}

iterate(){
  local RUNS=0
  local COMMAND="$*"
  local TMP_RET TMP_RET_CODE
  TMP_RET="$(${COMMAND})"
  TMP_RET_CODE="$?"

  until [[ "${TMP_RET_CODE}" = 0 ]]
  do
    if [[ "${RUNS}" = "0" ]]; then
      echo "   - Waiting for task completion (up to" \
        "$((1200)) seconds)" \
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
  FAILS="$((FAILS+TMP_RET_CODE))"
  echo "${TMP_RET}"
  return "${TMP_RET_CODE}"
}

# shellcheck disable=SC2329
check_bmh_status() {
    local FAILS_CHECK="${FAILS}"
    local STATUS PROVISIONING_STATE

    # Get all baremetalhosts as single JSON object with .items[] array
    # Then extract status fields for each host
    while IFS=' ' read -r STATUS PROVISIONING_STATE; do
        # Verify BM host status
        RESULT_STR="Baremetalhost status OK"
        equals "${STATUS}" "OK"

        # Verify the introspection completed successfully
        # State should be either "ready" or "available"
        RESULT_STR="Baremetalhost introspecting completed"
        if [[ "${PROVISIONING_STATE}" == "ready" ]] || [[ "${PROVISIONING_STATE}" == "available" ]]; then
            process_status 0
        else
            echo "       expected 'ready' or 'available', got '${PROVISIONING_STATE}'"
            process_status 1
        fi
    done < <(kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts \
        -n metal3 -o json | \
        jq -r '.items[] | "\(.status.operationalStatus) \(.status.provisioning.state)"')

    return "$((FAILS-FAILS_CHECK))"
}

# Verify that a resource exists in a type
# shellcheck disable=SC2329
check_k8s_entity() {
  local FAILS_CHECK="${FAILS}"
  local TYPE="${1}"
  shift
  for name in "${@}"; do
    # Check entity exists
    RESULT_STR="${TYPE} ${name} created"
    NS="$(echo "${name}" | cut -d ':' -f1)"
    NAME="$(echo "${name}" | cut -d ':' -f2)"
    process_status $?
  done

  return "$((FAILS-FAILS_CHECK))"
}

#
# Compare if the two inputs are the same and log
#
# Inputs:
# - first input to compare
# - second input to compare
# shellcheck disable=SC2329
equals(){
  [[ "${1}" = "${2}" ]]; RET_CODE="$?"
  if ! process_status "${RET_CODE}" ; then
    echo "       expected ${2}, got ${1}"
  fi
  return "${RET_CODE}"
}


# Verify that a resource exists in a type
# shellcheck disable=SC2329
check_k8s_rs() {
  local FAILS_CHECK="${FAILS}"
  for name in "${@}"; do
    # Check entity exists
    LABEL="$(echo "$name" | cut -f1 -d:)"
    NAME="$(echo "$name" | cut -f2 -d:)"
    NS="$(echo "${name}" | cut -d ':' -f3)"
    NB="$(echo "${name}" | cut -d ':' -f4)"
    ENTITIES="$(kubectl --kubeconfig "${KUBECONFIG}" get replicasets \
      -l "${LABEL}"="${NAME}" -n "${NS}" -o json)"
    NB_ENTITIES="$(echo "$ENTITIES" | jq -r '.items | length')"
    RESULT_STR="Replica sets with label ${LABEL}=${NAME} created"
    equals "${NB_ENTITIES}" "${NB}"
  done

  return "$((FAILS-FAILS_CHECK))"
}

# Verify a container is running
# shellcheck disable=SC2329
check_container(){
  local NAME="$1"
  RESULT_STR="Container ${NAME} running"
  sudo "${CONTAINER_RUNTIME}" ps | grep -w "$NAME$" > /dev/null
  process_status $?
  return $?
}

# Verify all pods are in Running state across all namespaces
# shellcheck disable=SC2329
check_all_pods_running() {
  local FAILS_CHECK="${FAILS}"
  local POD_NAME NAMESPACE STATUS
  local NOT_RUNNING_COUNT=0

  echo "Checking all pods status..."

  # Get all pods that are NOT in Running state
  while IFS=' ' read -r NAMESPACE POD_NAME STATUS; do
    if [[ -n "${POD_NAME}" ]]; then
      NOT_RUNNING_COUNT=$((NOT_RUNNING_COUNT+1))
      echo "  WARN: Pod ${NAMESPACE}/${POD_NAME} is in ${STATUS} state"
    fi
  done < <(kubectl --kubeconfig "${KUBECONFIG}" get pods --all-namespaces -o json | \
    jq -r '.items[] | select(.status.phase!="Running" and .status.phase!="Succeeded") | "\(.metadata.namespace) \(.metadata.name) \(.status.phase)"')

  RESULT_STR="All pods in Running or Succeeded state"
  if [[ "${NOT_RUNNING_COUNT}" -eq 0 ]]; then
    process_status 0
  else
    echo "       ${NOT_RUNNING_COUNT} pod(s) not in Running/Succeeded state"
    process_status 1
  fi

  return "$((FAILS-FAILS_CHECK))"
}

KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
EXPTD_V1ALPHAX_V1BETAX_CRDS="clusters.cluster.x-k8s.io \
  kubeadmconfigs.bootstrap.cluster.x-k8s.io \
  kubeadmconfigtemplates.bootstrap.cluster.x-k8s.io \
  machinedeployments.cluster.x-k8s.io \
  machines.cluster.x-k8s.io \
  machinesets.cluster.x-k8s.io \
  baremetalhosts.metal3.io"

# Add check for ironic deployment for Centos test
# Different tests were failing in CI because of ironic deployment was not in ready state.
EXPTD_DEPLOYMENTS="capm3-system:capm3-controller-manager \
    capi-system:capi-controller-manager \
    capi-kubeadm-bootstrap-system:capi-kubeadm-bootstrap-controller-manager \
    capi-kubeadm-control-plane-system:capi-kubeadm-control-plane-controller-manager \
    baremetal-operator-system:baremetal-operator-controller-manager \
    baremetal-operator-system:ironic-service"

EXPTD_RS="cluster.x-k8s.io/provider:infrastructure-metal3:capm3-system:1 \
  cluster.x-k8s.io/provider:cluster-api:capi-system:1 \
  cluster.x-k8s.io/provider:bootstrap-kubeadm:capi-kubeadm-bootstrap-system:1 \
  cluster.x-k8s.io/provider:control-plane-kubeadm:capi-kubeadm-control-plane-system:1 \
  cluster.x-k8s.io/provider:ipam-metal3:metal3-ipam-system:1"

BRIDGES="provisioning external"
EXPTD_CONTAINERS="httpd-infra registry"

FAILS=0


# Verify networking
for bridge in ${BRIDGES}; do
  RESULT_STR="Network ${bridge} exists"
  ip link show dev "${bridge}" > /dev/null
  process_status $? "Network ${bridge} exists"
done

# Verify Kubernetes cluster is reachable
RESULT_STR="Kubernetes cluster reachable"
kubectl version > /dev/null
process_status $?
echo ""

# Verify that the CRDs exist
RESULT_STR="Fetch CRDs"
CRDS="$(kubectl --kubeconfig "${KUBECONFIG}" get crds)"
process_status $? "Fetch CRDs"

LIST_OF_CRDS=("${EXPTD_V1ALPHAX_V1BETAX_CRDS}")

# shellcheck disable=SC2068
for name in ${LIST_OF_CRDS[@]}; do
  RESULT_STR="CRD ${name} created"
  echo "${CRDS}" | grep -w "${name}"  > /dev/null
  process_status $?
done
echo ""

# Verify v1beta1 Operators, Deployments, Replicasets
iterate check_k8s_entity deployments "${EXPTD_DEPLOYMENTS}"
iterate check_k8s_rs "${EXPTD_RS}"

# Verify all pods are running
echo ""
iterate check_all_pods_running
echo ""
# Verify the baremetal hosts
# Fetch Baremetalhosts CRs"

kubectl --kubeconfig "${KUBECONFIG}" get baremetalhosts -n metal3 -o json \
  > /dev/null
process_status $?


for container in ${EXPTD_CONTAINERS}; do
  iterate check_container "$container"
done

echo -e "\nNumber of failures : $FAILS"
exit "${FAILS}"
