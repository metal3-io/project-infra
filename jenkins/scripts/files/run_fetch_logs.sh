#!/bin/bash

#Do not fail on error (for example k8s cluster not available)
set -u

LOGS_TARBALL="${1:-container_logs.tgz}"
LOGS_DIR="${2:-logs}"
IMAGE_OS="${3:-ubuntu}"
TESTS_FOR="${4:-}"

if [ "${IMAGE_OS}" == "ubuntu" ]; then
  #Must match with run_integration_tests.sh
  CONTAINER_RUNTIME="docker"
else
  CONTAINER_RUNTIME="podman"
fi
mkdir -p "${LOGS_DIR}"

# Fetch cluster manifests
mkdir -p "${LOGS_DIR}/manifests"
cp -r /tmp/manifests/* "${LOGS_DIR}/manifests"

if [[ "${TESTS_FOR}" == "e2e_tests"* ]]; then
  mkdir -p "${LOGS_DIR}/e2e_artifacts"
  cp -r /home/metal3ci/tested_repo/_artifacts/. "${LOGS_DIR}/e2e_artifacts"
fi

function fetch_k8s_logs() {
dir_name="k8s_${1}"
kconfig="$2"

NAMESPACES="$(kubectl --kubeconfig="${kconfig}" get namespace -o json | jq -r '.items[].metadata.name')"
mkdir -p "${LOGS_DIR}/${dir_name}"
for NAMESPACE in $NAMESPACES
do
  mkdir -p "${LOGS_DIR}/${dir_name}/${NAMESPACE}"
  PODS="$(kubectl --kubeconfig="${kconfig}" get pods -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')"
  for POD in $PODS
  do
    mkdir -p "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}"
    CONTAINERS="$(kubectl --kubeconfig="${kconfig}" get pods -n "$NAMESPACE" "$POD" -o json | jq -r '.spec.containers[].name')"
    for CONTAINER in $CONTAINERS
    do
      mkdir -p "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}/${CONTAINER}"
      kubectl --kubeconfig="${kconfig}" logs -n "$NAMESPACE" "$POD" "$CONTAINER" \
      > "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}/${CONTAINER}/stdout.log"\
      2> "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}/${CONTAINER}/stderr.log"
    done
  done
done
}

# Fetch k8s logs
fetch_k8s_logs "management_cluster" "/home/metal3ci/.kube/config"

# Fetch Ironic containers logs before pivoting to the target cluster
CONTAINER_LOGS_DIR="${LOGS_DIR}/${CONTAINER_RUNTIME}/before_pivoting"
mkdir -p "${CONTAINER_LOGS_DIR}"
cp -r /tmp/"${CONTAINER_RUNTIME}"/* "${CONTAINER_LOGS_DIR}"

# Fetch Ironic containers logs after pivoting back to the source cluster
CONTAINER_LOGS_DIR="${LOGS_DIR}/${CONTAINER_RUNTIME}/after_pivoting"
mkdir -p "${CONTAINER_LOGS_DIR}"
LOCAL_CONTAINERS="$(sudo "${CONTAINER_RUNTIME}" ps -a --format "{{.Names}}")"
for LOCAL_CONTAINER in $LOCAL_CONTAINERS
do
  mkdir -p "${CONTAINER_LOGS_DIR}/${LOCAL_CONTAINER}"
  # shellcheck disable=SC2024
  sudo "${CONTAINER_RUNTIME}" logs "$LOCAL_CONTAINER" > "${CONTAINER_LOGS_DIR}/${LOCAL_CONTAINER}/stdout.log" \
  2> "${CONTAINER_LOGS_DIR}/${LOCAL_CONTAINER}/stderr.log"
done

mkdir -p "${LOGS_DIR}/qemu"
sudo sh -c "cp -r /var/log/libvirt/qemu/* ${LOGS_DIR}/qemu/"
sudo chown -R "${USER}:${USER}" "${LOGS_DIR}/qemu"

# Fetch atop and sysstat metrics
mkdir -p "${LOGS_DIR}/metrics/atop"
mkdir -p "${LOGS_DIR}/metrics/sysstat"
sudo sh -c "cp -r /var/log/atop/* ${LOGS_DIR}/metrics/atop/"
sudo sh -c "cp -r /var/log/sysstat/* ${LOGS_DIR}/metrics/sysstat/"
sudo chown -R "${USER}:${USER}" "${LOGS_DIR}/metrics"

mkdir -p "${LOGS_DIR}/cluster-api-config"
cp -r "/home/metal3ci/.cluster-api/." "${LOGS_DIR}/cluster-api-config/"

if [[ "${TESTS_FOR}" == "feature_tests_upgrade"* ]]
then
  mkdir -p "${LOGS_DIR}/upgrade"
  sudo sh -c "cp /tmp/\.*upgrade.result.txt ${LOGS_DIR}/upgrade/"
  sudo chown -R "${USER}:${USER}" "${LOGS_DIR}/upgrade"
fi

target_config=$(sudo find /tmp/ -type f -name "kubeconfig*")
if [ -n "${target_config}" ]
then
  #fetch target cluster k8s logs
  fetch_k8s_logs "target_cluster" "$target_config"
fi

tar -cvzf "$LOGS_TARBALL" "${LOGS_DIR}"/*
