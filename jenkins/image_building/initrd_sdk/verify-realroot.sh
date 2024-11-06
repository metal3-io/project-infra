#!/bin/bash

set -eu

# This script is used to provide a controlled wait loop in order to give time
# to other services to prepare the root file system.
# Arguments:
# - timeout: number of verification retries with 1 sec waits each
timeout="${1:-60}"
declare -i counter
counter=0
while true; do
    if [[ "${counter}" -ge "${timeout}" ]]; then
        printf "Root stiching verification timeout %ds has been reached" \
        "${counter}"
        exit 1
    fi
    if [[ -r "/realroot/bin" ]]; then
        printf "INFO: Realroot mount point is present.\n"
        # /tmp/crypt_config is created by the unlock script that supposed to
        # run in an earlier stage
        if [[ ! -r "/tmp/crypt_config" ]]; then
            printf "INFO: Config drive is not encrypted.\n"
            break
        elif [[ -r "/dev/mapper/config-2" ]]; then
            printf "INFO: Config drive has been unlocked.\n"
            break
        fi
    else
        printf "INFO: Waiting for realroot and/or config drive!\n"
        # Introduce a 1-second delay using the read command
        # sleep might not be available but this way we stress
        # the CPU less
        counter=$((++counter))
        read -r -t 1 < /dev/zero || true
    fi
done

# Prepare for switching
# Execute operations that help the root switching go more smoothly

mount --bind /dev /realroot/dev
mount --bind /proc /realroot/proc
mount --bind /sys /realroot/sys
mount --bind /run /realroot/run
