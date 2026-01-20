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
        docker.io/nvuillam/npm-groovy-lint:v16.1.1@sha256:fd8cf44d1ea3103f8f589770257f6f5960e76124c05a7fe81051bbff4dd3df38 \
        "${WORKDIR}"/hack/groovylint.sh "$@"
fi
