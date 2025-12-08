#!/usr/bin/env bash
set -euo pipefail

PROFILE="${PROFILE:-minikube}"
RETRIES="${RETRIES:-8}"
MAX_BACKOFF="${MAX_BACKOFF:-120}"

IMAGES=(
    "registry.nordix.org/quay-io-proxy/metal3-io/baremetal-operator:main"
    "registry.nordix.org/quay-io-proxy/metal3-io/ironic:release-33.0"
    "registry.nordix.org/quay-io-proxy/metal3-io/keepalived:release-0.9"
    "registry.k8s.io/cluster-api/kubeadm-bootstrap-controller:v1.12.1"
    "registry.k8s.io/cluster-api/kubeadm-control-plane-controller:v1.12.1"
    "registry.k8s.io/cluster-api/cluster-api-controller:v1.12.1"
    "registry.nordix.org/quay-io-proxy/metal3-io/cluster-api-provider-metal3:main"
    "quay.io/jetstack/cert-manager-controller:v1.19.1"
    "quay.io/jetstack/cert-manager-cainjector:v1.19.1"
    "quay.io/jetstack/cert-manager-webhook:v1.19.1"
    "registry.nordix.org/quay-io-proxy/metal3-io/ironic-standalone-operator:main"
    "registry.nordix.org/quay-io-proxy/metal3-io/ip-address-manager:main"
    "ghcr.io/fybrik/crdoc@sha256:355ef777a45021ee864e613b2234b4f2c6193762e3e0de94a26b66d06cec81c3"
    "registry.nordix.org/quay-io-proxy/metal3-io/ironic-ipa-downloader"
)

log(){ printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

pull_with_retry() {
  local img="$1"
  local attempt=1

  if docker image inspect "${img}" >/dev/null 2>&1; then
    log "Already pulled on host, skip: ${img}"
    return 0
  fi

  while (( attempt <= RETRIES )); do
    log "Host pull (${attempt}/${RETRIES}): ${img}"
    if docker pull "${img}"; then
      return 0
    fi
    local sleep_s=$(( 2 ** (attempt - 1) ))
    (( sleep_s > MAX_BACKOFF )) && sleep_s=$MAX_BACKOFF
    log "Pull failed, retrying in ${sleep_s}s: ${img}"
    sleep "$sleep_s"
    attempt=$((attempt + 1))
  done

  log "ERROR: Failed to pull after ${RETRIES} attempts: ${img}"
  return 1
}

save_and_load() {
  local img="$1"
  local tar

  tar="/tmp/$(echo "${img}" | tr '/:.' '___').tar"

  log "docker save -> ${tar}"
  rm -f "${tar}"
  docker save -o "${tar}" "${img}"

  log "minikube image load tar -> ${img}"
  minikube -p "${PROFILE}" image load "${tar}"

  rm -f "${tar}"
}

for img in "${IMAGES[@]}"; do
  pull_with_retry "${img}"
  save_and_load "${img}"
done

log "Done. Images in minikube:"
minikube -p "${PROFILE}" image ls || true
