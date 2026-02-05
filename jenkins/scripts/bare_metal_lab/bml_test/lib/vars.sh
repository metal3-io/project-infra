#!/usr/bin/env bash

export BARE_METAL_PROVISIONER_IP="172.22.0.1"
export BARE_METAL_PROVISIONER_CIDR=24
export EXTERNAL_SUBNET_V4_HOST="192.168.111.1"
export EXTERNAL_SUBNET_V4_PREFIX=24
export CONTAINER_RUNTIME=docker
export REGISTRY="${EXTERNAL_SUBNET_V4_HOST}:5000"
export USER
export IRONIC_DATA_DIR="/opt/metal3-dev-env/ironic"
export IRONIC_AUTH_DIR="${IRONIC_DATA_DIR}/auth/"
export IRONIC_BASIC_AUTH="true"
export IRONIC_HOST="172.22.0.2"
export IRONIC_HOST_IP="172.22.0.2"
export CAPIRELEASE="v1.12.1"
export CAPM3RELEASE="v1.13.99"
export IPAMRELEASE="v1.13.99"
export IRONIC_NAMESPACE="baremetal-operator-system"
export NAMEPREFIX="baremetal-operator"
export IPA_BASEURI=https://artifactory.nordix.org/artifactory/openstack-remote-cache/ironic-python-agent/dib

export CONTAINER_REGISTRY="registry.nordix.org/quay-io-proxy"
export CAPM3_IMAGE="${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3:main}"
export IPAM_IMAGE="${CONTAINER_REGISTRY}/metal3-io/ip-address-manager:main}"
export BARE_METAL_OPERATOR_IMAGE=${BARE_METAL_OPERATOR_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/baremetal-operator:main"}

export BMOPATH="/home/metal3ci/go/src/github.com/metal3-io/baremetal-operator"
export CAPM3PATH="/home/metal3ci/go/src/github.com/metal3-io/cluster-api-provider-metal3"
export IPAMPATH="/home/metal3ci/go/src/github.com/metal3-io/ip-address-manager"
export CAPI_CONFIG_DIR="/home/metal3ci/.config/cluster-api"

export IRONIC_NAMESPACE="baremetal-operator-system"
export IRSO_IRONIC_VERSION="33.0"

export WORKING_DIR="/opt/metal3-dev-env/"
export IRONIC_BASE_URL="http://172.22.0.2"

export WORKING_DIR="/opt/metal3-dev-env/"
export IRONIC_CACERT_FILE="${WORKING_DIR}certs/ironic-ca.pem"
export IRONIC_CAKEY_FILE="${WORKING_DIR}certs/ironic-ca.key"
export IRONIC_CERT_FILE="${WORKING_DIR}certs/ironic.crt"
export IRONIC_KEY_FILE="${WORKING_DIR}certs/ironic.key"

export IRSO_TAG="main"
export IRSOPATH="/home/${USER}/go/src/github.com/metal3-io/ironic-standalone-operator"
export IRONIC_ROLLOUT_WAIT=5
