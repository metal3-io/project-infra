#!/bin/bash

set -eu

LOGS_TARBALL=${1:-container_logs.tgz}
mkdir -p logs

NAMESPACES="$(kubectl get namespace -o json | jq -r '.items[].metadata.name')"
mkdir -p logs/k8s
for NAMESPACE in $NAMESPACES
do
  mkdir -p "logs/k8s/${NAMESPACE}"
  PODS="$(kubectl get pods -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')"
  for POD in $PODS
  do
    mkdir -p "logs/k8s/${NAMESPACE}/${POD}"
    CONTAINERS="$(kubectl get pods -n "$NAMESPACE" "$POD" -o json | jq -r '.spec.containers[].name')"
    for CONTAINER in $CONTAINERS
    do
      mkdir -p "logs/k8s/${NAMESPACE}/${POD}/${CONTAINER}"
      kubectl logs -n "$NAMESPACE" "$POD" "$CONTAINER" \
      > "logs/k8s/${NAMESPACE}/${POD}/${CONTAINER}/stdout.log"\
      2> "logs/k8s/${NAMESPACE}/${POD}/${CONTAINER}/stderr.log"
    done
  done
done

mkdir -p logs/docker
DOCKER_CONTAINERS="$(docker ps --format "{{json .}}" | jq -r '.Names')"
for DOCKER_CONTAINER in $DOCKER_CONTAINERS
do
  mkdir -p "logs/docker/${DOCKER_CONTAINER}"
  docker logs "$DOCKER_CONTAINER" > "logs/docker/${DOCKER_CONTAINER}/stdout.log" \
  2> "logs/docker/${DOCKER_CONTAINER}/stderr.log"
done

tar -cvzf "$LOGS_TARBALL" logs/*
