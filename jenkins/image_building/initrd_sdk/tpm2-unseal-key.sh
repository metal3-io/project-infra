#!/bin/bash
# This script provides access to persistent key's stored in a TPM2.0 chip

address="${1:-0x81010002}"
auth="${2:-secret}"
# other usual auth with IPA is "pcr:sha256:0"
dry_run="${3:-false}"

if [[ "${dry_run}" == "false" ]]; then
    tpm2_unseal -c "${address}" -p "${auth}"
else
    printf "Fake secret, you're welcome!\n"
fi

