#!/usr/bin/env bash

# Checking for linting erross in groovy files using npm-groovy-lint

set -eux

IS_CONTAINER="${IS_CONTAINER:-false}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"
WORKDIR="${WORKDIR:-/workdir}"

if [ "${IS_CONTAINER}" != "false" ]; then
    npm-groovy-lint --failon warning --verbose
else
    "${CONTAINER_RUNTIME}" run --rm \
        --env IS_CONTAINER=TRUE \
        --volume "${PWD}:${WORKDIR}:ro,z" \
        --entrypoint sh \
        --workdir "${WORKDIR}" \
        docker.io/nvuillam/npm-groovy-lint:v17.0.5@sha256:d2671e7b8aea51096445c9bc1c528e995b041b23b855c27313d6494118e3caee \
        "${WORKDIR}"/hack/groovylint.sh "$@"
fi
