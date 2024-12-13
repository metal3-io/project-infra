#!/usr/bin/env bash

# Based on https://github.com/prometheus-operator/kube-prometheus/blob/17aa6690a5739183c68efa048439739dce773827/build.sh
# This script uses arg $1 (name of *.jsonnet file to use) to generate the manifests/*.yaml files.

set -e
set -x
# only exit with zero if all commands of the pipeline exit successfully
set -o pipefail

# Make sure to use project tooling
PATH="$(pwd)/tmp/bin:${PATH}"

# Install needed tools
go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@v0.6.0
go install github.com/google/go-jsonnet/cmd/jsonnet@v0.20.0
go install github.com/brancz/gojsontoyaml@v0.1.0


# Make sure to start with a clean 'manifests' dir
rm -rf manifests
mkdir -p manifests/setup

# Calling gojsontoyaml is optional, but we would like to generate yaml, not json
jsonnet -J vendor -m manifests "${1-example.jsonnet}" | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}

# Make sure to remove json files
find manifests -type f ! -name '*.yaml' -delete
rm -f kustomization
