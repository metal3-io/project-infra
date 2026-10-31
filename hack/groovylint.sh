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
        docker.io/nvuillam/npm-groovy-lint:v19.0.0@sha256:8a815bcf7f193d1ccf53091e56ee6bf9911ab0917ea4d361470096585fae0d99 \
        "${WORKDIR}"/hack/groovylint.sh "$@"
fi
