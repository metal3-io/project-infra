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
        docker.io/nvuillam/npm-groovy-lint:v19.0.1@sha256:d614f73d8f6d9cb1289f2872cee59b1ca0519b40bcfb0a5f4c8d1ca2dbb08573 \
        "${WORKDIR}"/hack/groovylint.sh "$@"
fi
