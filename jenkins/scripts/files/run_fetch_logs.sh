#!/bin/bash

#Do not fail on error (for example k8s cluster not available)
set -u

LOGS_TARBALL=${1:-container_logs.tgz}
LOGS_DIR="${2:-logs}"
DISTRIBUTION="${3:-ubuntu}"
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

NAMESPACES="$(kubectl get namespace -o json | jq -r '.items[].metadata.name')"
mkdir -p "${LOGS_DIR}/k8s"
for NAMESPACE in $NAMESPACES
do
  mkdir -p "${LOGS_DIR}/k8s/${NAMESPACE}"
  PODS="$(kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')"
  for POD in $PODS
  do
    mkdir -p "${LOGS_DIR}/k8s/${NAMESPACE}/${POD}"
    CONTAINERS="$(kubectl get pods -n "$NAMESPACE" "$POD" -o json | jq -r '.spec.containers[].name')"
    for CONTAINER in $CONTAINERS
    do
      mkdir -p "${LOGS_DIR}/k8s/${NAMESPACE}/${POD}/${CONTAINER}"
      kubectl logs -n "$NAMESPACE" "$POD" "$CONTAINER" \
      > "${LOGS_DIR}/k8s/${NAMESPACE}/${POD}/${CONTAINER}/stdout.log"\
      2> "${LOGS_DIR}/k8s/${NAMESPACE}/${POD}/${CONTAINER}/stderr.log"
    done
  done
done

mkdir -p "${LOGS_DIR}/${CONTAINER_RUNTIME}"
LOCAL_CONTAINERS="$(sudo "${CONTAINER_RUNTIME}" ps --format "{{.Names}}")"
for LOCAL_CONTAINER in $LOCAL_CONTAINERS
do
  mkdir -p "${LOGS_DIR}/${CONTAINER_RUNTIME}/${LOCAL_CONTAINER}"
  sudo "${CONTAINER_RUNTIME}" logs "$LOCAL_CONTAINER" > "${LOGS_DIR}/${CONTAINER_RUNTIME}/${LOCAL_CONTAINER}/stdout.log" \
  2> "${LOGS_DIR}/${CONTAINER_RUNTIME}/${LOCAL_CONTAINER}/stderr.log"
done

mkdir -p "${LOGS_DIR}/qemu"
sudo sh -c "cp -r /var/log/libvirt/qemu/* "${LOGS_DIR}/qemu/""
sudo chown -R ${USER}:${USER} "${LOGS_DIR}/qemu"

tar -cvzf "$LOGS_TARBALL" ${LOGS_DIR}/*
