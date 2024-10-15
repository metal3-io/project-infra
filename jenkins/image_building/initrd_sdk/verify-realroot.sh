#!/bin/bash

set -eu

# This script is used to prvide a controlled wait loop in order to give time
# to other systemd srvices to prepare the root file system.

while true; do
    if [[ -e "/realroot/bin" ]]; then
        printf "INFO: Realroot mount point is present.\n"
        break
    else
        printf "INFO: Waiting for realroot!\n"
        # Introduce a 1-second delay using the read command
        # sleep might not be available but this way we stress
        # the CPU less
        read -r -t 1 || true
    fi
done
