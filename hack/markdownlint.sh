#!/bin/sh
# markdownlint-cli2 has config file(s) named .markdownlint-cli2.yaml in the repo

set -eux

IS_CONTAINER="${IS_CONTAINER:-false}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"

# all md files, but ignore .github
if [ "${IS_CONTAINER}" != "false" ]; then
    markdownlint-cli2 "**/*.md" "#.github"
else
    "${CONTAINER_RUNTIME}" run --rm \
        --env IS_CONTAINER=TRUE \
        --volume "${PWD}:/workdir:ro,z" \
        --entrypoint sh \
        --workdir /workdir \
        docker.io/pipelinecomponents/markdownlint-cli2:0.14.41@sha256:60785c4a4ec97442f8986f1ce3cbea347f0097a05fc5f48c128714a120078716 \
        /workdir/hack/markdownlint.sh "$@"
fi
