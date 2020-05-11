#!/bin/bash

#Do not fail on error (for example k8s cluster not available)
set -u

LOGS_TARBALL=${1:-container_logs.tgz}
LOGS_DIR="${2:-logs}"
mkdir -p ${LOGS_DIR}

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

mkdir -p "${LOGS_DIR}/docker"
DOCKER_CONTAINERS="$(docker ps --format "{{json .}}" | jq -r '.Names')"
for DOCKER_CONTAINER in $DOCKER_CONTAINERS
do
  mkdir -p "${LOGS_DIR}/docker/${DOCKER_CONTAINER}"
  docker logs "$DOCKER_CONTAINER" > "${LOGS_DIR}/docker/${DOCKER_CONTAINER}/stdout.log" \
  2> "${LOGS_DIR}/docker/${DOCKER_CONTAINER}/stderr.log"
done

tar -cvzf "$LOGS_TARBALL" ${LOGS_DIR}/*
