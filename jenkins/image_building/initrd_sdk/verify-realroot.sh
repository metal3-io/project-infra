#!/bin/bash

set -eu

# This script is used to prvide a controlled wait loop in order to give time
# to other systemd srvices to prepare the root file system.

while true; do
    if [[ -e "/realroot/bin" ]]; then
        printf "INFO: Realroot mount point is present.\n"
        # /tmp/crypt_config is created by the unlock script that supposed to
        # run in an earlier stage
        if [[ ! -e "/tmp/crypt_config"  ]]; then
            printf "INFO: Config drive is not encrypted.\n"
            break
        elif [[ -e "/dev/mapper/config-2" ]]; then
            printf "INFO: Config drive has been unlocked.\n"
            break
        fi
    else
        printf "INFO: Waiting for realroot and/or config drive!\n"
        # Introduce a 1-second delay using the read command
        # sleep might not be available but this way we stress
        # the CPU less
        read -r -t 1 < /dev/zero || true
    fi
done
