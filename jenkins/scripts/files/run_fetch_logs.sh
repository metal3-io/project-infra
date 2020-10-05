#!/bin/bash

#Do not fail on error (for example k8s cluster not available)
set -u

LOGS_TARBALL=${1:-container_logs.tgz}
LOGS_DIR="${2:-logs}"
DISTRIBUTION="${3:-ubuntu}"
TESTS_FOR="${4:-}"

if [ "${DISTRIBUTION}" == "ubuntu" ]; then
  #Must match with run_integration_tests.sh
  CONTAINER_RUNTIME="docker"
else
  CONTAINER_RUNTIME="podman"
fi
mkdir -p ${LOGS_DIR}

# Fetch cluster manifests
mkdir -p "${LOGS_DIR}/manifests"
cp -r /tmp/manifests/* "${LOGS_DIR}/manifests"

function fetch_k8s_logs() {
dir_name=k8s_${1}
kconfig=$2 

NAMESPACES="$(kubectl --kubeconfig=${kconfig} get namespace -o json | jq -r '.items[].metadata.name')"
mkdir -p "${LOGS_DIR}/${dir_name}"
for NAMESPACE in $NAMESPACES
do
  mkdir -p "${LOGS_DIR}/${dir_name}/${NAMESPACE}"
  PODS="$(kubectl --kubeconfig=${kconfig} get pods -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')"
  for POD in $PODS
  do
    mkdir -p "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}"
    CONTAINERS="$(kubectl --kubeconfig=${kconfig} get pods -n "$NAMESPACE" "$POD" -o json | jq -r '.spec.containers[].name')"
    for CONTAINER in $CONTAINERS
    do
      mkdir -p "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}/${CONTAINER}"
      kubectl --kubeconfig=${kconfig} logs -n "$NAMESPACE" "$POD" "$CONTAINER" \
      > "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}/${CONTAINER}/stdout.log"\
      2> "${LOGS_DIR}/${dir_name}/${NAMESPACE}/${POD}/${CONTAINER}/stderr.log"
    done
  done
done
}

# Fetch k8s logs
fetch_k8s_logs "management_cluster" "/home/airshipci/.kube/config"

mkdir -p "${LOGS_DIR}/${CONTAINER_RUNTIME}"
LOCAL_CONTAINERS="$(sudo "${CONTAINER_RUNTIME}" ps --format "{{.Names}}")"
for LOCAL_CONTAINER in $LOCAL_CONTAINERS
do
  mkdir -p "${LOGS_DIR}/${CONTAINER_RUNTIME}/${LOCAL_CONTAINER}"
  sudo "${CONTAINER_RUNTIME}" logs "$LOCAL_CONTAINER" > "${LOGS_DIR}/${CONTAINER_RUNTIME}/${LOCAL_CONTAINER}/stdout.log" \
  2> "${LOGS_DIR}/${CONTAINER_RUNTIME}/${LOCAL_CONTAINER}/stderr.log"
done

mkdir -p "${LOGS_DIR}/qemu"
sudo sh -c "cp -r /var/log/libvirt/qemu/* ${LOGS_DIR}/qemu/"
sudo chown -R ${USER}:${USER} "${LOGS_DIR}/qemu"

if [[ "${TESTS_FOR}" == "feature_tests_upgrade"* ]]
then
  mkdir -p "${LOGS_DIR}/upgrade"
  sudo sh -c "cp /tmp/*upgrade.result.txt ${LOGS_DIR}/upgrade/"
  sudo chown -R ${USER}:${USER} "${LOGS_DIR}/upgrade"
fi

if [[ "${TESTS_FOR}" == "feature_tests" || "${TESTS_FOR}" == "feature_tests_centos" ]]
then
  target_config=$(sudo find /tmp/ -type f -name "kubeconfig*")
  if [ "${target_config}" != "" ]
  then
    #fetch target cluster k8s logs
    fetch_k8s_logs "target_cluster" $target_config
  fi
fi

tar -cvzf "$LOGS_TARBALL" ${LOGS_DIR}/*
