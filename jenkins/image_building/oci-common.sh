#!/usr/bin/env bash

set -eux

# Handle generic sensitive credentials associated with
# the specific user/service account running the script.
# These credentials identify who performs operations and nothing more.

set +x

OCI_KEY_FILE="${OCI_KEY_FILE:?}"
chmod 600 "${OCI_KEY_FILE}"

export OCI_CLI_KEY_FILE="${OCI_KEY_FILE}"
export OCI_CLI_USER="${OCI_CLI_USER:?}"
export OCI_CLI_TENANCY="${OCI_CLI_TENANCY:?}"
export OCI_CLI_FINGERPRINT="${OCI_CLI_FINGERPRINT:?}"

set -x

install_oci_client() {
  rm -rf venv
  python3 -m venv venv

  # shellcheck source=/dev/null
  . venv/bin/activate
  # Install OCI CLI
  pip install oci-cli==3.76.0
}

# Upload image to object storage
upload_object_to_bucket() {
  local namespace_ocid="${1:?}"
  local bucket_name="${2:?}"
  local object_name="${3:?}"
  oci os object put \
      --namespace-name "${namespace_ocid}" \
      --bucket-name "${bucket_name}" \
      --name "${object_name}" \
      --file "${object_name}"
}

# Computes the sha256 checksum of an object and writes it to a file.
generate_sha256_for_object() {
    local object_name="${1:?}"
    local sha_name="${2:-${object_name}.sha256}"
    sha256sum "${object_name}" > "${sha_name}"
}
