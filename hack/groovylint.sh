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
        docker.io/nvuillam/npm-groovy-lint:v16.2.0@sha256:ee6d40a132d00e1349dc5e457084440e6646b3d47100353799074254e7b7f086 \
        "${WORKDIR}"/hack/groovylint.sh "$@"
fi
